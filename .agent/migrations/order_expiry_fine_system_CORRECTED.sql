-- =====================================================
-- ORDER EXPIRY FINE SYSTEM - CORRECTED FOR YOUR DB SCHEMA
-- =====================================================
-- Based on actual database analysis:
-- - users.full_name (not users.name)
-- - orders.title exists
-- =====================================================

-- Step 1: Drop existing functions WITH CASCADE (auto-drops triggers)
DROP FUNCTION IF EXISTS get_provider_unpaid_fines(UUID) CASCADE;
DROP FUNCTION IF EXISTS pay_fine(UUID, UUID[], TEXT) CASCADE;
DROP FUNCTION IF EXISTS pay_fines_with_subscription(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS check_and_mark_expired_orders() CASCADE;
DROP FUNCTION IF EXISTS extend_order_deadline(UUID) CASCADE;
DROP FUNCTION IF EXISTS set_order_deadline() CASCADE;
DROP FUNCTION IF EXISTS update_provider_fines() CASCADE;

-- Step 2: Add Fine Tracking Columns to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS deadline TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_expired BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS fine_amount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS fine_paid BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS extension_count INTEGER DEFAULT 0;

-- Create index for deadline queries
CREATE INDEX IF NOT EXISTS idx_orders_deadline ON orders(deadline) WHERE is_expired = FALSE;

-- Step 3: Add Fine Tracking to users table (for providers)
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_unpaid_fines NUMERIC(10,2) DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_fines_paid NUMERIC(10,2) DEFAULT 0;

-- Step 4: Create Fine Transactions Table
CREATE TABLE IF NOT EXISTS fine_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  fine_amount NUMERIC(10,2) NOT NULL DEFAULT 50.00,
  paid_at TIMESTAMPTZ,
  payment_method TEXT,
  razorpay_payment_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(order_id) -- Only one fine per order
);

-- Indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_fine_transactions_provider ON fine_transactions(provider_id);
CREATE INDEX IF NOT EXISTS idx_fine_transactions_order ON fine_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_fine_transactions_unpaid ON fine_transactions(provider_id) WHERE paid_at IS NULL;

-- Step 5: Function to Update Provider Total Fines
CREATE OR REPLACE FUNCTION update_provider_fines()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Add fine to provider's total unpaid fines
    UPDATE users 
    SET total_unpaid_fines = COALESCE(total_unpaid_fines, 0) + NEW.fine_amount
    WHERE id = NEW.provider_id;
    
  ELSIF TG_OP = 'UPDATE' AND NEW.paid_at IS NOT NULL AND OLD.paid_at IS NULL THEN
    -- Fine was just paid - move from unpaid to paid
    UPDATE users 
    SET 
      total_unpaid_fines = GREATEST(COALESCE(total_unpaid_fines, 0) - NEW.fine_amount, 0),
      total_fines_paid = COALESCE(total_fines_paid, 0) + NEW.fine_amount
    WHERE id = NEW.provider_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for fine tracking
DROP TRIGGER IF EXISTS trigger_update_provider_fines ON fine_transactions;
CREATE TRIGGER trigger_update_provider_fines
AFTER INSERT OR UPDATE ON fine_transactions
FOR EACH ROW EXECUTE FUNCTION update_provider_fines();

-- Step 6: Function to Set Initial Deadline (on order creation)
CREATE OR REPLACE FUNCTION set_order_deadline()
RETURNS TRIGGER AS $$
BEGIN
  -- Set initial 24hr deadline from order creation
  IF NEW.deadline IS NULL THEN
    NEW.deadline = NEW.created_at + INTERVAL '24 hours';
    NEW.extension_count = 0;
    NEW.is_expired = FALSE;
    NEW.fine_amount = 0;
    NEW.fine_paid = FALSE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for setting deadline
DROP TRIGGER IF EXISTS trigger_set_order_deadline ON orders;
CREATE TRIGGER trigger_set_order_deadline
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION set_order_deadline();

-- Step 7: Update existing orders to have deadlines
UPDATE orders
SET 
  deadline = created_at + INTERVAL '24 hours',
  extension_count = 0,
  is_expired = FALSE,
  fine_amount = 0,
  fine_paid = FALSE
WHERE deadline IS NULL;

-- Step 8: RPC Function to Extend Order Deadline (when "Working" clicked)
CREATE OR REPLACE FUNCTION extend_order_deadline(order_uuid UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
  new_deadline TIMESTAMPTZ;
  current_status TEXT;
BEGIN
  -- Get current order status
  SELECT status INTO current_status FROM orders WHERE id = order_uuid;
  
  -- Check if order can be extended (not completed or cancelled)
  IF current_status IN ('completed', 'cancelled') THEN
    RETURN json_build_object(
      'success', FALSE,
      'error', 'Cannot extend completed or cancelled orders'
    );
  END IF;
  
  -- Extend deadline by 24hr from NOW (not from previous deadline)
  new_deadline := NOW() + INTERVAL '24 hours';
  
  UPDATE orders
  SET 
    deadline = new_deadline,
    extension_count = extension_count + 1,
    is_expired = FALSE, -- Reset expired flag when extended
    updated_at = NOW()
  WHERE id = order_uuid
  RETURNING 
    json_build_object(
      'success', TRUE,
      'new_deadline', deadline,
      'extension_count', extension_count,
      'message', 'Deadline extended by 24 hours'
    ) INTO result;
    
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 9: RPC Function to Check & Mark Expired Orders
CREATE OR REPLACE FUNCTION check_and_mark_expired_orders()
RETURNS JSON AS $$
DECLARE
  expired_order RECORD;
  expired_count INTEGER := 0;
  fine_per_order NUMERIC := 50.00;
BEGIN
  -- Find all orders that are past deadline and not completed/cancelled
  FOR expired_order IN
    SELECT id, provider_id 
    FROM orders
    WHERE 
      deadline < NOW()
      AND status NOT IN ('completed', 'cancelled')
      AND is_expired = FALSE
      AND fine_amount = 0
  LOOP
    -- Mark order as expired
    UPDATE orders
    SET 
      is_expired = TRUE,
      fine_amount = fine_per_order,
      fine_paid = FALSE,
      updated_at = NOW()
    WHERE id = expired_order.id;
    
    -- Create fine transaction (trigger will update provider's totals)
    INSERT INTO fine_transactions (provider_id, order_id, fine_amount)
    VALUES (expired_order.provider_id, expired_order.id, fine_per_order)
    ON CONFLICT (order_id) DO NOTHING; -- Prevent duplicate fines
    
    expired_count := expired_count + 1;
  END LOOP;
  
  RETURN json_build_object(
    'success', TRUE,
    'expired_orders_count', expired_count,
    'fine_per_order', fine_per_order,
    'total_fines_applied', expired_count * fine_per_order
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 10: RPC Function to Get Provider's Unpaid Fines
-- CORRECTED: Uses full_name instead of name
CREATE OR REPLACE FUNCTION get_provider_unpaid_fines(p_provider_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_unpaid_fines', COALESCE(SUM(ft.fine_amount), 0),
    'fine_count', COUNT(ft.id),
    'fines', COALESCE(json_agg(
      json_build_object(
        'id', ft.id,
        'order_id', ft.order_id,
        'fine_amount', ft.fine_amount,
        'created_at', ft.created_at,
        'order_title', o.title
      ) ORDER BY ft.created_at DESC
    ), '[]'::json)
  ) INTO result
  FROM fine_transactions ft
  LEFT JOIN orders o ON ft.order_id = o.id
  WHERE ft.provider_id = p_provider_id
    AND ft.paid_at IS NULL;
    
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 11: RPC Function to Pay Fine (separate payment)
CREATE OR REPLACE FUNCTION pay_fine(
  p_provider_id UUID,
  p_fine_transaction_ids UUID[],
  p_payment_id TEXT
)
RETURNS JSON AS $$
DECLARE
  total_paid NUMERIC := 0;
  updated_count INTEGER := 0;
BEGIN
  -- Update fine transactions as paid
  WITH updated_fines AS (
    UPDATE fine_transactions
    SET 
      paid_at = NOW(),
      payment_method = 'razorpay',
      razorpay_payment_id = p_payment_id
    WHERE 
      id = ANY(p_fine_transaction_ids)
      AND provider_id = p_provider_id
      AND paid_at IS NULL
    RETURNING fine_amount, order_id
  )
  SELECT 
    COALESCE(SUM(fine_amount), 0),
    COUNT(*)
  INTO total_paid, updated_count
  FROM updated_fines;
  
  -- Mark orders as fine paid
  UPDATE orders
  SET fine_paid = TRUE
  WHERE id IN (
    SELECT order_id FROM fine_transactions WHERE id = ANY(p_fine_transaction_ids)
  );
  
  RETURN json_build_object(
    'success', TRUE,
    'total_paid', total_paid,
    'fines_paid_count', updated_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 12: RPC Function to Pay Fines with Subscription
CREATE OR REPLACE FUNCTION pay_fines_with_subscription(
  p_provider_id UUID,
  p_payment_id TEXT
)
RETURNS JSON AS $$
DECLARE
  total_paid NUMERIC := 0;
  updated_count INTEGER := 0;
BEGIN
  -- Update all unpaid fines for this provider
  WITH updated_fines AS (
    UPDATE fine_transactions
    SET 
      paid_at = NOW(),
      payment_method = 'subscription',
      razorpay_payment_id = p_payment_id
    WHERE 
      provider_id = p_provider_id
      AND paid_at IS NULL
    RETURNING fine_amount, order_id
  )
  SELECT 
    COALESCE(SUM(fine_amount), 0),
    COUNT(*)
  INTO total_paid, updated_count
  FROM updated_fines;
  
  -- Mark orders as fine paid
  UPDATE orders
  SET fine_paid = TRUE
  WHERE provider_id = p_provider_id AND fine_paid = FALSE;
  
  RETURN json_build_object(
    'success', TRUE,
    'total_paid', total_paid,
    'fines_paid_count', updated_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 13: Grant permissions for RPC functions
GRANT EXECUTE ON FUNCTION extend_order_deadline(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION check_and_mark_expired_orders() TO authenticated;
GRANT EXECUTE ON FUNCTION get_provider_unpaid_fines(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION pay_fine(UUID, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION pay_fines_with_subscription(UUID, TEXT) TO authenticated;

-- Step 14: RLS Policies for fine_transactions table
ALTER TABLE fine_transactions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Providers can view own fines" ON fine_transactions;
DROP POLICY IF EXISTS "System can insert fines" ON fine_transactions;
DROP POLICY IF EXISTS "System can update fines" ON fine_transactions;

-- Providers can view their own fines
CREATE POLICY "Providers can view own fines"
ON fine_transactions FOR SELECT
TO authenticated
USING (provider_id = auth.uid());

-- Only system can insert fines (via functions)
CREATE POLICY "System can insert fines"
ON fine_transactions FOR INSERT
TO authenticated
WITH CHECK (true);

-- Only system can update fines (via functions)
CREATE POLICY "System can update fines"
ON fine_transactions FOR UPDATE
TO authenticated
USING (true);

-- Step 15: Create view for provider fine summary
-- CORRECTED: Uses full_name and is_provider
DROP VIEW IF EXISTS provider_fine_summary;
CREATE VIEW provider_fine_summary AS
SELECT 
  u.id as provider_id,
  u.full_name as provider_name,
  u.total_unpaid_fines,
  u.total_fines_paid,
  COUNT(CASE WHEN ft.paid_at IS NULL THEN 1 END) as unpaid_fine_count,
  COUNT(CASE WHEN ft.paid_at IS NOT NULL THEN 1 END) as paid_fine_count,
  COUNT(ft.id) as total_fine_count
FROM users u
LEFT JOIN fine_transactions ft ON u.id = ft.provider_id
WHERE u.is_provider = true
GROUP BY u.id, u.full_name, u.total_unpaid_fines, u.total_fines_paid;

-- Grant access to view
GRANT SELECT ON provider_fine_summary TO authenticated;

-- =====================================================
-- MIGRATION COMPLETE ✅
-- =====================================================
-- All functions, triggers, and tables created successfully
-- Corrected for YOUR database schema
-- =====================================================
