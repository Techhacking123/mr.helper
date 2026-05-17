-- ==========================================
-- FIX ADS STORAGE - ANON ROLE POLICY
-- ==========================================
-- The ads TABLE has anon policies, but the ads STORAGE BUCKET
-- only has "authenticated" policies. Since your app uses anon role,
-- we need to add anon policies to the storage bucket too!
-- ==========================================

-- Step 1: Verify current storage policies (should show authenticated, not anon)
SELECT 
  policyname,
  cmd,
  roles::text,
  CASE 
    WHEN policyname LIKE '%anon%' THEN '✅ ANON POLICY'
    WHEN policyname LIKE '%authenticated%' THEN '⚠️ AUTHENTICATED ONLY'
    ELSE '❓ OTHER'
  END as status
FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE '%ads%'
ORDER BY cmd;

-- Step 2: Drop the old authenticated-only policies
DROP POLICY IF EXISTS "ads_bucket_authenticated_insert" ON storage.objects;
DROP POLICY IF EXISTS "ads_bucket_authenticated_update" ON storage.objects;
DROP POLICY IF EXISTS "ads_bucket_authenticated_delete" ON storage.objects;

-- Step 3: Create ANON policies for storage operations
-- (Keep the public read policy as-is)

-- Allow ANON role to INSERT (upload) to ads bucket
CREATE POLICY "ads_bucket_anon_insert"
ON storage.objects FOR INSERT
TO anon
WITH CHECK ( bucket_id = 'ads' );

-- Allow ANON role to UPDATE files in ads bucket
CREATE POLICY "ads_bucket_anon_update"
ON storage.objects FOR UPDATE
TO anon
USING ( bucket_id = 'ads' )
WITH CHECK ( bucket_id = 'ads' );

-- Allow ANON role to DELETE files in ads bucket
CREATE POLICY "ads_bucket_anon_delete"
ON storage.objects FOR DELETE
TO anon
USING ( bucket_id = 'ads' );

-- Step 4: Also keep authenticated policies for future use
CREATE POLICY "ads_bucket_authenticated_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'ads' );

CREATE POLICY "ads_bucket_authenticated_update"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'ads' )
WITH CHECK ( bucket_id = 'ads' );

CREATE POLICY "ads_bucket_authenticated_delete"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'ads' );

-- Step 5: Verify the new policies
SELECT 
  policyname,
  cmd,
  roles::text,
  CASE 
    WHEN roles::text LIKE '%anon%' THEN '✅ ANON ENABLED'
    WHEN roles::text LIKE '%authenticated%' THEN '✅ AUTH ENABLED'
    WHEN roles::text LIKE '%public%' THEN '✅ PUBLIC ENABLED'
    ELSE '❓'
  END as check_status
FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE '%ads%'
ORDER BY cmd, roles;

-- Success message
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE '✅ STORAGE ANON POLICIES CREATED!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Fixed: Storage bucket now allows ANON role';
  RAISE NOTICE '';
  RAISE NOTICE 'Before: Only authenticated role could upload';
  RAISE NOTICE 'After: Both anon AND authenticated can upload';
  RAISE NOTICE '';
  RAISE NOTICE 'This matches your app architecture which uses';
  RAISE NOTICE 'the anon key for all operations.';
  RAISE NOTICE '';
  RAISE NOTICE 'Next: Hot restart Flutter and try uploading!';
  RAISE NOTICE '================================================';
END $$;
