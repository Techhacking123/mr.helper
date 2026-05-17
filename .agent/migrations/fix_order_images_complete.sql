-- ============================================
-- DIAGNOSE AND FIX ORDER IMAGES UPLOAD ISSUE
-- ============================================
-- Run this complete script in Supabase SQL Editor

-- PART 1: DIAGNOSTIC - Check current state
-- =========================================

SELECT '=== STEP 1: Check if bucket exists ===' as step;
SELECT 
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types,
    CASE 
        WHEN public THEN '✅ Bucket is PUBLIC (Good!)'
        ELSE '❌ Bucket is PRIVATE (This is the problem!)'
    END as diagnosis
FROM storage.buckets
WHERE name = 'order_images';

SELECT '=== STEP 2: Check current policies ===' as step;
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd as operation,
    qual as using_expression,
    with_check as check_expression
FROM pg_policies
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND (policyname LIKE '%order%' OR policyname LIKE '%image%')
ORDER BY policyname;

-- PART 2: FIX - Clean and recreate everything
-- =========================================

SELECT '=== STEP 3: Creating/Updating bucket ===' as step;
-- Create bucket if it doesn't exist, update if it does
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'order_images', 
    'order_images', 
    true,
    10485760, -- 10MB max file size
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) 
DO UPDATE SET 
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[];

SELECT '=== STEP 4: Removing old policies ===' as step;
-- Drop ALL policies related to order_images bucket
DROP POLICY IF EXISTS "order_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "order_images_view" ON storage.objects;
DROP POLICY IF EXISTS "order_images_update" ON storage.objects;
DROP POLICY IF EXISTS "order_images_delete" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to upload order images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public to view order images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete their order images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can upload to order_images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view order_images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can delete from order_images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can update order_images" ON storage.objects;

-- Also clean up any orphan policies
DO $$ 
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'objects' 
        AND schemaname = 'storage'
        AND (policyname ILIKE '%order%' OR policyname ILIKE '%image%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
    END LOOP;
END $$;

SELECT '=== STEP 5: Creating NEW simple policies ===' as step;

-- Policy 1: INSERT - Allow ALL authenticated users to upload to order_images bucket
CREATE POLICY "order_images_insert_policy"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'order_images');

-- Policy 2: SELECT - Allow EVERYONE to view (public bucket)
CREATE POLICY "order_images_select_policy"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'order_images');

-- Policy 3: UPDATE - Allow authenticated users to update
CREATE POLICY "order_images_update_policy"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'order_images')
WITH CHECK (bucket_id = 'order_images');

-- Policy 4: DELETE - Allow authenticated users to delete
CREATE POLICY "order_images_delete_policy"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'order_images');

-- PART 3: VERIFICATION
-- =========================================

SELECT '=== STEP 6: Verification - Bucket Status ===' as step;
SELECT 
    name as bucket_name,
    public as is_public,
    file_size_limit,
    allowed_mime_types,
    CASE 
        WHEN public THEN '✅ PUBLIC - Ready to use!'
        ELSE '❌ PRIVATE - Still has issues!'
    END as status
FROM storage.buckets
WHERE name = 'order_images';

SELECT '=== STEP 7: Verification - Active Policies ===' as step;
SELECT 
    policyname as policy_name,
    cmd as operation,
    CASE 
        WHEN roles::text LIKE '%authenticated%' THEN 'Authenticated Users'
        WHEN roles::text LIKE '%public%' THEN 'Public (Everyone)'        ELSE roles::text
    END as applies_to,
    'order_images bucket' as target
FROM pg_policies
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE 'order_images%'
ORDER BY cmd;

-- Final success message
SELECT 
    '🎉 BUCKET SETUP COMPLETE! 🎉' as result,
    'The order_images bucket is now configured with:' as info1,
    '✅ Public access enabled' as info2,
    '✅ File size limit: 10MB' as info3,
    '✅ Allowed types: JPEG, PNG, WebP' as info4,
    '✅ 4 RLS policies (INSERT, SELECT, UPDATE, DELETE)' as info5,
    'Now hot reload your Flutter app and try uploading again!' as next_step;
