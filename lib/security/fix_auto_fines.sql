-- Function to check and apply fines for ALL expired orders
-- This should be called periodically (e.g., whenever a provider opens the app)

CREATE OR REPLACE FUNCTION check_and_apply_all_fines()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_expired_order RECORD;
  v_fine_amount NUMERIC := 50.0; -- Default Fine Amount
  v_count INTEGER := 0;
BEGIN
  -- Loop through all orders that are expired but haven't had a fine applied yet
  -- We assume a fine is applied if there is an entry in 'provider_fines' for this order
  FOR v_expired_order IN
    SELECT o.id, o.provider_id, o.status, o.timer_expires_at
    FROM orders o
    WHERE (o.status = 'verified' OR o.status = 'working')
      AND o.timer_expires_at IS NOT NULL
      AND o.timer_expires_at < NOW()
      AND NOT EXISTS (
        SELECT 1 FROM provider_fines pf WHERE pf.order_id = o.id
      )
  LOOP
    -- 1. Insert Fine Record
    INSERT INTO provider_fines (
      provider_id,
      order_id,
      amount,
      reason,
      status, -- 'unpaid'
      applied_at
    ) VALUES (
      v_expired_order.provider_id,
      v_expired_order.id,
      v_fine_amount,
      'Order expired without action (24hr rule)',
      'unpaid',
      NOW()
    );

    -- 2. Send Notification to Provider
    INSERT INTO notifications (
      user_id,
      order_id,
      message,
      is_read
    ) VALUES (
      v_expired_order.provider_id,
      v_expired_order.id,
      format('⚠️ A fine of ₹%s has been applied because order #%s expired without update. Please complete or cancel orders on time.', v_fine_amount, left(v_expired_order.id::text, 8)),
      false
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'fines_applied', v_count);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
