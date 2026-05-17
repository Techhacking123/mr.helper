-- ==========================================
-- QUICK DEBUG: Check Subscription Status
-- ==========================================
-- Run this in Supabase SQL Editor
-- ==========================================

-- 1. Check if subscription columns exist
SELECT 
  column_name, 
  data_type,
  is_nullable
FROM information_schema.columns 
WHERE table_name = 'users' 
AND column_name IN ('is_subscribed', 'subscription_expiry', 'cancelled_by_admin')
ORDER BY column_name;

-- 2. Check all providers and their subscription status
SELECT 
  id,
  full_name,
  is_provider,
  is_subscribed,
  subscription_expiry,
  CASE 
    WHEN is_subscribed = TRUE AND subscription_expiry > NOW()
    THEN '✅ ACTIVE'
    WHEN is_subscribed = TRUE AND subscription_expiry <= NOW()
    THEN '🟠 EXPIRED'
    WHEN is_subscribed = FALSE OR is_subscribed IS NULL
    THEN '❌ NOT SUBSCRIBED'
    ELSE '❓ UNKNOWN'
  END as subscription_status,
  CASE
    WHEN subscription_expiry IS NOT NULL AND subscription_expiry > NOW()
    THEN EXTRACT(DAY FROM (subscription_expiry - NOW())) || ' days left'
    WHEN subscription_expiry IS NOT NULL AND subscription_expiry <= NOW()
    THEN 'Expired ' || EXTRACT(DAY FROM (NOW() - subscription_expiry)) || ' days ago'
    ELSE 'No expiry set'
  END as expiry_info
FROM users
WHERE is_provider = TRUE
ORDER BY is_subscribed DESC NULLS LAST, subscription_expiry DESC NULLS LAST;

-- 3. Count providers by status
SELECT 
  COUNT(*) as total_providers,
  COUNT(*) FILTER (WHERE is_subscribed = TRUE AND subscription_expiry > NOW()) as active,
  COUNT(*) FILTER (WHERE is_subscribed = TRUE AND subscription_expiry <= NOW()) as expired,
  COUNT(*) FILTER (WHERE is_subscribed = FALSE OR is_subscribed IS NULL) as not_subscribed,
  COUNT(*) FILTER (WHERE cancelled_by_admin = TRUE) as cancelled_by_admin
FROM users
WHERE is_provider = TRUE;

-- 4. Check if RPC function exists
SELECT 
  proname as function_name,
  CASE 
    WHEN proname = 'get_subscription_stats' THEN '✅ Stats function exists'
    WHEN proname = 'admin_cancel_subscription' THEN '✅ Cancel function exists'
    ELSE proname
  END as status
FROM pg_proc 
WHERE proname IN ('get_subscription_stats', 'admin_cancel_subscription');

-- 5. Test the stats function directly
SELECT * FROM get_subscription_stats();

-- ==========================================
-- IF NO ACTIVE SUBSCRIPTIONS FOUND:
-- Run this to create a test subscription
-- ==========================================

-- Activate a test provider for 30 days
UPDATE users
SET 
  is_subscribed = TRUE,
  subscription_expiry = NOW() + INTERVAL '30 days',
  cancelled_by_admin = FALSE,
  cancellation_reason = NULL
WHERE is_provider = TRUE
  AND id = (
    SELECT id 
    FROM users 
    WHERE is_provider = TRUE 
    LIMIT 1
  )
RETURNING 
  id, 
  full_name, 
  is_subscribed, 
  subscription_expiry,
  'Provider activated for testing' as message;

-- Verify it worked
SELECT 
  id,
  full_name,
  is_subscribed,
  subscription_expiry,
  EXTRACT(DAY FROM (subscription_expiry - NOW())) as days_remaining
FROM users
WHERE is_provider = TRUE
  AND is_subscribed = TRUE
  AND subscription_expiry > NOW()
LIMIT 5;

-- ==========================================
-- EXPECTED RESULTS
-- ==========================================
-- Query 1: Should show 3 columns (is_subscribed, subscription_expiry, cancelled_by_admin)
-- Query 2: Should list all providers with their status
-- Query 3: Should show counts (if active = 0, need to activate one)
-- Query 4: Should show 2 functions exist
-- Query 5: Should return stats object
-- Update: Should activate 1 provider
-- Final verify: Should show activated provider
