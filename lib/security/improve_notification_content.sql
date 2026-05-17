-- IMPROVE NOTIFICATION CONTENT
-- ============================
-- Objective: Include User Name and Service Type in the push notification.
--
-- Logic:
-- 1. Fetch the Buyer's 'full_name' from the 'users' table using 'buyer_id'.
-- 2. Extract the Service Type from the order 'description' (First line: "Service Type: ...").
-- 3. Construct a dynamic message.

CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  notified_count INTEGER := 0;
  should_notify BOOLEAN := FALSE;
  
  -- Variables for dynamic content
  v_buyer_name TEXT := 'A User';
  v_service_type TEXT := 'Service';
  v_message_body TEXT;
BEGIN
  -- 1. LOGIC CHECK: When to notify?
  IF (TG_OP = 'INSERT' AND NEW.status = 'request_open') THEN
      should_notify := TRUE;
  ELSIF (TG_OP = 'UPDATE' AND NEW.status = 'request_open' AND OLD.status IS DISTINCT FROM 'request_open') THEN
      should_notify := TRUE;
  END IF;

  IF should_notify THEN
  
    -- 2. PREPARE DYNAMIC CONTENT
    -- Get Buyer Name
    SELECT full_name INTO v_buyer_name 
    FROM users 
    WHERE id = NEW.buyer_id;
    
    IF v_buyer_name IS NULL OR v_buyer_name = '' THEN
        v_buyer_name := 'A Customer';
    END IF;

    -- Extract Service Type from Description
    -- Format assumed from app: "Service Type: [Type]\n[Details]"
    -- We take the first line, then remove the prefix.
    v_service_type := split_part(NEW.description, E'\n', 1);
    v_service_type := REPLACE(v_service_type, 'Service Type: ', '');
    
    -- Fallback if parsing fails or empty
    IF v_service_type IS NULL OR length(v_service_type) < 2 THEN
        v_service_type := 'Service';
    END IF;
    
    -- Construct the Message
    -- Example: "Karthik needs Bathroom Cleaning in your area!"
    v_message_body := v_buyer_name || ' needs ' || v_service_type || ' in your area!';

    -- (Optional) Expire subscriptions first
    BEGIN
        PERFORM auto_expire_subscriptions();
    EXCEPTION WHEN OTHERS THEN
        -- Ignore
    END;
    
    -- 3. FIND MATCHING PROVIDERS
    FOR provider_record IN 
      SELECT 
        id,
        full_name
      FROM users 
      WHERE is_provider = TRUE 
        AND service_id = NEW.service_id 
        AND subscription_status = 'active'
        AND subscription_end_date > NOW()
        AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL)
    LOOP
      
        -- 4. IDEMPOTENCY CHECK
        IF NOT EXISTS (
            SELECT 1 FROM notifications 
            WHERE user_id = provider_record.id 
            AND order_id = NEW.id
        ) THEN
            -- Insert Notification with DYNAMIC CONTENT
            INSERT INTO notifications (user_id, order_id, title, message, created_at)
            VALUES (
              provider_record.id, 
              NEW.id, 
              'New Job Opportunity', -- Title
              v_message_body,        -- Dynamic Message
              NOW()
            );
            
            notified_count := notified_count + 1;
        END IF;

    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-apply trigger just in case
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
CREATE TRIGGER on_new_order_notify
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();
