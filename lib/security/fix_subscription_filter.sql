-- ==========================================
-- FIX: Only notify subscribed providers
-- ==========================================
-- This migration updates the notify_providers_on_order function
-- to only send order notifications to providers with active subscriptions

-- Re-create the function with subscription check
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
      AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL) -- Loose location matching
    LOOP
      -- Insert Notification
      INSERT INTO notifications (user_id, order_id, message, created_at)
      VALUES (provider_record.id, NEW.id, 'New service request available match!', NOW());
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- No need to recreate the trigger as it remains the same
-- The existing trigger will now use the updated function
