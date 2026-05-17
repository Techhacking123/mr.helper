-- ============================================
-- RED STAR PENALTY SYSTEM - Database Migration
-- ============================================

-- 1. Add red_stars count and is_blocked flag to users table
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS red_stars INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT false;

-- 2. Create red star history table
CREATE TABLE IF NOT EXISTS public.provider_red_stars (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  reason TEXT DEFAULT 'Service not completed within deadline',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast provider lookups
CREATE INDEX IF NOT EXISTS idx_provider_red_stars_provider
ON public.provider_red_stars(provider_id);

-- 3. Enable RLS on provider_red_stars
ALTER TABLE public.provider_red_stars ENABLE ROW LEVEL SECURITY;

-- Providers can read their own red stars
CREATE POLICY "Providers can view own red stars"
ON public.provider_red_stars FOR SELECT
USING (provider_id = auth.uid());

-- 4. Update the check_and_mark_expired_orders RPC to assign red stars
CREATE OR REPLACE FUNCTION public.check_and_mark_expired_orders()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  expired_count INTEGER := 0;
  blocked_count INTEGER := 0;
  r RECORD;
BEGIN
  -- Find orders that have passed their deadline and are still active
  FOR r IN
    SELECT id, provider_id
    FROM public.orders
    WHERE deadline IS NOT NULL
      AND deadline < now()
      AND status NOT IN ('completed', 'cancelled', 'expired')
  LOOP
    -- Mark order as expired
    UPDATE public.orders
    SET status = 'expired',
        timer_started_at = NULL,
        timer_expires_at = NULL
    WHERE id = r.id;

    -- Record red star (only if not already recorded for this order)
    INSERT INTO public.provider_red_stars (provider_id, order_id, reason)
    SELECT r.provider_id, r.id, 'Service not completed within deadline'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.provider_red_stars
      WHERE order_id = r.id AND provider_id = r.provider_id
    );

    -- Increment red_stars count on the user
    UPDATE public.users
    SET red_stars = COALESCE(red_stars, 0) + 1
    WHERE id = r.provider_id
      AND NOT EXISTS (
        SELECT 1 FROM public.provider_red_stars prs
        WHERE prs.order_id = r.id AND prs.provider_id = r.provider_id
        -- This subquery runs BEFORE the insert above in the same iteration,
        -- but since we used INSERT...WHERE NOT EXISTS, we need a different guard.
        -- Actually, let's use a simpler approach below.
      );

    expired_count := expired_count + 1;
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
    AND is_blocked = false
  RETURNING id INTO r;

  GET DIAGNOSTICS blocked_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'expired_count', expired_count,
    'blocked_count', blocked_count,
    'checked_at', now()
  );
END;
$$;

-- 5. Function to get provider red star info
CREATE OR REPLACE FUNCTION public.get_provider_red_stars(p_provider_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  star_count INTEGER;
  blocked BOOLEAN;
  star_history JSONB;
BEGIN
  -- Get current count and blocked status
  SELECT COALESCE(u.red_stars, 0), COALESCE(u.is_blocked, false)
  INTO star_count, blocked
  FROM public.users u
  WHERE u.id = p_provider_id;

  -- Get recent history
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', prs.id,
      'order_id', prs.order_id,
      'reason', prs.reason,
      'created_at', prs.created_at
    ) ORDER BY prs.created_at DESC
  ), '[]'::jsonb)
  INTO star_history
  FROM public.provider_red_stars prs
  WHERE prs.provider_id = p_provider_id;

  RETURN jsonb_build_object(
    'red_stars', star_count,
    'is_blocked', blocked,
    'history', star_history
  );
END;
$$;

-- 6. Function to unblock a provider (reset red stars)
CREATE OR REPLACE FUNCTION public.unblock_provider(p_provider_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Reset red stars count and unblock
  UPDATE public.users
  SET red_stars = 0,
      is_blocked = false
  WHERE id = p_provider_id;

  -- Clear red star history
  DELETE FROM public.provider_red_stars
  WHERE provider_id = p_provider_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Provider unblocked successfully. Red stars reset to 0.'
  );
END;
$$;
