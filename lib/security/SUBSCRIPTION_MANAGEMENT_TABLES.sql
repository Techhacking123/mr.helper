-- ==========================================
-- SUBSCRIPTION MANAGEMENT SYSTEM
-- ==========================================
-- INSTRUCTIONS:
-- 1. Copy this ENTIRE file
-- 2. Paste in Supabase SQL Editor
-- 3. Click "RUN"
-- ==========================================

-- Create subscription history table
CREATE TABLE IF NOT EXISTS subscription_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('activated', 'renewed', 'expired', 'cancelled_by_admin', 'cancelled_by_user')),
  previous_status BOOLEAN,
  new_status BOOLEAN,
  previous_expiry TIMESTAMPTZ,
  new_expiry TIMESTAMPTZ,
  payment_id TEXT,
  amount DECIMAL(10, 2),
  admin_id UUID REFERENCES users(id),  -- Admin who performed action
  cancellation_reason TEXT,  -- Why was it cancelled
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_subscription_history_provider 
ON subscription_history(provider_id);

CREATE INDEX IF NOT EXISTS idx_subscription_history_action 
ON subscription_history(action);

CREATE INDEX IF NOT EXISTS idx_subscription_history_created 
ON subscription_history(created_at DESC);

-- Add cancellation fields to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS cancelled_by_admin BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS cancellation_reason TEXT,
ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS cancelled_by_admin_id UUID REFERENCES users(id);

-- Function to log subscription changes automatically
CREATE OR REPLACE FUNCTION log_subscription_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only log if subscription fields changed
  IF (OLD.is_subscribed IS DISTINCT FROM NEW.is_subscribed) OR 
     (OLD.subscription_expiry IS DISTINCT FROM NEW.subscription_expiry) THEN
    
    INSERT INTO subscription_history (
      provider_id,
      action,
      previous_status,
      new_status,
      previous_expiry,
      new_expiry,
      created_at
    ) VALUES (
      NEW.id,
      CASE
        WHEN NEW.cancelled_by_admin = TRUE THEN 'cancelled_by_admin'
        WHEN OLD.is_subscribed = FALSE AND NEW.is_subscribed = TRUE THEN 'activated'
        WHEN OLD.is_subscribed = TRUE AND NEW.is_subscribed = TRUE THEN 'renewed'
        WHEN NEW.is_subscribed = FALSE THEN 'expired'
        ELSE 'updated'
      END,
      OLD.is_subscribed,
      NEW.is_subscribed,
      OLD.subscription_expiry,
      NEW.subscription_expiry,
      NOW()
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for automatic logging
DROP TRIGGER IF EXISTS subscription_change_logger ON users;
CREATE TRIGGER subscription_change_logger
AFTER UPDATE ON users
FOR EACH ROW
WHEN (OLD.is_subscribed IS DISTINCT FROM NEW.is_subscribed OR 
      OLD.subscription_expiry IS DISTINCT FROM NEW.subscription_expiry)
EXECUTE FUNCTION log_subscription_change();

-- Function for admin to cancel subscription
CREATE OR REPLACE FUNCTION admin_cancel_subscription(
  p_provider_id UUID,
  p_admin_id UUID,
  p_reason TEXT
)
RETURNS JSON AS $$
DECLARE
  v_result JSON;
  v_previous_status BOOLEAN;
  v_previous_expiry TIMESTAMPTZ;
BEGIN
  -- Get current subscription status
  SELECT is_subscribed, subscription_expiry
  INTO v_previous_status, v_previous_expiry
  FROM users
  WHERE id = p_provider_id AND is_provider = TRUE;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Provider not found');
  END IF;
  
  -- Cancel subscription
  UPDATE users
  SET 
    is_subscribed = FALSE,
    subscription_expiry = NULL,
    cancelled_by_admin = TRUE,
    cancellation_reason = p_reason,
    cancelled_at = NOW(),
    cancelled_by_admin_id = p_admin_id
  WHERE id = p_provider_id;
  
  -- Log to history
  INSERT INTO subscription_history (
    provider_id,
    action,
    previous_status,
    new_status,
    previous_expiry,
    new_expiry,
    admin_id,
    cancellation_reason
  ) VALUES (
    p_provider_id,
    'cancelled_by_admin',
    v_previous_status,
    FALSE,
    v_previous_expiry,
    NULL,
    p_admin_id,
    p_reason
  );
  
  -- Send notification to provider
  INSERT INTO notifications (user_id, message, is_read, created_at)
  VALUES (
    p_provider_id,
    'Mr.Helper cancelled your subscription. Reason: ' || p_reason || '. Please renew your subscription or contact us.',
    FALSE,
    NOW()
  );
  
  v_result := json_build_object(
    'success', true,
    'message', 'Subscription cancelled successfully',
    'provider_id', p_provider_id,
    'previous_status', v_previous_status,
    'previous_expiry', v_previous_expiry
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get subscription statistics
CREATE OR REPLACE FUNCTION get_subscription_stats()
RETURNS JSON AS $$
DECLARE
  v_stats JSON;
BEGIN
  SELECT json_build_object(
    'total_providers', COUNT(*),
    'active_subscriptions', COUNT(*) FILTER (WHERE is_subscribed = TRUE AND subscription_expiry > NOW()),
    'expired_subscriptions', COUNT(*) FILTER (WHERE is_subscribed = TRUE AND subscription_expiry <= NOW()),
    'never_subscribed', COUNT(*) FILTER (WHERE is_subscribed = FALSE OR is_subscribed IS NULL),
    'cancelled_by_admin', COUNT(*) FILTER (WHERE cancelled_by_admin = TRUE),
    'total_revenue_estimation', COALESCE(SUM(CASE WHEN is_subscribed = TRUE THEN 149.00 ELSE 0 END), 0)
  )
  INTO v_stats
  FROM users
  WHERE is_provider = TRUE;
  
  RETURN v_stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Success message
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE '✅ SUBSCRIPTION MANAGEMENT SYSTEM CREATED!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Created:';
  RAISE NOTICE '  ✅ subscription_history table';
  RAISE NOTICE '  ✅ Automatic change logging';
  RAISE NOTICE '  ✅ Admin cancellation function';
  RAISE NOTICE '  ✅ Statistics function';
  RAISE NOTICE '';
  RAISE NOTICE 'Next: Create admin subscription management page';
  RAISE NOTICE '================================================';
END $$;
