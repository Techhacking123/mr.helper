-- FIX PROVIDER NOTIFICATION TRIGGER
-- This script relaxes the strict checks to ensure providers get notifications

CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  loc_name TEXT;
BEGIN
  -- Only run for open requests
  IF NEW.status = 'request_open' THEN
    
    -- Get location name safely
    SELECT name INTO loc_name FROM locations WHERE id = NEW.location_id;

    -- Find matching providers (RELAXED CHECK)
    FOR provider_record IN 
      SELECT id FROM users 
      WHERE is_provider = TRUE 
      AND service_id = NEW.service_id 
      -- Check 1: Status (Handle text or enum)
      AND (subscription_status::text = 'active' OR subscription_status IS NULL)
      -- Check 2: Date (Allow nulls for legacy/testing, handle timezone)
      AND (subscription_end_date IS NULL OR subscription_end_date > NOW())
      -- Check 3: Location (Allow providers with NO location to see all, or exact match)
      AND (location IS NULL OR location = '' OR location = loc_name)
    LOOP
      -- Insert Notification
      INSERT INTO notifications (user_id, order_id, message, created_at)
      VALUES (
        provider_record.id, 
        NEW.id, 
        'New Service Request: ' || (SELECT name FROM services WHERE id = NEW.service_id) || ' in ' || COALESCE(loc_name, 'your area'), 
        NOW()
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure Trigger Exists
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
CREATE TRIGGER on_new_order_notify
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();
