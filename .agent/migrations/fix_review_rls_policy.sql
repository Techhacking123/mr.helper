-- ========================================
-- FIX: Provider Reviews - Disable RLS (Proper Solution)
-- ========================================
-- Since your app doesn't use Supabase Auth, we disable RLS
-- and rely on application-level permission checking

-- DISABLE Row Level Security on provider_reviews
ALTER TABLE provider_reviews DISABLE ROW LEVEL SECURITY;

-- Drop all existing policies (they're not needed without RLS)
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'provider_reviews'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON provider_reviews';
    END LOOP;
END $$;

-- Verify RLS is disabled
SELECT 
  tablename,
  rowsecurity 
FROM pg_tables 
WHERE tablename = 'provider_reviews';

-- This should show: rowsecurity = false
