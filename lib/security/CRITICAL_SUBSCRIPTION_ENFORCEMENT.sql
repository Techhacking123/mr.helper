-- ==========================================
-- CRITICAL: STRICT SUBSCRIPTION ENFORCEMENT
-- ==========================================
-- This migration ensures ONLY providers with ACTIVE subscriptions
-- receive order requests and notifications
-- 
-- Run this ENTIRE script in Supabase SQL Editor
-- ==========================================

-- Step 1: Add subscription_status ENUM type
DO $$ BEGIN
    CREATE TYPE subscription_status_enum AS ENUM ('none', 'active', 'expired');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Step 2: Add subscription_status column to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_status subscription_status_enum DEFAULT 'none';

-- Step 3: Add subscription end_date column
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_end_date TIMESTAMPTZ;

-- Step 4: Migrate existing data
-- Convert existing is_subscribed and subscription_expiry to new format
UPDATE users
SET subscription_status = CASE
    WHEN is_subscribed = TRUE AND (subscription_expiry IS NULL OR subscription_expiry > NOW()) THEN 'active'::subscription_status_enum
    WHEN is_subscribed = TRUE AND subscription_expiry <= NOW() THEN 'expired'::subscription_status_enum
    ELSE 'none'::subscription_status_enum
END,
subscription_end_date = subscription_expiry
WHERE is_provider = TRUE;

-- Step 5: Create function to automatically expire subscriptions
CREATE OR REPLACE FUNCTION auto_expire_subscriptions()
RETURNS void AS $$
BEGIN
  UPDATE users
  SET subscription_status = 'expired'::subscription_status_enum
  WHERE is_provider = TRUE 
    AND subscription_status = 'active'::subscription_status_enum
    AND subscription_end_date IS NOT NULL
    AND subscription_end_date <= NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 6: Create trigger to validate subscription on activation
CREATE OR REPLACE FUNCTION validate_subscription_on_update()
RETURNS TRIGGER AS $$
BEGIN
  -- Auto-expire if end_date has passed
  IF NEW.subscription_end_date IS NOT NULL AND NEW.subscription_end_date <= NOW() THEN
    NEW.subscription_status = 'expired'::subscription_status_enum;
  END IF;
  
  -- Ensure consistency: if status is 'active', must have end_date
  IF NEW.subscription_status = 'active'::subscription_status_enum AND NEW.subscription_end_date IS NULL THEN
    RAISE EXCEPTION 'Active subscription must have an end_date';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS validate_subscription_trigger ON users;

-- Create trigger
CREATE TRIGGER validate_subscription_trigger
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION validate_subscription_on_update();

-- Step 7: CRITICAL - Update notification trigger with STRICT subscription check
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
        
        RAISE NOTICE 'Notified provider: % (Status: %, Expiry: %)', 
          provider_record.full_name,
          provider_record.subscription_status,
          provider_record.subscription_end_date;
      END IF;
    END LOOP;
    
    RAISE NOTICE 'Order %. Total providers notified: %', NEW.id, notified_count;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure trigger exists
DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;
CREATE TRIGGER notify_providers_on_order_trigger
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();

-- Step 8: Create view for active providers only
CREATE OR REPLACE VIEW active_subscribed_providers AS
SELECT 
  id,
  full_name,
  email,
  phone_number,
  service_id,
  location,
  subscription_status,
  subscription_end_date,
  EXTRACT(DAY FROM (subscription_end_date - NOW())) as days_remaining
FROM users
WHERE is_provider = TRUE
  AND subscription_status = 'active'::subscription_status_enum
  AND subscription_end_date > NOW();

-- Step 9: Create function to check if provider can receive orders
CREATE OR REPLACE FUNCTION can_receive_orders(provider_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  provider_status subscription_status_enum;
  provider_end_date TIMESTAMPTZ;
BEGIN
  SELECT subscription_status, subscription_end_date
  INTO provider_status, provider_end_date
  FROM users
  WHERE id = provider_id AND is_provider = TRUE;
  
  -- Must be active AND have future end_date
  RETURN provider_status = 'active'::subscription_status_enum 
         AND provider_end_date IS NOT NULL 
         AND provider_end_date > NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 10: Create helper function to activate subscription
CREATE OR REPLACE FUNCTION activate_subscription(
  provider_id UUID,
  duration_days INTEGER DEFAULT 7
)
RETURNS void AS $$
BEGIN
  UPDATE users
  SET 
    subscription_status = 'active'::subscription_status_enum,
    subscription_end_date = NOW() + (duration_days || ' days')::INTERVAL,
    is_subscribed = TRUE,
    subscription_expiry = NOW() + (duration_days || ' days')::INTERVAL
  WHERE id = provider_id AND is_provider = TRUE;
  
  RAISE NOTICE 'Activated subscription for provider % until %', 
    provider_id, 
    NOW() + (duration_days || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 11: Add index for performance
CREATE INDEX IF NOT EXISTS idx_users_subscription_active 
ON users(subscription_status, subscription_end_date) 
WHERE is_provider = TRUE;

-- Step 12: Verification queries
-- Uncomment to see results:

-- Check active providers
-- SELECT id, full_name, subscription_status, subscription_end_date 
-- FROM users WHERE is_provider = TRUE;

-- Test if a provider can receive orders
-- SELECT can_receive_orders('YOUR_PROVIDER_ID_HERE');

-- View all active subscribed providers
-- SELECT * FROM active_subscribed_providers;

-- ==========================================
-- MIGRATION COMPLETE
-- ==========================================
-- Next steps:
-- 1. Update Flutter app to use subscription_status field
-- 2. Test with active and inactive providers
-- 3. Set up periodic job to run auto_expire_subscriptions()
-- ==========================================
