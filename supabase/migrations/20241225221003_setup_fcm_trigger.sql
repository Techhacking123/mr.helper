-- ==========================================
-- FCM PUSH NOTIFICATION TRIGGER SETUP
-- ==========================================
-- This trigger automatically sends FCM push notifications
-- when a new row is inserted into the notifications table

-- 1. Create the function that calls the Supabase Edge Function
CREATE OR REPLACE FUNCTION send_fcm_on_notification()
RETURNS TRIGGER AS $$
DECLARE
    request_id bigint;
    api_url text;
    payload jsonb;
BEGIN
   -- Build the API URL for your Supabase Edge Function
    -- Replace <YOUR_PROJECT_REF> with your actual Supabase project reference
    api_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/push_notifications';
    
    -- Build the payload to send to the Edge Function
    payload := jsonb_build_object(
        'record', row_to_json(NEW)
    );
    
    -- Make HTTP POST request to the Edge Function using pg_net
    -- This requires the pg_net extension to be enabled
    SELECT net.http_post(
        url := api_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := payload
    ) INTO request_id;
    
    -- Log the request (optional, for debugging)
    RAISE LOG 'FCM notification request sent with ID: %', request_id;
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- If the HTTP request fails, log the error but don't fail the transaction
        RAISE WARNING 'Failed to send FCM notification: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Create or replace the trigger
DROP TRIGGER IF EXISTS trigger_send_fcm_notification ON notifications;
CREATE TRIGGER trigger_send_fcm_notification
    AFTER INSERT ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION send_fcm_on_notification();

-- 3. Grant necessary permissions
GRANT USAGE ON SCHEMA net TO postgres, anon, authenticated, service_role;

-- Note: This requires:
-- 1. pg_net extension to be enabled in Supabase
-- 2. The push_notifications Edge Function to be deployed
-- 3. FIREBASE_SERVICE_ACCOUNT secret to be set in Supabase

COMMENT ON FUNCTION send_fcm_on_notification() IS 
'Automatically sends FCM push notifications via Supabase Edge Function when notifications are inserted';
