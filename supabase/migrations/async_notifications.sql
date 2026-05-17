-- PHASE 3: ASYNC / OPTIMIZED NOTIFICATIONS
-- Optimization: Replace synchronous row-by-row looping with set-based batch insertion.
-- This significantly reduces the time it takes to create an order.

-- 1. Create/Replace the Notification Function
CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  service_name TEXT;
  location_name TEXT;
BEGIN
  -- Only proceed for new open requests
  IF NEW.status = 'request_open' THEN
    
    -- Fetch service name and location name
    SELECT name INTO service_name FROM services WHERE id = NEW.service_id;
    SELECT name INTO location_name FROM locations WHERE id = NEW.location_id;
    
    -- BATCH INSERT: Inserts notifications for ALL matching providers in one operation
    -- This relies on the indexes created in Phase 1 (idx_users_provider_active)
    INSERT INTO notifications (user_id, order_id, message, is_read, type, created_at)
    SELECT 
      u.id, 
      NEW.id, 
      'New Request: ' || COALESCE(service_name, 'Service') || ' in ' || COALESCE(location_name, 'your area'),
      false,
      'order_request', -- Ensure this type exists or use 'general'
      NOW()
    FROM users u
    WHERE 
      u.is_provider = true 
      AND u.service_id = NEW.service_id 
      AND u.subscription_status = 'active'
      -- Match location by Name because users table stores location Name, while orders stores ID
      AND (u.location = location_name OR u.location IS NULL)
      ;
      
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Ensure Trigger is Linked
DROP TRIGGER IF EXISTS on_order_created_notify ON orders;
CREATE TRIGGER on_order_created_notify
  AFTER INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_providers_on_order();
