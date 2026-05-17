-- ==========================================
-- EMERGENCY CLEANUP: DUPLICATE TRIGGERS
-- ==========================================
-- This script removes ALL duplicate triggers
-- Run this IMMEDIATELY in Supabase SQL Editor
-- ==========================================

-- ==========================================
-- STEP 1: DROP ALL DUPLICATE TRIGGERS
-- ==========================================

-- Drop ALL triggers on notifications table
DROP TRIGGER IF EXISTS on_notification_created ON notifications;
DROP TRIGGER IF EXISTS on_notification_push ON notifications;
DROP TRIGGER IF EXISTS send_fcm_notifications ON notifications;
DROP TRIGGER IF EXISTS trigger_send_fcm_notification ON notifications;
DROP TRIGGER IF EXISTS tr_send_fcm ON notifications;
DROP TRIGGER IF EXISTS push_notification_trigger ON notifications;

-- Drop ALL notification-creating triggers on orders table
DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;
DROP TRIGGER IF EXISTS on_order_created ON orders;
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
DROP TRIGGER IF EXISTS notify_providers_trigger ON orders;
DROP TRIGGER IF EXISTS tr_notify_providers ON orders;

-- Note: We're keeping these triggers as they serve different purposes:
-- - trigger_notify_provider_fines (for fine alerts)
-- - trigger_set_order_deadline (for setting deadlines)

-- ==========================================
-- STEP 2: RECREATE CORRECT TRIGGERS
-- ==========================================

-- ==========================================
-- 2A. ORDER NOTIFICATION TRIGGER
-- ==========================================

CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  loc_name TEXT;
  notified_count INTEGER := 0;
BEGIN
  -- Only run for INSERT operations with status 'request_open'
  IF (TG_OP = 'INSERT' AND NEW.status = 'request_open') THEN
    
    -- Get location name safely
    SELECT name INTO loc_name FROM locations WHERE id = NEW.location_id;

    -- Find matching providers
    FOR provider_record IN 
      SELECT id FROM users 
      WHERE is_provider = TRUE 
      AND service_id = NEW.service_id 
      -- Subscription checks
      AND (subscription_status::text = 'active' OR subscription_status IS NULL)
      AND (subscription_end_date IS NULL OR subscription_end_date > NOW())
      -- Location check
      AND (location IS NULL OR location = '' OR location = loc_name)
    LOOP
      -- IDEMPOTENCY CHECK: Only insert if notification doesn't exist
      IF NOT EXISTS (
        SELECT 1 FROM notifications 
        WHERE user_id = provider_record.id 
        AND order_id = NEW.id
      ) THEN
        INSERT INTO notifications (user_id, order_id, message, created_at)
        VALUES (
          provider_record.id, 
          NEW.id, 
          'New Service Request: ' || (SELECT name FROM services WHERE id = NEW.service_id) || ' in ' || COALESCE(loc_name, 'your area'), 
          NOW()
        );
        notified_count := notified_count + 1;
      END IF;
    END LOOP;
    
    RAISE NOTICE 'Order % created. Notified % providers.', NEW.id, notified_count;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger (SINGLE TRIGGER FOR INSERT ONLY)
CREATE TRIGGER notify_providers_on_order_trigger
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();

-- ==========================================
-- 2B. FCM NOTIFICATION TRIGGER  
-- ==========================================

CREATE OR REPLACE FUNCTION send_fcm_on_notification()
RETURNS TRIGGER AS $$
DECLARE
    request_id bigint;
    api_url text;
    payload jsonb;
BEGIN
    -- Build the API URL for Supabase Edge Function
    api_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/push_notifications';
    
    -- Build the payload
    payload := jsonb_build_object('record', row_to_json(NEW));
    
    -- Make HTTP POST request using pg_net
    SELECT net.http_post(
        url := api_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := payload
    ) INTO request_id;
    
    RAISE LOG 'FCM notification request sent with ID: %', request_id;
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Failed to send FCM notification: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger (SINGLE TRIGGER FOR INSERT ONLY)
CREATE TRIGGER trigger_send_fcm_notification
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_fcm_on_notification();

-- ==========================================
-- STEP 3: VERIFICATION
-- ==========================================

DO $$
DECLARE
  c_orders INT;
  c_notif INT;
BEGIN
  -- Count triggers on orders (INSERT only, excluding fine/deadline triggers)
  SELECT COUNT(*) INTO c_orders 
  FROM information_schema.triggers 
  WHERE event_object_table = 'orders' 
  AND event_manipulation = 'INSERT'
  AND trigger_name NOT IN ('trigger_notify_provider_fines', 'trigger_set_order_deadline');
  
  -- Count triggers on notifications (INSERT only)
  SELECT COUNT(*) INTO c_notif 
  FROM information_schema.triggers 
  WHERE event_object_table = 'notifications'
  AND event_manipulation = 'INSERT';
  
  RAISE NOTICE '==================================================';
  RAISE NOTICE '✅ CLEANUP COMPLETE';
  RAISE NOTICE '==================================================';
  RAISE NOTICE 'Orders table INSERT triggers (notification-related): % (Should be 1)', c_orders;
  RAISE NOTICE 'Notifications table INSERT triggers: % (Should be 1)', c_notif;
  RAISE NOTICE '==================================================';
  
  IF c_orders = 1 AND c_notif = 1 THEN
    RAISE NOTICE '✅ SUCCESS: Trigger configuration is now CORRECT!';
  ELSE
    RAISE WARNING '⚠️ WARNING: Unexpected trigger count. Please verify manually.';
  END IF;
END $$;

-- ==========================================
-- FINAL VERIFICATION QUERY
-- ==========================================

-- Run this to see all remaining triggers
SELECT 
    event_object_table as table_name,
    trigger_name,
    event_manipulation as event_type,
    action_timing as timing
FROM information_schema.triggers 
WHERE event_object_table IN ('orders', 'notifications')
ORDER BY event_object_table, trigger_name;

-- Expected output:
-- notifications | trigger_send_fcm_notification | INSERT | AFTER
-- orders        | notify_providers_on_order_trigger | INSERT | AFTER
-- orders        | trigger_notify_provider_fines | UPDATE | AFTER (for fines - OK)
-- orders        | trigger_set_order_deadline | INSERT | BEFORE (for deadlines - OK)

-- ==========================================
-- END OF CLEANUP SCRIPT
-- ==========================================
