-- OPTION 1: Make services bucket publicly writable
-- This allows uploads without authentication
-- Use this if you want a quick fix for admin uploads

-- Create policy to allow public (anon) uploads
CREATE POLICY "Public Upload Services"
ON storage.objects FOR INSERT
TO anon
WITH CHECK ( bucket_id = 'services' );

-- Also allow public to read
CREATE POLICY "Public Read Services"
ON storage.objects FOR SELECT
TO anon
USING ( bucket_id = 'services' );

-- Allow public updates
CREATE POLICY "Public Update Services"
ON storage.objects FOR UPDATE
TO anon
USING ( bucket_id = 'services' );

-- Allow public deletes
CREATE POLICY "Public Delete Services"
ON storage.objects FOR DELETE
TO anon
USING ( bucket_id = 'services' );
