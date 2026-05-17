-- ==========================================
-- FIX ADS STORAGE - COMPREHENSIVE RLS SETUP
-- ==========================================
-- This script fixes the storage RLS policies for the 'ads' bucket
-- allowing authenticated users (admin) to upload ad images
-- ==========================================

-- Step 1: Ensure the 'ads' bucket exists and is public
INSERT INTO storage.buckets (id, name, public) 
VALUES ('ads', 'ads', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Step 2: Drop all existing policies for 'ads' bucket to avoid conflicts
DROP POLICY IF EXISTS "ads_bucket_public_read" ON storage.objects;
DROP POLICY IF EXISTS "ads_bucket_authenticated_insert" ON storage.objects;
DROP POLICY IF EXISTS "ads_bucket_authenticated_update" ON storage.objects;
DROP POLICY IF EXISTS "ads_bucket_authenticated_delete" ON storage.objects;
DROP POLICY IF EXISTS "Public read access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated update" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated delete" ON storage.objects;
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete" ON storage.objects;

-- Step 3: Create comprehensive policies for 'ads' bucket

-- Allow public to read/view ads
CREATE POLICY "ads_bucket_public_read"
ON storage.objects FOR SELECT
TO public
USING ( bucket_id = 'ads' );

-- Allow ALL authenticated users to insert (upload) to ads bucket
CREATE POLICY "ads_bucket_authenticated_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'ads' );

-- Allow authenticated users to update files in ads bucket
CREATE POLICY "ads_bucket_authenticated_update"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'ads' )
WITH CHECK ( bucket_id = 'ads' );

-- Allow authenticated users to delete files in ads bucket
CREATE POLICY "ads_bucket_authenticated_delete"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'ads' );

-- Step 4: Verify the policies were created
SELECT 
  policyname,
  cmd,
  roles::text,
  CASE 
    WHEN qual IS NOT NULL THEN 'USING defined'
    ELSE 'No USING'
  END as using_clause,
  CASE 
    WHEN with_check IS NOT NULL THEN 'WITH CHECK defined'
    ELSE 'No WITH CHECK'
  END as with_check_clause
FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE 'ads_bucket%'
ORDER BY cmd;

-- Step 5: Verify bucket configuration
SELECT 
  id,
  name,
  public,
  created_at
FROM storage.buckets 
WHERE id = 'ads';

-- Success message
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE '✅ ADS STORAGE POLICIES CONFIGURED!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Bucket: ads';
  RAISE NOTICE 'Public Read: YES';
  RAISE NOTICE 'Authenticated Users Can: INSERT, UPDATE, DELETE';
  RAISE NOTICE '';
  RAISE NOTICE 'Next Steps:';
  RAISE NOTICE '1. Hot restart your Flutter app';
  RAISE NOTICE '2. Try uploading an ad image again';
  RAISE NOTICE '3. Check the terminal for any errors';
  RAISE NOTICE '================================================';
END $$;
