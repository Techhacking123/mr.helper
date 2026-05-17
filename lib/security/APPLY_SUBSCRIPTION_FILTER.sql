-- ==========================================
-- QUICK FIX: Only Notify Subscribed Providers
-- ==========================================
-- Run this entire script in Supabase SQL Editor
-- This will ensure only providers with active subscriptions
-- receive notifications about new service requests

-- Step 1: Ensure subscription columns exist
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_subscribed BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expiry TIMESTAMPTZ;

-- Step 2: Update the notification trigger function
CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
BEGIN
  -- Only run for open requests
  IF NEW.status = 'request_open' THEN
    -- Find matching providers (same service, same location, AND subscribed with valid expiry)
    FOR provider_record IN 
      SELECT id FROM users 
      WHERE is_provider = TRUE 
      AND service_id = NEW.service_id 
      AND is_subscribed = TRUE  -- Only notify subscribed providers
      AND (subscription_expiry IS NULL OR subscription_expiry > NOW())  -- Check subscription hasn't expired
      AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL)
    LOOP
      -- Insert Notification
      INSERT INTO notifications (user_id, order_id, message, created_at)
      VALUES (provider_record.id, NEW.id, 'New service request available match!', NOW());
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The existing trigger will automatically use the updated function
-- No need to recreate the trigger

-- Verification Query (Optional - uncomment to run)
-- SELECT prosrc FROM pg_proc WHERE proname = 'notify_providers_on_order';
