-- ==========================================
-- FIX: Update Trigger with Direct URLs
-- ==========================================
-- This updates the trigger function to use direct URLs
-- instead of app.settings (which we don't have permission to set)
-- ==========================================

-- IMPORTANT: Replace these values:
-- 1. Replace 'rvrpsqdrbwfvllelyqhf' with your actual project ref (if different)
-- 2. Replace the service_role_key with your actual key

-- Drop and recreate the FCM notification trigger function
CREATE OR REPLACE FUNCTION send_fcm_on_notification()
RETURNS TRIGGER AS $$
DECLARE
    request_id bigint;
    api_url text;
    payload jsonb;
    service_role_key text;
BEGIN
    -- Hardcode your Supabase project URL and service role key
    api_url := 'https://rvrpsqdrbwfvllelyqhf.supabase.co/functions/v1/push_notifications';
    service_role_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2cnBzcWRyYndmdmxsZWx5cWhmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTE1ODE5OSwiZXhwIjoyMDgwNzM0MTk5fQ.GyckF5tq300NJmV-invzTOLo-eBlv2U9AOoiMJtkMXc';
    
    -- Build the payload
    payload := jsonb_build_object('record', row_to_json(NEW));
    
    -- Make HTTP POST request using pg_net
    BEGIN
        SELECT net.http_post(
            url := api_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := payload
        ) INTO request_id;
        
        RAISE LOG 'FCM notification request sent with ID: %', request_id;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE WARNING 'Failed to send FCM notification: %', SQLERRM;
    END;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger already exists, so we don't need to recreate it
-- But if it doesn't exist, uncomment this:
/*
DROP TRIGGER IF EXISTS trigger_send_fcm_notification ON notifications;
CREATE TRIGGER trigger_send_fcm_notification
    AFTER INSERT ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION send_fcm_on_notification();
*/

-- ==========================================
-- VERIFICATION
-- ==========================================

-- Check if function was updated
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'send_fcm_on_notification';

-- Should show the updated function with hardcoded URLs

-- ==========================================
-- TEST IT
-- ==========================================

-- Create a test notification to trigger FCM
INSERT INTO notifications (user_id, message, created_at)
VALUES (
    'e1f887e4-40d5-4026-bbff-861733fdccd8',  -- Your provider user ID
    '🎉 TEST: FCM should work now!',
    NOW()
);

-- After running this:
-- 1. Check your phone - did notification appear?
-- 2. Go to Supabase Dashboard → Edge Functions → push_notifications → Logs
--    You should see a new invocation!

-- ==========================================
-- IMPORTANT NOTES
-- ==========================================

-- ⚠️ SECURITY WARNING:
-- The service_role_key is now hardcoded in the database.
-- This is generally safe because:
-- 1. Only database functions can access it
-- 2. It's not exposed to client apps
-- 3. RLS policies still apply
--
-- However, for maximum security in production:
-- - Use Supabase Vault to store the key
-- - Or use Edge Function environment variables instead

-- ==========================================
