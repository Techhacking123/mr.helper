-- DEBUG: Allow PUBLIC (anon) uploads to 'services' bucket
-- This is to rule out authentication issues. If this works, the issue is with the user session.

-- 1. Ensure bucket exists
INSERT INTO storage.buckets (id, name, public) 
VALUES ('services', 'services', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Drop existing insert policies for this bucket
DROP POLICY IF EXISTS "Authenticated Insert Services" ON storage.objects;
DROP POLICY IF EXISTS "Public Insert Services" ON storage.objects;

-- 3. Create a PUBLIC insert policy
CREATE POLICY "Public Insert Services"
ON storage.objects FOR INSERT
TO public
WITH CHECK ( bucket_id = 'services' );

-- 4. Ensure Public Read (should already be there, but ensuring)
DROP POLICY IF EXISTS "Public Read Services" ON storage.objects;
CREATE POLICY "Public Read Services"
ON storage.objects FOR SELECT
TO public
USING ( bucket_id = 'services' );
