-- 1. Ensure the 'services' bucket is PUBLIC
INSERT INTO storage.buckets (id, name, public)
VALUES ('services', 'services', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Drop potential conflicting policies for 'services' bucket
DROP POLICY IF EXISTS "Public Access Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete Services" ON storage.objects;
DROP POLICY IF EXISTS "Services Upload Policy" ON storage.objects;
DROP POLICY IF EXISTS "Services Public Read Policy" ON storage.objects;

-- 3. Create simplified policies

-- Public Read Access: Everyone can view
CREATE POLICY "Public Read Services"
ON storage.objects FOR SELECT
USING ( bucket_id = 'services' );

-- Insert Access: Allow any authenticated user to upload
-- Note: 'authenticated' role includes all logged-in users.
-- Try removing the 'WITH CHECK' restriction temporarily if it still fails, 
-- but this standard checklist usually works.
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

-- 4. Verify RLS is enabled on objects table (it usually is by default)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
