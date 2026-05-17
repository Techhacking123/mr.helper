-- ============================================
-- COMPLETE ORDER IMAGES BUCKET SETUP
-- ============================================
-- This script will:
-- 1. Create the bucket if it doesn't exist
-- 2. Make it public
-- 3. Set up all necessary policies
-- Run this in your Supabase SQL Editor

-- Step 1: Create the bucket (if it doesn't exist)
-- Note: This might error if bucket exists, that's OK!
INSERT INTO storage.buckets (id, name, public)
VALUES ('order_images', 'order_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Step 2: Make absolutely sure it's public
UPDATE storage.buckets
SET public = true
WHERE name = 'order_images';

-- Step 3: Remove ALL existing policies for order_images
DO $$ 
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'objects' 
        AND schemaname = 'storage'
        AND (policyname LIKE '%order_image%' OR policyname LIKE '%order_image%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
    END LOOP;
END $$;

-- Step 4: Create brand new simple policies
-- Policy 1: INSERT - Authenticated users can upload
CREATE POLICY "order_images_upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'order_images');

-- Policy 2: SELECT - Everyone can view (public bucket)
CREATE POLICY "order_images_view"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'order_images');

-- Policy 3: UPDATE - Authenticated users can update their files
CREATE POLICY "order_images_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'order_images');

-- Policy 4: DELETE - Authenticated users can delete their files
CREATE POLICY "order_images_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'order_images');

-- Step 5: Verify everything is set up correctly
SELECT 
    'Bucket Configuration:' as info,
    name,
    public as is_public,
    CASE 
        WHEN public THEN '✅ PUBLIC (Good!)'
        ELSE '❌ PRIVATE (Bad! Needs to be public)'
    END as status
FROM storage.buckets
WHERE name = 'order_images';

-- Step 6: Show all policies
SELECT 
    'Storage Policies:' as info,
    policyname as policy_name,
    cmd as command_type,
    CASE 
        WHEN roles = '{authenticated}' THEN 'Authenticated Users'
        WHEN roles = '{public}' THEN 'Public (Everyone)'
        ELSE roles::text
    END as who_can_use
FROM pg_policies
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE 'order_images%'
ORDER BY cmd;

-- Success message
SELECT '✅ ORDER IMAGES BUCKET SETUP COMPLETE!' as result;
