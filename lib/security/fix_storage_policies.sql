-- Enable the pg_net extension if it's not already enabled (usually good for Supabase)
-- CREATE EXTENSION IF NOT EXISTS "pg_net";

-- 1. Ensure the 'services' bucket exists and is set to PUBLIC
INSERT INTO storage.buckets (id, name, public)
VALUES ('services', 'services', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Drop potential conflicting policies specific to 'services' bucket
-- We use unique names so we can safely manage them.
DROP POLICY IF EXISTS "Public Access Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Insert Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Update Services" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Delete Services" ON storage.objects;

-- 3. Create policies for the 'services' bucket

-- Public Read Access: Anyone can view images in the 'services' bucket
CREATE POLICY "Public Access Services"
ON storage.objects FOR SELECT
USING ( bucket_id = 'services' );

-- Authenticated Insert: Logged-in users (Admins/Providers) can upload
CREATE POLICY "Authenticated Insert Services"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'services' );

-- Authenticated Update: Logged-in users can update (replace) images
CREATE POLICY "Authenticated Update Services"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'services' );

-- Authenticated Delete: Logged-in users can delete images
CREATE POLICY "Authenticated Delete Services"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'services' );

-- 4. Ensure the services table has the image_url column
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS image_url TEXT;
