-- ==========================================
-- FIX ADS TABLE RLS POLICIES
-- ==========================================
-- This fixes the RLS policies on the 'ads' table itself
-- The error is happening when inserting into the ads TABLE,
-- not when uploading to the ads storage bucket
-- ==========================================

-- Step 1: Check if ads table exists and has RLS enabled
SELECT 
  tablename,
  rowsecurity
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'ads';

-- Step 2: Create the ads table if it doesn't exist
CREATE TABLE IF NOT EXISTS ads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  image_url TEXT NOT NULL,
  link TEXT,
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Step 3: Enable RLS on the ads table
ALTER TABLE ads ENABLE ROW LEVEL SECURITY;

-- Step 4: Drop any existing policies
DROP POLICY IF EXISTS "Public read ads" ON ads;
DROP POLICY IF EXISTS "Authenticated insert ads" ON ads;
DROP POLICY IF EXISTS "Authenticated update ads" ON ads;
DROP POLICY IF EXISTS "Authenticated delete ads" ON ads;
DROP POLICY IF EXISTS "Anon read ads" ON ads;

-- Step 5: Create comprehensive RLS policies for ads table

-- Allow everyone (public/anon) to SELECT/read ads
CREATE POLICY "Public read ads"
ON ads FOR SELECT
TO public
USING (true);

-- Allow authenticated users to INSERT ads
CREATE POLICY "Authenticated insert ads"
ON ads FOR INSERT
TO authenticated
WITH CHECK (true);

-- Allow authenticated users to UPDATE ads
CREATE POLICY "Authenticated update ads"
ON ads FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- Allow authenticated users to DELETE ads
CREATE POLICY "Authenticated delete ads"
ON ads FOR DELETE
TO authenticated
USING (true);

-- Step 6: CRITICAL FIX - Also allow ANON role (since you use custom auth)
-- Based on your supabase_rls.sql pattern, you use anon key with custom auth

DROP POLICY IF EXISTS "Anon full access ads" ON ads;
CREATE POLICY "Anon full access ads"
ON ads FOR ALL
TO anon
USING (true)
WITH CHECK (true);

-- Step 7: Verify the policies were created
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles::text,
  cmd
FROM pg_policies 
WHERE tablename = 'ads' 
AND schemaname = 'public'
ORDER BY cmd, policyname;

-- Step 8: Create an index for better performance
CREATE INDEX IF NOT EXISTS idx_ads_is_active ON ads(is_active);
CREATE INDEX IF NOT EXISTS idx_ads_end_date ON ads(end_date);

-- Success message
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE '✅ ADS TABLE RLS POLICIES CONFIGURED!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Table: ads';
  RAISE NOTICE 'RLS Enabled: YES';
  RAISE NOTICE 'Policies Created:';
  RAISE NOTICE '  - Public/Anon can READ ads';
  RAISE NOTICE '  - Authenticated users can INSERT';
  RAISE NOTICE '  - Authenticated users can UPDATE';
  RAISE NOTICE '  - Authenticated users can DELETE';
  RAISE NOTICE '  - Anon role has FULL access (for custom auth)';
  RAISE NOTICE '';
  RAISE NOTICE 'Next Steps:';
  RAISE NOTICE '1. Copy the policy verification results above';
  RAISE NOTICE '2. Hot restart your Flutter app';
  RAISE NOTICE '3. Try uploading an ad again';
  RAISE NOTICE '================================================';
END $$;
