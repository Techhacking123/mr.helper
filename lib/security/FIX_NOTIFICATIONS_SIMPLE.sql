-- ==========================================
-- 🔥 QUICK FIX: Stop Unsubscribed Providers from Getting Notifications
-- ==========================================
-- INSTRUCTIONS:
-- 1. Copy this ENTIRE file
-- 2. Go to https://supabase.com/dashboard/project/rvrpsqdrbwfvllelyqhf/sql
-- 3. Paste and click "RUN"
-- 4. Done! ✅
-- ==========================================

-- Ensure columns exist (safe to run even if they already exist)
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_subscribed BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expiry TIMESTAMPTZ;

-- Update the trigger function to CHECK SUBSCRIPTIONS
CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  notified_count INTEGER := 0;
BEGIN
  -- Only for broadcast orders
  IF NEW.status = 'request_open' THEN
    
    -- Find ONLY SUBSCRIBED providers
    FOR provider_record IN 
      SELECT id, full_name
      FROM users 
      WHERE is_provider = TRUE 
        AND service_id = NEW.service_id 
        -- ✅ KEY FIX: Only subscribed providers
        AND is_subscribed = TRUE
        -- ✅ KEY FIX: Subscription not expired
        AND (subscription_expiry IS NULL OR subscription_expiry > NOW())
        -- Match location
        AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL)
    LOOP
      -- Send notification
      INSERT INTO notifications (user_id, order_id, message, created_at)
      VALUES (provider_record.id, NEW.id, 'New service request available in your area!', NOW());
      
      notified_count := notified_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Order %: Notified % subscribed providers', NEW.id, notified_count;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove old triggers
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
DROP TRIGGER IF EXISTS notify_providers_trigger ON orders;
DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;

-- Create trigger
CREATE TRIGGER on_new_order_notify
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();

-- Show results
DO $$
DECLARE
  active INTEGER;
  inactive INTEGER;
BEGIN
  SELECT COUNT(*) INTO active FROM users 
  WHERE is_provider = TRUE AND is_subscribed = TRUE AND (subscription_expiry IS NULL OR subscription_expiry > NOW());
  
  SELECT COUNT(*) INTO inactive FROM users 
  WHERE is_provider = TRUE AND (is_subscribed = FALSE OR is_subscribed IS NULL OR subscription_expiry <= NOW());
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FIX APPLIED SUCCESSFULLY';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Subscribed providers (WILL get notifications): %', active;
  RAISE NOTICE 'Unsubscribed providers (BLOCKED): %', inactive;
  RAISE NOTICE '========================================';
END $$;
