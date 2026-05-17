-- ==========================================
-- FIX DUPLICATE NOTIFICATIONS
-- ==========================================
-- Problem: The 'notify_providers_on_order' trigger fires on INSERT OR UPDATE.
-- The order creation flow does an INSERT (status='request_open') followed by an UPDATE (adding images).
-- This causes the notification logic to run TWICE, sending duplicate push notifications.
--
-- Solution:
-- 1. Modify the function to check TG_OP (Trigger Operation).
-- 2. Only notify on INSERT if status is 'request_open'.
-- 3. Only notify on UPDATE if status CHANGED TO 'request_open' (transition).
-- 4. Add an idempotency check (IF NOT EXISTS) before inserting into the notifications table.

CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
  notified_count INTEGER := 0;
  should_notify BOOLEAN := FALSE;
BEGIN
  -- Determine if we should notify based on TG_OP and status change
  IF (TG_OP = 'INSERT' AND NEW.status = 'request_open') THEN
      should_notify := TRUE;
  ELSIF (TG_OP = 'UPDATE' AND NEW.status = 'request_open' AND OLD.status IS DISTINCT FROM 'request_open') THEN
      should_notify := TRUE;
      -- RAISE NOTICE 'Status changed to request_open, triggering notification';
  END IF;

  -- Verify if we should proceed (and if function 'auto_expire_subscriptions' exists)
  -- We assume 'auto_expire_subscriptions' exists from previous migrations. 
  -- If not, we can skip it or wrap in exception block, but it's better to keep existing logic.

  IF should_notify THEN
    
    -- Attempt to expire subscriptions (Keep existing logic if function exists)
    BEGIN
        PERFORM auto_expire_subscriptions();
    EXCEPTION WHEN OTHERS THEN
        -- Ignore if function doesn't exist, to prevent breaking order flow
        RAISE WARNING 'auto_expire_subscriptions failed or missing: %', SQLERRM;
    END;
    
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
        
        -- IDEMPOTENCY CHECK: Ensure we haven't already notified this provider for this order
        IF NOT EXISTS (
            SELECT 1 FROM notifications 
            WHERE user_id = provider_record.id 
            AND order_id = NEW.id
        ) THEN
            -- Insert Notification
            INSERT INTO notifications (user_id, order_id, message, created_at)
            VALUES (
              provider_record.id, 
              NEW.id, 
              'New service request available in your area!', 
              NOW()
            );
            
            notified_count := notified_count + 1;
            
            -- RAISE NOTICE 'Notified provider: %', provider_record.full_name;
        -- ELSE
            -- RAISE NOTICE 'Provider % already notified for order %', provider_record.full_name, NEW.id;
        END IF;

      END IF;
    END LOOP;
    
    RAISE NOTICE 'Order % (Op: %). Total providers notified: %', NEW.id, TG_OP, notified_count;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the trigger is correctly set to capture INSERT and UPDATE
-- (The existing trigger likely is "AFTER INSERT OR UPDATE", which is fine now that we check TG_OP)
