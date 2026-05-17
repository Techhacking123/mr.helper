-- ============================================
-- 24-HOUR OTP VERIFICATION DEADLINE SYSTEM
-- ============================================
-- When a provider accepts/is approved for an order, a 24-hour countdown begins.
-- If OTP is NOT verified within 24 hours, a red star is automatically applied.

-- 1. Add otp_verification_deadline column to orders table
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS otp_verification_deadline TIMESTAMPTZ;

-- Index for fast queries on orders needing OTP verification
CREATE INDEX IF NOT EXISTS idx_orders_otp_verification_deadline
ON public.orders(otp_verification_deadline)
WHERE otp_verification_deadline IS NOT NULL;

-- 2. Function to check and penalize providers who missed OTP verification deadline
CREATE OR REPLACE FUNCTION public.check_otp_verification_deadlines()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r RECORD;
  penalized_count INTEGER := 0;
  blocked_count INTEGER := 0;
BEGIN
  -- Find orders where:
  -- 1. otp_verification_deadline has passed
  -- 2. Status is still 'accepted' or 'confirmed' (OTP not yet verified)
  -- 3. Provider exists
  FOR r IN
    SELECT id, provider_id, buyer_id
    FROM public.orders
    WHERE otp_verification_deadline IS NOT NULL
      AND otp_verification_deadline < now()
      AND status IN ('accepted', 'confirmed')
      AND provider_id IS NOT NULL
  LOOP
    -- Record red star (only if not already recorded for this order with this reason)
    INSERT INTO public.provider_red_stars (provider_id, order_id, reason)
    SELECT r.provider_id, r.id, 'OTP not verified within 24 hours of acceptance'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.provider_red_stars
      WHERE order_id = r.id AND provider_id = r.provider_id
    );

    -- Change status to expired so we don't process it again and the UI updates
    UPDATE public.orders
    SET status = 'expired'
    WHERE id = r.id;

    penalized_count := penalized_count + 1;

    -- Send notification to provider about the penalty
    INSERT INTO notifications (user_id, order_id, title, message, is_read, created_at)
    VALUES (
      r.provider_id,
      r.id,
      'Red Star Penalty Applied',
      '⚠️ A red star has been applied to your account because OTP was not verified within 24 hours for order #' || left(r.id::text, 8) || '. Please verify orders promptly to avoid penalties.',
      false,
      NOW()
    );

    -- Send notification to buyer about the provider's penalty
    IF r.buyer_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, order_id, title, message, is_read, created_at)
      VALUES (
        r.buyer_id,
        r.id,
        'Provider Penalized',
        'The provider failed to verify the OTP in time for your order. A penalty has been applied to their account for this improper behavior.',
        false,
        NOW()
      );
    END IF;
  END LOOP;

  -- Recalculate red_stars from the history table (accurate count)
  UPDATE public.users u
  SET red_stars = sub.star_count
  FROM (
    SELECT provider_id, COUNT(*) as star_count
    FROM public.provider_red_stars
    GROUP BY provider_id
  ) sub
  WHERE u.id = sub.provider_id
    AND u.red_stars IS DISTINCT FROM sub.star_count;

  -- Auto-block providers with 3+ red stars
  UPDATE public.users
  SET is_blocked = true
  WHERE red_stars >= 3
    AND is_blocked = false;

  GET DIAGNOSTICS blocked_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'penalized_count', penalized_count,
    'blocked_count', blocked_count,
    'checked_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.check_otp_verification_deadlines() IS
'Checks for orders where OTP verification deadline has passed and applies red star penalties to providers.';
