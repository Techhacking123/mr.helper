-- ========================================
-- ORDER STATUS & TIMER MANAGEMENT SYSTEM
-- ========================================
-- This migration adds:
-- 1. New order statuses: working, cancelled, expired
-- 2. Timer tracking for 24-hour countdown
-- 3. Fine management for providers
-- 4. Automated expiry handling

-- ========================================
-- Step 1: Add timer and status fields to orders table
-- ========================================

-- Add timer tracking columns
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS timer_started_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS timer_expires_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS timer_reset_count INTEGER DEFAULT 0;

-- Add column to track if fine was applied
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS fine_applied BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS fine_amount DECIMAL(10, 2) DEFAULT 0;

-- ========================================
-- Step 2: Create provider_fines table
-- ========================================

CREATE TABLE IF NOT EXISTS provider_fines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  fine_amount DECIMAL(10, 2) NOT NULL DEFAULT 50.00,
  reason TEXT,
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  paid BOOLEAN DEFAULT FALSE,
  paid_at TIMESTAMPTZ,
  subscription_payment_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_provider_fines_provider_id ON provider_fines(provider_id);
CREATE INDEX IF NOT EXISTS idx_provider_fines_paid ON provider_fines(paid);
CREATE INDEX IF NOT EXISTS idx_provider_fines_order_id ON provider_fines(order_id);

-- ========================================
-- Step 3: Add total_fines tracking to users table
-- ========================================

ALTER TABLE users
ADD COLUMN IF NOT EXISTS total_unpaid_fines DECIMAL(10, 2) DEFAULT 0;

-- ========================================
-- Step 4: Enable RLS on provider_fines
-- ========================================

ALTER TABLE provider_fines ENABLE ROW LEVEL SECURITY;

-- Providers can view their own fines
CREATE POLICY "Providers can view own fines"
ON provider_fines FOR SELECT
USING (auth.uid() = provider_id);

-- Allow service_role (backend) to insert fines
-- For now, we'll allow authenticated users to view fines for testing
-- In production, you may want to restrict this further
CREATE POLICY "Allow select for authenticated users"
ON provider_fines FOR SELECT
USING (auth.role() = 'authenticated');

-- ========================================
-- Step 5: Create function to start timer
-- ========================================

CREATE OR REPLACE FUNCTION start_order_timer(order_id_param UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE orders
  SET 
    timer_started_at = NOW(),
    timer_expires_at = NOW() + INTERVAL '24 hours'
  WHERE id = order_id_param;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- Step 6: Create function to reset timer
-- ========================================

CREATE OR REPLACE FUNCTION reset_order_timer(order_id_param UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE orders
  SET 
    timer_started_at = NOW(),
    timer_expires_at = NOW() + INTERVAL '24 hours',
    timer_reset_count = COALESCE(timer_reset_count, 0) + 1,
    status = 'working'
  WHERE id = order_id_param;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- Step 7: Create function to apply fine for expired order
-- ========================================

CREATE OR REPLACE FUNCTION apply_expiry_fine(order_id_param UUID)
RETURNS VOID AS $$
DECLARE
  v_provider_id UUID;
  v_fine_amount DECIMAL(10, 2) := 50.00;
BEGIN
  -- Get provider_id from order
  SELECT provider_id INTO v_provider_id
  FROM orders
  WHERE id = order_id_param;

  -- Only apply if not already applied
  UPDATE orders
  SET 
    status = 'expired',
    fine_applied = TRUE,
    fine_amount = v_fine_amount
  WHERE id = order_id_param
  AND fine_applied = FALSE;

  -- Insert fine record
  IF FOUND THEN
    INSERT INTO provider_fines (provider_id, order_id, fine_amount, reason)
    VALUES (
      v_provider_id,
      order_id_param,
      v_fine_amount,
      'Order expired - No action taken within 24 hours'
    );

    -- Update provider's total unpaid fines
    UPDATE users
    SET total_unpaid_fines = COALESCE(total_unpaid_fines, 0) + v_fine_amount
    WHERE id = v_provider_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- Step 8: Create function to calculate total fines for provider
-- ========================================

CREATE OR REPLACE FUNCTION get_provider_unpaid_fines(provider_id_param UUID)
RETURNS DECIMAL(10, 2) AS $$
DECLARE
  total DECIMAL(10, 2);
BEGIN
  SELECT COALESCE(SUM(fine_amount), 0) INTO total
  FROM provider_fines
  WHERE provider_id = provider_id_param
  AND paid = FALSE;
  
  RETURN total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- Step 9: Create function to mark fines as paid
-- ========================================

CREATE OR REPLACE FUNCTION mark_fines_paid(provider_id_param UUID, payment_id_param UUID)
RETURNS VOID AS $$
BEGIN
  -- Mark all unpaid fines as paid
  UPDATE provider_fines
  SET 
    paid = TRUE,
    paid_at = NOW(),
    subscription_payment_id = payment_id_param
  WHERE provider_id = provider_id_param
  AND paid = FALSE;

  -- Reset provider's total unpaid fines
  UPDATE users
  SET total_unpaid_fines = 0
  WHERE id = provider_id_param;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- Step 10: Create view for active order timers
-- ========================================

CREATE OR REPLACE VIEW active_order_timers AS
SELECT 
  o.id,
  o.buyer_id,
  o.provider_id,
  o.status,
  o.timer_started_at,
  o.timer_expires_at,
  o.timer_reset_count,
  o.fine_applied,
  EXTRACT(EPOCH FROM (o.timer_expires_at - NOW())) AS seconds_remaining,
  CASE 
    WHEN o.timer_expires_at < NOW() THEN TRUE
    ELSE FALSE
  END AS is_expired
FROM orders o
WHERE o.status IN ('verified', 'working')
AND o.timer_expires_at IS NOT NULL;

-- ========================================
-- Step 11: Grant permissions
-- ========================================

GRANT SELECT ON active_order_timers TO authenticated;
GRANT EXECUTE ON FUNCTION start_order_timer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_order_timer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION apply_expiry_fine(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION get_provider_unpaid_fines(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_fines_paid(UUID, UUID) TO service_role;

-- ========================================
-- COMMENTS
-- ========================================

COMMENT ON TABLE provider_fines IS 'Tracks fines applied to providers for expired orders';
COMMENT ON COLUMN orders.timer_started_at IS 'When the 24-hour timer was started (after verification)';
COMMENT ON COLUMN orders.timer_expires_at IS 'When the 24-hour timer expires';
COMMENT ON COLUMN orders.timer_reset_count IS 'Number of times user clicked "Working" to reset timer';
COMMENT ON COLUMN orders.fine_applied IS 'Whether a fine was applied for this order';
COMMENT ON FUNCTION start_order_timer IS 'Starts the 24-hour countdown timer for an order';
COMMENT ON FUNCTION reset_order_timer IS 'Resets the timer when user clicks "Working"';
COMMENT ON FUNCTION apply_expiry_fine IS 'Applies ₹50 fine when order expires without user action';
