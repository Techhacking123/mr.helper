-- 1. Ensure the 'services' bucket is PUBLIC
INSERT INTO storage.buckets (id, name, public)
VALUES ('services', 'services', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Drop potential conflicting policies for 'services' bucket (Safe drops)
-- We only try to drop the ones we likely created or standard ones.
DROP POLICY IF EXISTS "Public Read Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete Services" ON storage.objects;

-- 3. Create policies
-- Note: schema 'storage' is system managed, but creating policies is allowed.

-- Public Read Access: Everyone can view
CREATE POLICY "Public Read Services"
ON storage.objects FOR SELECT
USING ( bucket_id = 'services' );

-- Insert Access: Allow any authenticated user to upload
CREATE POLICY "Authenticated Insert Services"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'services' );

-- Update Access
CREATE POLICY "Authenticated Update Services"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'services' );

-- Delete Access
CREATE POLICY "Authenticated Delete Services"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'services' );

-- Removed the ALTER TABLE command which caused the permission error.
-- RLS is enabled by default on storage.objects.
