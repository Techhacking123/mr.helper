-- ==========================================
-- MRHELPERAI FINAL PRODUCTION SQL SCHEMA
-- ==========================================

-- 1. UPDATE ORDERS TABLE
-- Add missing fields for the "Place Order" flow
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS user_phone TEXT,
ADD COLUMN IF NOT EXISTS user_price NUMERIC, -- User's budget
ADD COLUMN IF NOT EXISTS description TEXT;

-- 1.1 UPDATE STATUS CONSTRAINT
-- Allow 'request_open' for broadcast logic

-- First, clean up any invalid data that might violate the new constraint
UPDATE orders 
SET status = 'pending' 
WHERE status NOT IN ('pending', 'accepted', 'completed', 'request_open', 'rejected', 'cancelled');

DO $$ 
BEGIN 
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_status_check') THEN 
        ALTER TABLE orders DROP CONSTRAINT orders_status_check; 
    END IF; 
END $$;

ALTER TABLE orders ADD CONSTRAINT orders_status_check 
  CHECK (status IN ('pending', 'accepted', 'completed', 'request_open', 'rejected', 'cancelled'));

-- 2. CREATE ORDER_OFFERS TABLE (Adaptive to orders.id type)
-- Use dynamic SQL to handle cases where orders.id might be Integer instead of UUID
DO $$
DECLARE
    ref_type text;
    usr_type text;
BEGIN
    -- Check orders.id type
    SELECT data_type INTO ref_type FROM information_schema.columns 
    WHERE table_name = 'orders' AND column_name = 'id';
    
    -- Check users.id type (just in case)
    SELECT data_type INTO usr_type FROM information_schema.columns 
    WHERE table_name = 'users' AND column_name = 'id';
    
    -- Normalize types for DDL (integer/bigint -> bigint, uuid -> uuid)
    IF ref_type = 'integer' OR ref_type = 'bigint' THEN
        ref_type := 'BIGINT';
    ELSE
        ref_type := 'UUID';
    END IF;

    IF usr_type = 'integer' OR usr_type = 'bigint' THEN
        usr_type := 'BIGINT';
    ELSE
        usr_type := 'UUID';
    END IF;

    -- Dynamic Create Table
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'order_offers') THEN
        EXECUTE format('
            CREATE TABLE order_offers (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                order_id %s NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
                provider_id %s NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                price NUMERIC NOT NULL,
                status TEXT NOT NULL DEFAULT ''pending'' CHECK (status IN (''pending'', ''accepted'', ''rejected'')),
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )', ref_type, usr_type);
    END IF;
END $$;

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_order_offers_order_id ON order_offers(order_id);
CREATE INDEX IF NOT EXISTS idx_order_offers_provider_id ON order_offers(provider_id);

-- 3. FUNCTION TO NOTIFY MATCHING PROVIDERS
-- This triggers when a new order is created with status 'request_open'
CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
BEGIN
  -- Only run for open requests
  IF NEW.status = 'request_open' THEN
    
    -- Auto-expire (Best effort here, relies on auto_expire function existing)
    -- PERFORM auto_expire_subscriptions(); -- Might fail if not defined in this file context yet

    -- Find matching providers (STRICT CHECK)
    FOR provider_record IN 
      SELECT id FROM users 
      WHERE is_provider = TRUE 
      AND service_id = NEW.service_id 
      -- STRICT: Only active status
      AND subscription_status = 'active'::subscription_status_enum
      -- STRICT: Must have future end date
      AND subscription_end_date IS NOT NULL 
      AND subscription_end_date > NOW()
      -- Match location
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

-- DROP AND RECREATE TRIGGER
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
CREATE TRIGGER on_new_order_notify
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();

-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- ENABLE RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 1. USERS TABLE POLICIES
-- Everyone can read basics (needed for listings)
DROP POLICY IF EXISTS "Public Read Users" ON users;
CREATE POLICY "Public Read Users" ON users FOR SELECT USING (true);

-- Only user can update their own profile
DROP POLICY IF EXISTS "Update Own Profile" ON users;
CREATE POLICY "Update Own Profile" ON users FOR UPDATE USING (id = auth.uid()); -- Note: Since we use custom auth, this relies on your app passing context, but for standard RLS matching we might need a lookup. 
-- *CRITICAL NOTE*: Since you are using CUSTOM AUTH (not Supabase Auth), 'auth.uid()' will be NULL.
-- RLS works best with Supabase Auth. With Custom Auth + Anon Key, RLS is effectively "Anyone with Key".
-- TO FIX THIS FOR YOUR APP: We essentially have to allow anon access OR use a JWT strategy.
-- GIVEN your setup: We will allow OPEN access to these tables for the 'anon' role but trust the CLIENT parameters.
-- THIS IS A TRADE-OFF.

-- RELAXING RLS FOR CUSTOM AUTH ARCHITECTURE
-- (Real production apps should use Supabase.auth.signIn)

DROP POLICY IF EXISTS "Anon Full Policy Orders" ON orders;
CREATE POLICY "Anon Full Policy Orders" ON orders FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Anon Full Policy Offers" ON order_offers;
CREATE POLICY "Anon Full Policy Offers" ON order_offers FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Anon Full Policy Notifications" ON notifications;
CREATE POLICY "Anon Full Policy Notifications" ON notifications FOR ALL USING (true) WITH CHECK (true);

-- (If using Real Supabase Auth, we would use strict policies like:)
-- CREATE POLICY "Providers view matching orders" ON orders FOR SELECT USING (
--   status = 'request_open' AND service_id = (SELECT service_id FROM users WHERE id = auth.uid())
-- );

-- CRITICAL FIX: Allow public signups (Inserts)
DROP POLICY IF EXISTS "Public Insert Users" ON users;
CREATE POLICY "Public Insert Users" ON users FOR INSERT WITH CHECK (true);

-- 2. ADD FCM TOKEN SUPPORT
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 3. FIX FEEDBACK VISIBILITY (Task 2)
-- Ensure feedback is visible so the JOIN in ServiceResultPage works
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read Feedback" ON feedback;
CREATE POLICY "Public Read Feedback" ON feedback FOR SELECT USING (true);

-- 4. ENSURE SERVICES EXIST (Task 2)
-- This ensures 'Cleaning' ID exists for provider linkage.

ALTER TABLE services ADD COLUMN IF NOT EXISTS base_price NUMERIC;
ALTER TABLE services ADD COLUMN IF NOT EXISTS image_url TEXT;

INSERT INTO services (name, description, base_price, image_url)
SELECT 'Cleaning', 'Home and Office Cleaning', 50, 'https://example.com/cleaning.png'
WHERE NOT EXISTS (SELECT 1 FROM services WHERE name = 'Cleaning');

INSERT INTO services (name, description, base_price, image_url)
SELECT 'Plumbing', 'Pipe and Leak Repairs', 80, 'https://example.com/plumbing.png'
WHERE NOT EXISTS (SELECT 1 FROM services WHERE name = 'Plumbing');

INSERT INTO services (name, description, base_price, image_url)
SELECT 'Electrical', 'Wiring and Installation', 90, 'https://example.com/electrical.png'
WHERE NOT EXISTS (SELECT 1 FROM services WHERE name = 'Electrical');

-- 5. SUPABASE -> FIREBASE TRIGGER (Log Logic)
-- Real implementation requires an Edge Function.
-- This function mimics the trigger by logging to a table (create if needed)
CREATE TABLE IF NOT EXISTS push_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    title TEXT,
    body TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION log_push_notification()
RETURNS TRIGGER AS $$
DECLARE
    target_fcm TEXT;
BEGIN
    -- Get FCM token
    SELECT fcm_token INTO target_fcm FROM users WHERE id = NEW.user_id;
    
    IF target_fcm IS NOT NULL THEN
        INSERT INTO push_logs (user_id, title, body)
        VALUES (NEW.user_id, 'New Notification', NEW.message);
        
        -- HERE is where you would call:
        -- perform_net_request('https://<project>.supabase.co/functions/v1/push', ...);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_notification_push ON notifications;
CREATE TRIGGER on_notification_push
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION log_push_notification();
