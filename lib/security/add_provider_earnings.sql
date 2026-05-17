-- Add total_earnings column to users table (Using users table as providers are stored here)
-- Using NUMERIC(10,2) for currency
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_earnings NUMERIC(10, 2) DEFAULT 0;

-- Function to safely complete order and update earnings transactionally
-- This prevents race conditions and ensures earnings are only added once.
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
BEGIN
  -- 1. Lock the order row to prevent race conditions
  SELECT status, price, provider_id INTO v_order_status, v_amount, v_provider_id_in_order
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

  -- 5. Determine Amount
  IF v_amount IS NULL THEN
     v_amount := 0; 
  END IF;

  -- 6. Update Provider Earnings
  UPDATE users
  SET total_earnings = COALESCE(total_earnings, 0) + v_amount
  WHERE id = p_provider_id;

  -- 7. Update Order Status
  -- Also clear timer fields as per previous logic in OrderTimerManager
  UPDATE orders
  SET status = 'completed',
      timer_started_at = NULL,
      timer_expires_at = NULL,
      images = '[]'::jsonb -- Clear images if per previous logic, but maybe optional? Keeping it consistent.
  WHERE id = p_order_id;

  -- 8. Return success
  RETURN jsonb_build_object('success', true, 'amount_added', v_amount);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
