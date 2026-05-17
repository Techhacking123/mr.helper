-- Fix RLS policies for 'services' bucket

-- 1. Ensure the bucket exists and is public
INSERT INTO storage.buckets (id, name, public) 
VALUES ('services', 'services', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Public Access Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete Services" ON storage.objects;
DROP POLICY IF EXISTS "Public Insert Services" ON storage.objects;
DROP POLICY IF EXISTS "Public Read Services" ON storage.objects;

-- 3. Create permissive policies for 'services' bucket

-- Allow public read access
CREATE POLICY "Public Read Services"
ON storage.objects FOR SELECT
TO public
USING ( bucket_id = 'services' );

-- Allow authenticated users to upload (INSERT)
CREATE POLICY "Authenticated Insert Services"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'services' );

-- Allow authenticated users to update
CREATE POLICY "Authenticated Update Services"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'services' );

-- Allow authenticated users to delete
CREATE POLICY "Authenticated Delete Services"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'services' );

-- 4. Enable RLS on storage.objects (just in case it was disabled)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
