-- 1. Ensure subscription_start_date exists (useful if not already present)
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_start_date TIMESTAMP WITH TIME ZONE;

-- 2. Function to get Current Week's Earnings (based on subscription start day)
CREATE OR REPLACE FUNCTION get_provider_current_week_earnings(p_provider_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sub_start TIMESTAMPTZ;
  v_week_start TIMESTAMPTZ;
  v_week_end TIMESTAMPTZ;
  v_earnings NUMERIC(10, 2);
  v_day_of_week INT;
BEGIN
  -- Get subscription start date
  SELECT subscription_start_date INTO v_sub_start
  FROM users
  WHERE id = p_provider_id;

  -- If no subscription start, fallback to standard Monday start
  IF v_sub_start IS NULL THEN
    v_week_start := DATE_TRUNC('week', NOW());
  ELSE
    -- Calculate start of the current cycle based on the subscription day of week
    -- Logic: Find the most recent occurrence of the subscription weekday
    -- This is a bit complex in SQL pure arithmetic, simplified approach:
    -- Use interval math relative to NOW()
    
    -- Actually, simple "Monthly" usually just means last 30 days or this calendar month.
    -- But "based on subscription time" means if I bought it on Friday, my week is Fri-Fri.
    
    -- Current Time
    -- Difference in days
    -- We want the range [NOW - (days_since_start % 7), (NOW - (days_since_start % 7)) + 7]
    -- Wait, easier:
    -- v_week_start = NOW() - INTERVAL '1 day' * (MOD(EXTRACT(DAY FROM NOW() - v_sub_start)::INT, 7))
    -- We need to ensure we are looking at the *current* cycle.
    
    v_week_start := NOW() - (MOD(EXTRACT(DAY FROM NOW() - v_sub_start)::INT, 30) || ' days')::INTERVAL;
    -- Flatten to start of day? Maybe user wants exact time. Let's start of day for cleaner reporting.
    v_week_start := DATE_TRUNC('day', v_week_start);
  END IF;

  v_week_end := v_week_start + INTERVAL '30 days';

  -- Sum earnings (completed orders) in this window
  SELECT COALESCE(SUM(price), 0)
  INTO v_earnings
  FROM orders
  WHERE provider_id = p_provider_id
    AND status = 'completed'
    AND updated_at >= v_week_start
    AND updated_at < v_week_end;

  RETURN jsonb_build_object(
    'earnings', v_earnings,
    'start_date', v_week_start,
    'end_date', v_week_end
  );
END;
$$;

-- 3. Function to get Monthly Earnings History (Last 12 months)
CREATE OR REPLACE FUNCTION get_provider_earnings_history(p_provider_id UUID)
RETURNS TABLE (
  week_start TIMESTAMPTZ,
  week_end TIMESTAMPTZ,
  total_amount NUMERIC(10, 2),
  order_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sub_start TIMESTAMPTZ;
  v_anchor TIMESTAMPTZ;
  i INT;
  v_w_start TIMESTAMPTZ;
  v_w_end TIMESTAMPTZ;
BEGIN
  SELECT subscription_start_date INTO v_sub_start
  FROM users
  WHERE id = p_provider_id;

  IF v_sub_start IS NULL THEN
    v_anchor := DATE_TRUNC('week', NOW());
  ELSE
    v_anchor := NOW() - (MOD(EXTRACT(DAY FROM NOW() - v_sub_start)::INT, 30) || ' days')::INTERVAL;
    v_anchor := DATE_TRUNC('day', v_anchor);
  END IF;

  -- Generate last 12 weeks
  FOR i IN 0..11 LOOP
    v_w_start := v_anchor - (i * 30 || ' days')::INTERVAL;
    v_w_end := v_w_start + INTERVAL '30 days';
    
    RETURN QUERY
    SELECT 
      v_w_start,
      v_w_end,
      COALESCE(SUM(price), 0),
      COUNT(*)
    FROM orders
    WHERE provider_id = p_provider_id
      AND status = 'completed'
      AND updated_at >= v_w_start
      AND updated_at < v_w_end;
  END LOOP;
END;
$$;
