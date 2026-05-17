-- ============================================
-- ORDER IMAGES FEATURE - DATABASE MIGRATION
-- ============================================
-- Safe to run multiple times (idempotent)

-- Step 1: Add images column to orders table
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]'::jsonb;

-- Add comment for documentation
COMMENT ON COLUMN orders.images IS 'Array of image URLs for the order (min 1, max 4 images)';

-- Step 2: Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_images ON orders USING GIN (images);

-- Step 3: Storage Bucket RLS Policies
-- Note: Create the 'order_images' bucket manually in Supabase Dashboard first!
-- Make sure it's PUBLIC!

-- Drop existing policies if they exist (to avoid errors)
DROP POLICY IF EXISTS "Allow authenticated users to upload order images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public to view order images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete their order images" ON storage.objects;

-- Now create the policies
-- Allow authenticated users to upload order images
CREATE POLICY "Allow authenticated users to upload order images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'order_images');

-- Allow public to view order images (bucket must be public)
CREATE POLICY "Allow public to view order images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'order_images');

-- Allow users to delete their own order images
CREATE POLICY "Allow users to delete their order images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'order_images' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Verification Query
SELECT 
    column_name, 
    data_type, 
    column_default
FROM information_schema.columns
WHERE table_name = 'orders' AND column_name = 'images';

-- Expected Result:
-- column_name | data_type | column_default
-- images      | jsonb     | '[]'::jsonb

-- Migration completed successfully!
SELECT 'Order images migration completed! ✅' as status;
