-- ==========================================
-- PENDING PROVIDERS KYC SYSTEM
-- ==========================================
-- This migration creates a system where provider data is kept in a separate
-- table during KYC approval, and only moved to users table after approval

-- 1. CREATE PENDING_PROVIDERS TABLE
CREATE TABLE IF NOT EXISTS public.pending_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone_number TEXT,
    bio TEXT,
    location TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    avatar_url TEXT,
    service_id UUID,
    service_type TEXT,
    aadhar_card_url TEXT,
    pan_card_url TEXT,
    price NUMERIC,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. CREATE INDEX FOR PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_pending_providers_status ON pending_providers(status);
CREATE INDEX IF NOT EXISTS idx_pending_providers_email ON pending_providers(email);

-- 3. ENABLE RLS ON PENDING_PROVIDERS
ALTER TABLE pending_providers ENABLE ROW LEVEL SECURITY;

-- Allow public insert (for signup)
DROP POLICY IF EXISTS "Public Insert Pending Providers" ON pending_providers;
CREATE POLICY "Public Insert Pending Providers" ON pending_providers 
FOR INSERT WITH CHECK (true);

-- Allow public select (for admin to view)
DROP POLICY IF EXISTS "Public Read Pending Providers" ON pending_providers;
CREATE POLICY "Public Read Pending Providers" ON pending_providers 
FOR SELECT USING (true);

-- Allow public update (for admin to approve/reject)
DROP POLICY IF EXISTS "Public Update Pending Providers" ON pending_providers;
CREATE POLICY "Public Update Pending Providers" ON pending_providers 
FOR UPDATE USING (true) WITH CHECK (true);

-- Allow public delete (for cleanup)
DROP POLICY IF EXISTS "Public Delete Pending Providers" ON pending_providers;
CREATE POLICY "Public Delete Pending Providers" ON pending_providers 
FOR DELETE USING (true);

-- 4. FUNCTION TO APPROVE PROVIDER AND MOVE TO USERS TABLE
CREATE OR REPLACE FUNCTION approve_provider(provider_id UUID)
RETURNS VOID AS $$
DECLARE
    pending_record RECORD;
BEGIN
    -- Get the pending provider record
    SELECT * INTO pending_record FROM pending_providers 
    WHERE id = provider_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pending provider not found or already processed';
    END IF;
    
    -- Insert into users table
    INSERT INTO users (
        email,
        password,
        full_name,
        phone_number,
        is_provider,
        bio,
        location,
        latitude,
        longitude,
        avatar_url,
        service_id,
        service_type,
        aadhar_card_url,
        pan_card_url,
        price,
        status,
        created_at
    ) VALUES (
        pending_record.email,
        pending_record.password,
        pending_record.full_name,
        pending_record.phone_number,
        true, -- is_provider
        pending_record.bio,
        pending_record.location,
        pending_record.latitude,
        pending_record.longitude,
        pending_record.avatar_url,
        pending_record.service_id,
        pending_record.service_type,
        pending_record.aadhar_card_url,
        pending_record.pan_card_url,
        pending_record.price,
        'active', -- Set status to active
        pending_record.created_at
    );
    
    -- Delete from pending_providers after successfully moving to users
    DELETE FROM pending_providers WHERE id = provider_id;
    
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. FUNCTION TO REJECT PROVIDER
CREATE OR REPLACE FUNCTION reject_provider(provider_id UUID)
RETURNS VOID AS $$
BEGIN
    -- Delete rejected provider immediately
    -- This allows them to re-apply with the same email
    DELETE FROM pending_providers 
    WHERE id = provider_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pending provider not found or already processed';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. CLEANUP FUNCTION - NO LONGER NEEDED
-- Rejected providers are immediately deleted upon rejection
-- Approved providers are immediately deleted upon approval
-- Therefore, pending_providers only contains truly pending applications

-- 7. MIGRATE EXISTING PENDING PROVIDERS FROM USERS TABLE
-- Move existing pending providers to the new pending_providers table
INSERT INTO pending_providers (
    email,
    password,
    full_name,
    phone_number,
    bio,
    location,
    latitude,
    longitude,
    avatar_url,
    service_id,
    service_type,
    aadhar_card_url,
    pan_card_url,
    price,
    status,
    created_at
)
SELECT 
    email,
    password,
    full_name,
    phone_number,
    bio,
    location,
    latitude,
    longitude,
    avatar_url,
    service_id,
    service_type,
    aadhar_card_url,
    pan_card_url,
    price,
    status,
    created_at
FROM users
WHERE is_provider = true AND status = 'pending'
ON CONFLICT (email) DO NOTHING;

-- 8. DELETE MIGRATED PENDING PROVIDERS FROM USERS TABLE
DELETE FROM users 
WHERE is_provider = true AND status = 'pending';

-- 9. ALSO HANDLE REJECTED PROVIDERS
-- Move existing rejected providers to pending_providers
INSERT INTO pending_providers (
    email,
    password,
    full_name,
    phone_number,
    bio,
    location,
    latitude,
    longitude,
    avatar_url,
    service_id,
    service_type,
    aadhar_card_url,
    pan_card_url,
    price,
    status,
    created_at
)
SELECT 
    email,
    password,
    full_name,
    phone_number,
    bio,
    location,
    latitude,
    longitude,
    avatar_url,
    service_id,
    service_type,
    aadhar_card_url,
    pan_card_url,
    price,
    status,
    created_at
FROM users
WHERE is_provider = true AND status = 'rejected'
ON CONFLICT (email) DO NOTHING;

-- Delete rejected providers from users table
DELETE FROM users 
WHERE is_provider = true AND status = 'rejected';

-- 10. UPDATE clear_rejected_user FUNCTION TO WORK WITH PENDING_PROVIDERS
-- Note: Since rejected providers are immediately deleted, this is mainly for legacy cleanup
CREATE OR REPLACE FUNCTION clear_rejected_user(email_input TEXT)
RETURNS VOID AS $$
BEGIN
    -- Delete from pending_providers (in case of any edge cases)
    DELETE FROM pending_providers 
    WHERE email = email_input;
    
    -- Also delete from users table if rejected (legacy cleanup)
    DELETE FROM users 
    WHERE email = email_input 
    AND status = 'rejected';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
