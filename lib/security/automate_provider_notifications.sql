-- Enable pg_cron if available (might fail on some setups, but worth a try)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Function to check and send automated provider notifications
CREATE OR REPLACE FUNCTION process_provider_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user RECORD;
    v_total_fines NUMERIC;
    v_notif_exists BOOLEAN;
BEGIN
    -- Loop through all providers (Using is_provider boolean)
    FOR v_user IN SELECT * FROM users WHERE is_provider = true LOOP
        
        -- ---------------------------------------------------------
        -- 1. CHECK FINES (Notify if fines exist)
        -- ---------------------------------------------------------
        -- Assumes table 'provider_fines' exists with 'provider_id', 'status', 'fine_amount'
        SELECT COALESCE(SUM(fine_amount), 0) 
        INTO v_total_fines 
        FROM provider_fines 
        WHERE provider_id = v_user.id AND is_paid = false;
        
        IF v_total_fines > 0 THEN
             -- Limit to once every 24 hours
             SELECT EXISTS (
                 SELECT 1 FROM notifications 
                 WHERE user_id = v_user.id 
                 AND type = 'fine_reminder'
                 AND created_at > NOW() - INTERVAL '24 hours'
             ) INTO v_notif_exists;

             IF NOT v_notif_exists THEN
                 INSERT INTO notifications (user_id, type, title, message, created_at, is_read)
                 VALUES (v_user.id, 'fine_reminder', 'Outstanding Fines', 'You have pending fines of ₹' || v_total_fines || '. Please pay to avoid interruptions.', NOW(), false);
             END IF;
        END IF;

        -- ---------------------------------------------------------
        -- 2. CHECK SUBSCRIPTION (Notify every 3 hours if inactive/expired)
        -- ---------------------------------------------------------
        IF v_user.is_subscribed IS NOT TRUE OR (v_user.subscription_expiry IS NOT NULL AND v_user.subscription_expiry < NOW()) THEN
             -- Check last reminder time (Every 3 hours)
             SELECT EXISTS (
                 SELECT 1 FROM notifications 
                 WHERE user_id = v_user.id 
                 AND type = 'subscription_reminder'
                 AND created_at > NOW() - INTERVAL '3 hours'
             ) INTO v_notif_exists;

             IF NOT v_notif_exists THEN
                 INSERT INTO notifications (user_id, type, title, message, created_at, is_read)
                 VALUES (v_user.id, 'subscription_reminder', 'Subscription Required', 'You do not have an active subscription. Subscribe now to get service requests!', NOW(), false);
             END IF;
        
        ELSE
             -- Subscription is Active
             -- 3. CHECK IF SUBSCRIPTION JUST ENDED (e.g. within last hour) could be handled above by expiry check.
        END IF;

    END LOOP;
END;
$$;

-- Attempt to schedule the job (Runs every hour to check)
-- Note: '0 * * * *' runs every hour. The function logic handles the "3 hour" frequency check internally.
-- We use DO block to avoid error if pg_cron is not enabled.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('process-provider-reminders-job', '0 * * * *', 'SELECT process_provider_reminders()');
    END IF;
END
$$;
