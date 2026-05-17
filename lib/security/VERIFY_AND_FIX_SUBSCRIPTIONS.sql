-- ================================================
-- VERIFY AND FIX SUBSCRIPTION ENFORCEMENT
-- Run this script to debug why unsubscribed providers receive notifications
-- ================================================

-- 1. DIAGNOSTICS: Check for data inconsistency
-- Find providers who are 'active' but shouldn't be
DO $$
DECLARE
  bad_provider_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO bad_provider_count
  FROM users
  WHERE is_provider = TRUE 
    AND subscription_status = 'active'
    AND (subscription_end_date IS NULL OR subscription_end_date <= NOW());
    
  RAISE NOTICE 'Found % providers with invalid active status (expired date but active status)', bad_provider_count;
END $$;

-- 2. FIX DATA: Force expiry for anyone with past end_date
UPDATE users
SET subscription_status = 'expired'
WHERE is_provider = TRUE 
  AND subscription_status = 'active'
  AND (subscription_end_date IS NULL OR subscription_end_date <= NOW());

-- 3. FIX DATA: Ensure 'none' status for those with no subscription data
UPDATE users
SET subscription_status = 'none'
WHERE is_provider = TRUE
  AND subscription_status IS NULL;

-- 4. VERIFY TRIGGER FUNCTION
-- Re-applying the strict function to ensure no rollback happened
CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  notified_count INTEGER := 0;
BEGIN
  -- Only run for open requests
  IF NEW.status = 'request_open' THEN
    
    -- Auto-expire any subscriptions that have passed their end_date
    PERFORM auto_expire_subscriptions();
    
    -- Find matching providers with STRICT subscription check
    FOR provider_record IN 
      SELECT 
        id,
        full_name,
        subscription_status,
        subscription_end_date
      FROM users 
      WHERE is_provider = TRUE 
        AND service_id = NEW.service_id 
        -- CRITICAL: Only active subscriptions
        AND subscription_status = 'active'::subscription_status_enum
        -- CRITICAL: Must have valid end_date in future
        AND subscription_end_date IS NOT NULL
        AND subscription_end_date > NOW()
        -- Match location
        AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL)
    LOOP
      -- Double-check subscription is still active (extra safety)
      IF provider_record.subscription_status = 'active'::subscription_status_enum 
         AND provider_record.subscription_end_date > NOW() THEN
        
        -- Insert Notification
        INSERT INTO notifications (user_id, order_id, message, created_at)
        VALUES (
          provider_record.id, 
          NEW.id, 
          'New service request available in your area!', 
          NOW()
        );
        
        notified_count := notified_count + 1;
      END IF;
    END LOOP;
    
    RAISE NOTICE 'Filtered Order %. Notified % active subscribers.', NEW.id, notified_count;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. VERIFY TRIGGER IS ATTACHED
DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;
CREATE TRIGGER notify_providers_on_order_trigger
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();

-- 6. REMOVE OLD TRIGGERS (Cleanup)
-- Remove the old trigger from supabase_rls.sql if it exists under a different name
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;

-- 7. CLEANUP OLD NOTIFICATIONS
-- Optional: Delete notifications for unsubscribed users created in last 24h
-- DELETE FROM notifications
-- WHERE created_at > NOW() - INTERVAL '1 day'
-- AND user_id IN (
--   SELECT id FROM users 
--   WHERE subscription_status != 'active' OR subscription_end_date <= NOW()
-- );

DO $$ BEGIN
  RAISE NOTICE 'Verification and Fix Complete. Strict enforcement active.';
END $$;
