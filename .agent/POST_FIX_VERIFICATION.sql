-- ==========================================
-- POST-FIX VERIFICATION SCRIPT
-- ==========================================
-- Run this in Supabase SQL Editor after applying the fix
-- to verify everything is configured correctly
-- ==========================================

-- ==========================================
-- 1. VERIFY TRIGGER COUNT (Should be exactly 2)
-- ==========================================

SELECT 
    event_object_table as table_name,
    trigger_name,
    event_manipulation as event_type,
    action_timing as timing
FROM information_schema.triggers 
WHERE event_object_table IN ('orders', 'notifications')
ORDER BY event_object_table, trigger_name;

-- ✅ EXPECTED RESULT: Exactly 2 rows
-- Row 1: notifications | trigger_send_fcm_notification | INSERT | AFTER
-- Row 2: orders         | on_new_order_notify           | INSERT | AFTER
--
-- ❌ IF YOU SEE MORE: You have duplicate triggers. See cleanup section below.

-- ==========================================
-- 2. TEST THE TRIGGER FUNCTION
-- ==========================================

-- Test that the notify_providers_on_order function exists
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'notify_providers_on_order';

-- ✅ EXPECTED: Should return 1 row with the function definition

-- ==========================================
-- 3. CHECK FOR RECENT DUPLICATE NOTIFICATIONS
-- ==========================================

-- Find any duplicate notifications from last 24 hours
SELECT 
    user_id,
    order_id,
    COUNT(*) as notification_count,
    STRING_AGG(message, ' | ') as messages,
    MAX(created_at) as latest_notification
FROM notifications
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY user_id, order_id
HAVING COUNT(*) > 1
ORDER BY notification_count DESC, latest_notification DESC;

-- ✅ EXPECTED: 0 rows (no duplicates)
-- ❌ IF YOU SEE ROWS: Still have duplicates (investigate further)

-- ==========================================
-- 4. CLEANUP SECTION (Run only if duplicates found)
-- ==========================================

-- UNCOMMENT AND RUN THESE ONLY IF STEP 1 SHOWED DUPLICATE TRIGGERS

/*
-- Drop all duplicate triggers on orders table
DROP TRIGGER IF EXISTS notify_providers_trigger ON orders;
DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;
DROP TRIGGER IF EXISTS tr_notify_providers ON orders;
DROP TRIGGER IF EXISTS order_notification_trigger ON orders;

-- Drop all duplicate triggers on notifications table  
DROP TRIGGER IF EXISTS tr_send_fcm ON notifications;
DROP TRIGGER IF EXISTS push_notification_trigger ON notifications;
DROP TRIGGER IF EXISTS send_fcm_trigger ON notifications;

-- Keep these two triggers (correct ones):
-- - on_new_order_notify on orders
-- - trigger_send_fcm_notification on notifications

-- Re-run verification query from Step 1 to confirm only 2 triggers remain
*/

-- ==========================================
-- 5. CLEANUP OLD DUPLICATE NOTIFICATIONS
-- ==========================================

-- OPTIONAL: Remove old duplicate notifications from database
-- (This won't affect new ones, just cleans up history)

/*
-- First, see what will be deleted
SELECT user_id, order_id, COUNT(*) as dupes
FROM notifications
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY user_id, order_id
HAVING COUNT(*) > 1;

-- Then delete duplicates, keeping only the oldest one per user+order
DELETE FROM notifications
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY user_id, order_id 
                   ORDER BY created_at ASC
               ) as rn
        FROM notifications
        WHERE created_at > NOW() - INTERVAL '7 days'
    ) t
    WHERE rn > 1
);
*/

-- ==========================================
-- 6. FINAL HEALTH CHECK
-- ==========================================

-- Summary of notifications in last 24 hours
SELECT 
    COUNT(*) as total_notifications,
    COUNT(DISTINCT order_id) as unique_orders,
    COUNT(DISTINCT user_id) as unique_users,
    ROUND(COUNT(*)::numeric / NULLIF(COUNT(DISTINCT order_id), 0), 2) as avg_notifications_per_order
FROM notifications
WHERE created_at > NOW() - INTERVAL '24 hours';

-- ✅ EXPECTED: avg_notifications_per_order should be close to 1.0
-- ❌ IF > 1.5: Still creating duplicates

-- ==========================================
-- SUCCESS CRITERIA
-- ==========================================
-- ✅ Step 1: Exactly 2 triggers
-- ✅ Step 2: Function exists
-- ✅ Step 3: 0 duplicate notifications in last 24 hours
-- ✅ Step 6: avg_notifications_per_order ≈ 1.0
--
-- If all checks pass: Fix is working! 🎉
-- If any fail: See cleanup section or contact support
-- ==========================================
