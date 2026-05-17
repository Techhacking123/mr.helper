-- Function for admin to cancel subscription
-- REDEFINED to update ALL subscription related columns
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
  
  -- Cancel subscription - Updating ALL status columns
  UPDATE users
  SET 
    is_subscribed = FALSE,
    subscription_status = 'cancelled',
    subscription_expiry = NOW(), -- Set to now/past instead of NULL to be safe
    subscription_end_date = NOW(), -- Important: Sync with expiry
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
    NOW(),
    p_admin_id,
    p_reason
  );
  
  -- Send notification to provider
  INSERT INTO notifications (user_id, message, is_read, created_at)
  VALUES (
    p_provider_id,
    'Urgent: Your subscription has been cancelled by the admin. Reason: ' || p_reason || '. Please contact support.',
    FALSE,
    NOW()
  );
  
  v_result := json_build_object(
    'success', true,
    'message', 'Subscription cancelled successfully and status updated.',
    'provider_id', p_provider_id,
    'previous_status', v_previous_status
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
