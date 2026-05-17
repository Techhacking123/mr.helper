-- Add image_url column to services table
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Create a new storage bucket for services
INSERT INTO storage.buckets (id, name, public) VALUES ('services', 'services', true)
ON CONFLICT (id) DO NOTHING;

-- Set up RLS policies for the services bucket
-- Use unique names to avoid conflicts with other buckets

-- Allow public access to view images
CREATE POLICY "Public Access Services"
ON storage.objects FOR SELECT
USING ( bucket_id = 'services' );

-- Allow authenticated users to upload
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
