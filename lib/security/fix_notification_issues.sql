-- ==========================================
-- FIX FOR PUSH NOTIFICATION ISSUES
-- ==========================================
-- Issue 1: Double notifications when provider sends offer
-- Issue 2: No notification when service is completed

-- SOLUTION FOR ISSUE 2: Add notification to complete_order_and_pay function
-- ==========================================

CREATE OR REPLACE FUNCTION complete_order_and_pay(
  p_order_id UUID,
  p_provider_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order_status TEXT;
  v_amount NUMERIC;
  v_provider_id_in_order UUID;
  v_buyer_id UUID;
  v_provider_name TEXT;
BEGIN
  -- 1. Lock the order row to prevent race conditions
  -- Fetch price, buyer_id, falling back to user_price if price is NULL
  SELECT status, COALESCE(price, user_price, 0), provider_id, buyer_id
  INTO v_order_status, v_amount, v_provider_id_in_order, v_buyer_id
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  -- 2. Verify Order Exists
  IF v_order_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  -- 3. Verify Provider matches (Security check)
  IF v_provider_id_in_order IS DISTINCT FROM p_provider_id THEN
     RETURN jsonb_build_object('success', false, 'error', 'Not authorized for this order');
  END IF;

  -- 4. Verify Status (prevent duplicates)
  IF v_order_status = 'completed' THEN
     RETURN jsonb_build_object('success', false, 'error', 'Order already completed');
  END IF;

  IF v_order_status = 'cancelled' THEN
     RETURN jsonb_build_object('success', false, 'error', 'Order is cancelled. No earnings added.');
  END IF;

  -- 5. Determine Amount (Safety check, though COALESCE handles it)
  IF v_amount IS NULL THEN
     v_amount := 0; 
  END IF;

  -- 6. Update Provider Earnings (total_earnings only)
  -- Monthly earnings are calculated dynamically from subscription_start_date
  UPDATE users
  SET 
    total_earnings = COALESCE(total_earnings, 0) + v_amount
  WHERE id = p_provider_id;

  -- 7. Update Order Status
  UPDATE orders
  SET status = 'completed',
      timer_started_at = NULL,
      timer_expires_at = NULL,
      images = '[]'::jsonb,
      price = v_amount -- Ensure the final price is recorded in the price column for history
  WHERE id = p_order_id;

  -- 8. **NEW: Send notification to user about service completion**
  -- Get provider name for the notification message
  SELECT full_name INTO v_provider_name FROM users WHERE id = p_provider_id;
  
  -- Insert notification for the buyer (this will trigger FCM notification automatically)
  INSERT INTO notifications (user_id, order_id, title, message, is_read, created_at)
  VALUES (
    v_buyer_id,
    p_order_id,
    'Service Completed!',
    COALESCE(v_provider_name, 'The provider') || ' has completed your service. Please review the work and leave feedback!',
    false,
    NOW()
  );

  -- 9. Return success
  RETURN jsonb_build_object('success', true, 'amount_added', v_amount);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

COMMENT ON FUNCTION complete_order_and_pay(UUID, UUID) IS 
'Complete order, update provider earnings, and notify buyer about service completion';
