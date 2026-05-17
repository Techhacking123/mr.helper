-- ==========================================
-- FCM TOKEN DEBUG SCRIPT
-- ==========================================
-- Run this to check FCM token configuration
-- ==========================================

-- 1. Check if current user has FCM token
SELECT 
    id,
    full_name,
    fcm_token,
    is_provider,
    subscription_status,
    CASE 
        WHEN fcm_token IS NULL THEN '❌ NO TOKEN'
        WHEN LENGTH(fcm_token) < 50 THEN '⚠️ TOKEN TOO SHORT'
        ELSE '✅ TOKEN EXISTS'
    END as token_status
FROM users
WHERE is_provider = TRUE
ORDER BY created_at DESC
LIMIT 10;

-- 2. Check recent notifications
SELECT 
    n.id,
    n.user_id,
    n.order_id,
    n.message,
    n.created_at,
    u.fcm_token IS NOT NULL as has_fcm_token
FROM notifications n
LEFT JOIN users u ON n.user_id = u.id
WHERE n.created_at > NOW() - INTERVAL '1 hour'
ORDER BY n.created_at DESC
LIMIT 10;

-- 3. Test if update_fcm_token RPC exists
SELECT proname 
FROM pg_proc 
WHERE proname = 'update_fcm_token';
-- Should return 1 row if RPC exists

-- ==========================================
-- EXPECTED RESULTS:
-- ==========================================
-- Query 1: All providers should have ✅ TOKEN EXISTS
-- Query 2: Recent notifications should have has_fcm_token = true
-- Query 3: Should return 'update_fcm_token' (RPC exists)
-- ==========================================
