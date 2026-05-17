-- ==========================================
-- DUPLICATE NOTIFICATION FIX - VERIFICATION
-- ==========================================
-- Run this script to verify your database configuration
-- and identify duplicate notification triggers

-- ==========================================
-- 1. CHECK FOR DUPLICATE TRIGGERS
-- ==========================================

-- Check triggers on 'orders' table
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'orders'
ORDER BY trigger_name;

-- Expected result: Should show ONLY 1 trigger
-- - on_new_order_notify (AFTER INSERT)

-- ==========================================

-- Check triggers on 'notifications' table  
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'notifications'
ORDER BY trigger_name;

-- Expected result: Should show ONLY 1 trigger
-- - trigger_send_fcm_notification (AFTER INSERT)

-- ==========================================
-- 2. CHECK FOR DUPLICATE NOTIFICATIONS
-- ==========================================

-- Find orders with duplicate notifications
SELECT 
    o.id as order_id,
    o.title,
    o.status,
    COUNT(n.id) as notification_count,
    STRING_AGG(n.user_id::text, ', ') as notified_users
FROM orders o
LEFT JOIN notifications n ON n.order_id = o.id
WHERE o.created_at > NOW() - INTERVAL '7 days'
GROUP BY o.id, o.title, o.status
HAVING COUNT(n.id) > 1
ORDER BY o.created_at DESC;

-- If this returns results, you have duplicate notifications

-- ==========================================
-- 3. FIND SPECIFIC USER DUPLICATES
-- ==========================================

-- Find if same user got multiple notifications for same order
SELECT 
    user_id,
    order_id,
    COUNT(*) as duplicate_count,
    STRING_AGG(message, ' | ') as messages,
    STRING_AGG(created_at::text, ' | ') as timestamps
FROM notifications
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY user_id, order_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- This shows the EXACT duplicate notifications

-- ==========================================
-- 4. VERIFY AUTOMATED NOTIFICATION TRIGGERS
-- ==========================================

-- Check if automated notification triggers exist
SELECT 
    trigger_name,
    event_object_table
FROM information_schema.triggers 
WHERE trigger_name IN (
    'trigger_notify_provider_fines',
    'trigger_send_fcm_notification',
    'on_new_order_notify',
    'notify_providers_on_order_trigger',
    'subscription_change_logger'
)
ORDER BY event_object_table, trigger_name;

-- ==========================================
-- 5. CHECK CRON JOBS (if pg_cron is enabled)
-- ==========================================

-- List all scheduled cron jobs
-- SELECT * FROM cron.job;

-- Note: This will only work if pg_cron extension is enabled
-- If you get an error, cron jobs are not configured

-- ==========================================
-- INTERPRETATION GUIDE
-- ==========================================
--
-- HEALTHY STATE:
-- - 1 trigger on 'orders' table
-- - 1 trigger on 'notifications' table  
-- - 0 duplicate notifications in the last 7 days
--
-- UNHEALTHY STATE (needs fixing):
-- - Multiple triggers on same table
-- - Duplicate notifications for same user + order_id
-- - Trigger names from different SQL migration files
--
-- ==========================================

-- ==========================================
-- 6. CLEANUP (RUN ONLY IF DUPLICATES FOUND)
-- ==========================================

-- UNCOMMENT AND RUN THESE ONLY IF YOU FOUND DUPLICATES ABOVE

-- Drop all known duplicate triggers on orders table
-- DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
-- DROP TRIGGER IF EXISTS notify_providers_trigger ON orders;
-- DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;
-- DROP TRIGGER IF EXISTS tr_notify_providers ON orders;
-- DROP TRIGGER IF EXISTS order_notification_trigger ON orders;

-- Drop all known duplicate triggers on notifications table
-- DROP TRIGGER IF EXISTS trigger_send_fcm_notification ON notifications;
-- DROP TRIGGER IF EXISTS tr_send_fcm ON notifications;
-- DROP TRIGGER IF EXISTS push_notification_trigger ON notifications;
-- DROP TRIGGER IF EXISTS send_fcm_trigger ON notifications;

-- After dropping duplicates, re-run the migration:
-- supabase/migrations/20241225221002_fix_provider_matching.sql
-- supabase/migrations/20241225221003_setup_fcm_trigger.sql

-- ==========================================
-- END OF VERIFICATION SCRIPT
-- ==========================================
