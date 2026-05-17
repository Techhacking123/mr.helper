-- ==========================================
-- EXPIRED ORDERS MONITORING FUNCTION
-- ==========================================
-- This function checks for orders that have passed their deadline
-- and applies fines to providers who haven't completed them

CREATE OR REPLACE FUNCTION check_and_mark_expired_orders()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_expired_order RECORD;
  v_fine_amount NUMERIC := 50.0; -- Default Fine Amount
  v_fines_applied INTEGER := 0;
  v_notifications_sent INTEGER := 0;
BEGIN
  -- Loop through all orders that are expired but haven't had a fine applied yet
  -- An order is expired if deadline has passed and status is not completed/cancelled
  FOR v_expired_order IN
    SELECT 
      o.id AS order_id,
      o.provider_id,
      o.user_id,
      o.status,
      o.deadline,
      o.service_name
    FROM orders o
    WHERE o.deadline < NOW()
      AND o.status NOT IN ('completed', 'cancelled')
      AND o.provider_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 
        FROM provider_fines pf 
        WHERE pf.order_id = o.id
      )
  LOOP
    -- 1. Insert Fine Record
    INSERT INTO provider_fines (
      provider_id,
      order_id,
      amount,
      reason,
      status,
      applied_at
    ) VALUES (
      v_expired_order.provider_id,
      v_expired_order.order_id,
      v_fine_amount,
      'Order expired without completion',
      'unpaid',
      NOW()
    );

    v_fines_applied := v_fines_applied + 1;

    -- 2. Send Notification to Provider
    INSERT INTO notifications (
      user_id,
      order_id,
      title,
      message,
      is_read,
      created_at
    ) VALUES (
      v_expired_order.provider_id,
      v_expired_order.order_id,
      'Fine Applied',
      format('⚠️ A fine of ₹%s has been applied because order "%s" expired without completion. Please complete or cancel orders on time.', 
             v_fine_amount, 
             v_expired_order.service_name),
      false,
      NOW()
    );

    v_notifications_sent := v_notifications_sent + 1;

    -- 3. Update order status to mark it as expired
    UPDATE orders
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = v_expired_order.order_id;

  END LOOP;

  RETURN jsonb_build_object(
    'success', true, 
    'fines_applied', v_fines_applied,
    'notifications_sent', v_notifications_sent
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false, 
    'error', SQLERRM
  );
END;
$$;

-- Add comment for documentation
COMMENT ON FUNCTION check_and_mark_expired_orders() IS 
'Checks for expired orders, applies fines to providers, and sends notifications';
