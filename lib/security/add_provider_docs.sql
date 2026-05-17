-- Add columns for provider documents to the users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS aadhar_card_url TEXT,
ADD COLUMN IF NOT EXISTS pan_card_url TEXT;

-- Create a storage bucket for provider documents if it doesn't exist
-- Note: Creating buckets usually requires using the Storage API or dashboard, 
-- but we can insert into storage.buckets if permissions allow.
-- For safety, we will assume standard 'documents' or 'provider_docs' bucket 
-- needs to be created via dashboard, but we can try to set policies.

-- Set up RLS policies for the documents (assuming a 'provider_docs' bucket)
-- Allow authenticated users to upload their own documents
create policy "Users can upload their own provider docs"
on storage.objects for insert
with check ( bucket_id = 'provider_docs' AND auth.uid() = owner );

-- Allow users to view their own documents
create policy "Users can view their own provider docs"
on storage.objects for select
using ( bucket_id = 'provider_docs' AND auth.uid() = owner );
