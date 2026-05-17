-- =====================================================
-- AUTOMATED PUSH NOTIFICATION SYSTEM
-- =====================================================
-- This script implements:
-- 1. Order deadline reminders (10hrs, 2hrs, 1hr)
-- 2. Subscription expiry reminders (3 days, 2 days, 1 day, 1hr)
-- 3. Fine alert notifications
-- =====================================================

-- =====================================================
-- 1. ORDER DEADLINE REMINDER NOTIFICATIONS
-- =====================================================

CREATE OR REPLACE FUNCTION send_order_deadline_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    order_record RECORD;
    provider_fcm_token TEXT;
    user_fcm_token TEXT;
    hours_remaining NUMERIC;
    notification_title TEXT;
    notification_body TEXT;
BEGIN
    -- Find orders approaching deadline (10hr, 2hr, 1hr windows)
    FOR order_record IN
        SELECT 
            o.id,
            o.title,
            o.deadline,
            o.provider_id,
            o.user_id,
            o.status,
            EXTRACT(EPOCH FROM (o.deadline - NOW())) / 3600 AS hours_left
        FROM orders o
        WHERE 
            o.status NOT IN ('completed', 'cancelled')
            AND o.deadline > NOW()
            AND o.deadline < NOW() + INTERVAL '10 hours'
            -- Only send if we haven't sent this tier of reminder yet
            AND NOT EXISTS (
                SELECT 1 FROM notifications n
                WHERE n.order_id = o.id
                AND n.type = 'order_deadline_reminder'
                AND n.created_at > NOW() - INTERVAL '12 hours'
                -- Prevent duplicate reminders within 12 hours
            )
    LOOP
        hours_remaining := order_record.hours_left;
        
        -- Determine which reminder tier (10hr, 2hr, or 1hr)
        IF hours_remaining <= 1 THEN
            notification_title := '⏰ Order Deadline in 1 Hour!';
            notification_body := 'Order "' || order_record.title || '" is due in 1 hour. Please complete or update status.';
        ELSIF hours_remaining <= 2 THEN
            notification_title := '⏰ Order Deadline in 2 Hours!';
            notification_body := 'Order "' || order_record.title || '" is due in 2 hours.';
        ELSIF hours_remaining <= 10 THEN
            notification_title := '⏰ Order Deadline Approaching';
            notification_body := 'Order "' || order_record.title || '" is due in ' || ROUND(hours_remaining) || ' hours.';
        ELSE
            CONTINUE; -- Skip if outside reminder windows
        END IF;

        -- Get FCM tokens
        SELECT fcm_token INTO provider_fcm_token
        FROM users
        WHERE id = order_record.provider_id;

        SELECT fcm_token INTO user_fcm_token
        FROM users
        WHERE id = order_record.user_id;

        -- Send to PROVIDER
        IF provider_fcm_token IS NOT NULL THEN
            INSERT INTO notifications (
                user_id,
                title,
                message,
                type,
                order_id,
                data,
                created_at
            ) VALUES (
                order_record.provider_id,
                notification_title,
                notification_body,
                'order_deadline_reminder',
                order_record.id,
                jsonb_build_object(
                    'screen', 'order_detail',
                    'order_id', order_record.id,
                    'hours_left', ROUND(hours_remaining, 1)
                ),
                NOW()
            );
        END IF;

        -- Send to USER
        IF user_fcm_token IS NOT NULL THEN
            INSERT INTO notifications (
                user_id,
                title,
                message,
                type,
                order_id,
                data,
                created_at
            ) VALUES (
                order_record.user_id,
                notification_title,
                'Your order "' || order_record.title || '" is due soon. Mark as completed if service is done.',
                'order_deadline_reminder',
                order_record.id,
                jsonb_build_object(
                    'screen', 'order_detail',
                    'order_id', order_record.id,
                    'hours_left', ROUND(hours_remaining, 1)
                ),
                NOW()
            );
        END IF;

        RAISE NOTICE 'Deadline reminder sent for order % (% hours left)', order_record.id, ROUND(hours_remaining);
    END LOOP;
END;
$$;

-- =====================================================
-- 2. SUBSCRIPTION EXPIRY REMINDER NOTIFICATIONS
-- =====================================================

CREATE OR REPLACE FUNCTION send_subscription_expiry_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    provider_record RECORD;
    days_remaining NUMERIC;
    hours_remaining NUMERIC;
    notification_title TEXT;
    notification_body TEXT;
    reminder_key TEXT;
BEGIN
    -- Find providers with expiring subscriptions
    FOR provider_record IN
        SELECT 
            u.id,
            u.full_name,
            u.fcm_token,
            u.subscription_end_date,
            EXTRACT(EPOCH FROM (u.subscription_end_date - NOW())) / 86400 AS days_left,
            EXTRACT(EPOCH FROM (u.subscription_end_date - NOW())) / 3600 AS hours_left
        FROM users u
        WHERE 
            u.is_provider = TRUE
            AND u.subscription_status = 'active'
            AND u.subscription_end_date IS NOT NULL
            AND u.subscription_end_date > NOW()
            AND u.subscription_end_date < NOW() + INTERVAL '3 days'
    LOOP
        days_remaining := provider_record.days_left;
        hours_remaining := provider_record.hours_left;
        
        -- Determine which reminder tier and create unique key
        IF hours_remaining <= 1 THEN
            notification_title := '🚨 Subscription Expires in 1 Hour!';
            notification_body := 'Your subscription expires very soon! Renew now to keep receiving orders.';
            reminder_key := provider_record.id::TEXT || '_1hour';
        ELSIF days_remaining <= 1 THEN
            notification_title := '⚠️ Subscription Expires Tomorrow!';
            notification_body := 'Your subscription expires in ' || ROUND(hours_remaining) || ' hours. Tap to renew.';
            reminder_key := provider_record.id::TEXT || '_1day';
        ELSIF days_remaining <= 2 THEN
            notification_title := '⏰ Subscription Expires in 2 Days';
            notification_body := 'Your subscription will expire soon. Renew to continue receiving orders.';
            reminder_key := provider_record.id::TEXT || '_2days';
        ELSIF days_remaining <= 3 THEN
            notification_title := '📆 Subscription Expires in 3 Days';
            notification_body := 'Reminder: Your subscription expires in 3 days.';
            reminder_key := provider_record.id::TEXT || '_3days';
        ELSE
            CONTINUE;
        END IF;

        -- Check if we already sent this specific reminder
        IF EXISTS (
            SELECT 1 FROM notifications
            WHERE user_id = provider_record.id
            AND type = 'subscription_expiry_reminder'
            AND data->>'reminder_key' = reminder_key
            AND created_at > NOW() - INTERVAL '24 hours'
        ) THEN
            CONTINUE; -- Skip if already sent recently
        END IF;

        -- Send notification (only if FCM token exists)
        IF provider_record.fcm_token IS NOT NULL THEN
            INSERT INTO notifications (
                user_id,
                title,
                message,
                type,
                data,
                created_at
            ) VALUES (
                provider_record.id,
                notification_title,
                notification_body,
                'subscription_expiry_reminder',
                jsonb_build_object(
                    'screen', 'subscription_page',
                    'reminder_key', reminder_key,
                    'days_left', ROUND(days_remaining, 1),
                    'hours_left', ROUND(hours_remaining, 1)
                ),
                NOW()
            );

            RAISE NOTICE 'Subscription expiry reminder sent to provider % (% days left)', 
                provider_record.id, ROUND(days_remaining);
        END IF;
    END LOOP;
END;
$$;

-- =====================================================
-- 3. FINE ALERT NOTIFICATIONS (TRIGGER-BASED)
-- =====================================================

CREATE OR REPLACE FUNCTION notify_provider_of_fines()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    provider_name TEXT;
    order_title TEXT;
    fcm_token TEXT;
BEGIN
    -- Get provider details
    SELECT full_name, fcm_token
    INTO provider_name, fcm_token
    FROM users
    WHERE id = NEW.provider_id;

    -- Get order title
    SELECT title
    INTO order_title
    FROM orders
    WHERE id = NEW.id;

    -- Only send if provider has FCM token and fine was just created
    IF fcm_token IS NOT NULL AND NEW.fine_amount > 0 AND (OLD.fine_amount IS NULL OR OLD.fine_amount = 0) THEN
        -- Insert notification
        INSERT INTO notifications (
            user_id,
            title,
            message,
            type,
            order_id,
            data,
            created_at
        ) VALUES (
            NEW.provider_id,
            '💰 Fine Applied',
            'A fine of ₹' || NEW.fine_amount || ' has been applied to order "' || order_title || '". Tap to pay.',
            'fine_alert',
            NEW.id,
            jsonb_build_object(
                'screen', 'subscription_page',
                'order_id', NEW.id,
                'fine_amount', NEW.fine_amount
            ),
            NOW()
        );

        RAISE NOTICE 'Fine alert sent to provider % for order %', NEW.provider_id, NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS trigger_notify_provider_fines ON orders;

-- Create trigger for fine notifications
CREATE TRIGGER trigger_notify_provider_fines
AFTER UPDATE OF fine_amount ON orders
FOR EACH ROW
WHEN (NEW.fine_amount > 0 AND (OLD.fine_amount IS NULL OR OLD.fine_amount = 0))
EXECUTE FUNCTION notify_provider_of_fines();

-- =====================================================
-- 4. MANUAL TRIGGER FUNCTIONS (For Testing)
-- =====================================================

-- Test order deadline reminders
COMMENT ON FUNCTION send_order_deadline_reminders() IS 
'Run this function periodically (every hour) to send order deadline reminders. 
Usage: SELECT send_order_deadline_reminders();';

-- Test subscription expiry reminders
COMMENT ON FUNCTION send_subscription_expiry_reminders() IS 
'Run this function periodically (twice daily) to send subscription expiry reminders.
Usage: SELECT send_subscription_expiry_reminders();';

-- =====================================================
-- 5. CRON JOB SETUP (Using pg_cron if available)
-- =====================================================
-- NOTE: pg_cron must be enabled on your Supabase project
-- If not available, use Supabase Edge Functions with cron schedules

-- Enable pg_cron extension (run as superuser)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule order deadline reminders (every hour)
-- SELECT cron.schedule(
--     'order-deadline-reminders',
--     '0 * * * *', -- Every hour
--     $$ SELECT send_order_deadline_reminders(); $$
-- );

-- Schedule subscription expiry reminders (twice daily at 9 AM and 6 PM)
-- SELECT cron.schedule(
--     'subscription-expiry-reminders',
--     '0 9,18 * * *', -- At 9 AM and 6 PM
--     $$ SELECT send_subscription_expiry_reminders(); $$
-- );

-- =====================================================
-- 6. VERIFICATION QUERIES
-- =====================================================

-- Check recent deadline reminders
-- SELECT * FROM notifications 
-- WHERE type = 'order_deadline_reminder' 
-- ORDER BY created_at DESC LIMIT 10;

-- Check recent subscription expiry reminders
-- SELECT * FROM notifications 
-- WHERE type = 'subscription_expiry_reminder' 
-- ORDER BY created_at DESC LIMIT 10;

-- Check recent fine alerts
-- SELECT * FROM notifications 
-- WHERE type = 'fine_alert' 
-- ORDER BY created_at DESC LIMIT 10;

-- Test which orders would trigger reminders
-- SELECT 
--     id, title, deadline, status,
--     EXTRACT(EPOCH FROM (deadline - NOW())) / 3600 AS hours_left
-- FROM orders
-- WHERE status NOT IN ('completed', 'cancelled')
-- AND deadline > NOW()
-- AND deadline < NOW() + INTERVAL '10 hours';

-- Test which subscriptions would trigger reminders
-- SELECT 
--     id, full_name, subscription_end_date,
--     EXTRACT(EPOCH FROM (subscription_end_date - NOW())) / 86400 AS days_left
-- FROM users
-- WHERE is_provider = TRUE
-- AND subscription_status = 'active'
-- AND subscription_end_date > NOW()
-- AND subscription_end_date < NOW() + INTERVAL '3 days';

-- =====================================================
-- IMPLEMENTATION NOTES
-- =====================================================
-- 
-- 1. Run this SQL script in Supabase SQL Editor
-- 
-- 2. For CRON scheduling, you have two options:
--    
--    Option A: pg_cron (if available on Supabase)
--    - Uncomment the cron.schedule commands above
--    
--    Option B: Supabase Edge Functions (Recommended)
--    - Create Edge Functions that call these SQL functions
--    - Use Supabase's cron feature to schedule them
--    - See: supabase/functions/deadline-reminders/index.ts
--    - See: supabase/functions/subscription-reminders/index.ts
-- 
-- 3. Fine alerts are AUTOMATIC via trigger
--    - No cron needed
--    - Fires when order.fine_amount is updated
-- 
-- 4. Flutter must handle deep linking for navigation
--    - See: lib/main.dart for notification click handlers
-- 
-- =====================================================

RAISE NOTICE '✅ Automated notification system installed successfully!';
RAISE NOTICE '📋 Next steps:';
RAISE NOTICE '1. Test functions manually: SELECT send_order_deadline_reminders();';
RAISE NOTICE '2. Set up cron jobs (pg_cron or Edge Functions)';
RAISE NOTICE '3. Update Flutter app for deep linking';
