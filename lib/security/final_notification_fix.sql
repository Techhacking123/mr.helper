-- FIX DUPLICATE NOTIFICATIONS (ROOT CAUSE: INSERT + UPDATE FLOW)
-- ===============================================================
-- Root Cause: The app creates an order (INSERT) and then immediately updates it with images (UPDATE).
-- The notification trigger was firing on BOTH events because the status was 'request_open' in both cases.
--
-- Solution:
-- 1. We replace the trigger function to explicitly check if it's an INSERT or if the status CHANGED during an UPDATE.
-- 2. We use 'TG_OP' to distinguish between INSERT and UPDATE.
-- 3. We keep the 'idempotency check' (IF NOT EXISTS) as a backup safety measure.

CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  notified_count INTEGER := 0;
  should_notify BOOLEAN := FALSE;
BEGIN
  -- 1. LOGIC CHECK: When to notify?
  -- Case A: It is a new order (INSERT) and status is 'request_open'
  IF (TG_OP = 'INSERT' AND NEW.status = 'request_open') THEN
      should_notify := TRUE;
      
  -- Case B: It is an update (UPDATE), BUT only if status CHANGED to 'request_open' (e.g. from 'draft')
  -- This prevents notifications when just updating images or other fields while status stays 'request_open'.
  ELSIF (TG_OP = 'UPDATE' AND NEW.status = 'request_open' AND OLD.status IS DISTINCT FROM 'request_open') THEN
      should_notify := TRUE;
  END IF;

  IF should_notify THEN
    
    -- (Optional) Expire subscriptions first to ensure valid list
    BEGIN
        PERFORM auto_expire_subscriptions();
    EXCEPTION WHEN OTHERS THEN
        -- Safely ignore if function is missing
    END;
    
    -- 2. FIND MATCHING PROVIDERS
    FOR provider_record IN 
      SELECT 
        id,
        full_name
      FROM users 
      WHERE is_provider = TRUE 
        -- Must match service
        AND service_id = NEW.service_id 
        -- Must have ACTIVE subscription
        AND subscription_status = 'active'
        AND subscription_end_date > NOW()
        -- Must match location (or have global location if null)
        AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL)
    LOOP
      
        -- 3. IDEMPOTENCY CHECK (Safety Net)
        -- Check if we already notified this user for this specific order
        IF NOT EXISTS (
            SELECT 1 FROM notifications 
            WHERE user_id = provider_record.id 
            AND order_id = NEW.id
        ) THEN
            -- Insert Notification
            INSERT INTO notifications (user_id, order_id, title, message, created_at)
            VALUES (
              provider_record.id, 
              NEW.id, 
              'New Service Request',
              'New service request available in your area!', 
              NOW()
            );
            
            notified_count := notified_count + 1;
        END IF;

    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RE-APPLY THE TRIGGER
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;

CREATE TRIGGER on_new_order_notify
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();
