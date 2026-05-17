-- ==========================================
-- ADMIN ADS - FIX STORAGE POLICIES
-- ==========================================
-- The bucket exists, just need to ensure policies are correct
-- ==========================================

-- First, check current policies
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage';

-- Drop existing policies on storage.objects for ads bucket if any
DROP POLICY IF EXISTS "Public read access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated update" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated delete" ON storage.objects;
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete" ON storage.objects;

-- Create fresh policies for ads bucket
CREATE POLICY "ads_bucket_public_read"
ON storage.objects FOR SELECT
TO public
USING ( bucket_id = 'ads' );

CREATE POLICY "ads_bucket_authenticated_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'ads' );

CREATE POLICY "ads_bucket_authenticated_update"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'ads' );

CREATE POLICY "ads_bucket_authenticated_delete"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'ads' );

-- Verify bucket is public
UPDATE storage.buckets 
SET public = true 
WHERE id = 'ads';

-- Check policies were created
SELECT 
  policyname,
  cmd,
  roles
FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE 'ads_bucket%';

-- Success message
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE '✅ STORAGE POLICIES CONFIGURED!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Bucket: ads (already exists)';
  RAISE NOTICE 'Public: YES';
  RAISE NOTICE 'Policies: Created for SELECT, INSERT, UPDATE, DELETE';
  RAISE NOTICE '';
  RAISE NOTICE 'Next: Hot restart Flutter app and test image upload';
  RAISE NOTICE '================================================';
END $$;
