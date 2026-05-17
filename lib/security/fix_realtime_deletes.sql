-- Fix Realtime DELETE Events Not Broadcasting
-- This ensures DELETE events are properly broadcast via Supabase Realtime

-- Step 1: Check current realtime publication settings
-- Run this to see current configuration:
-- SELECT * FROM pg_publication WHERE pubname = 'supabase_realtime';

-- Step 2: Drop and recreate the publication with DELETE events
-- The issue is likely that DELETE events are not included in the publication

-- IMPORTANT: First, remove users table from publication
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS users;

-- Now add it back with explicit DELETE event support
-- The 'publish' parameter controls which events are broadcast
-- By default, it might only include INSERT and UPDATE
ALTER PUBLICATION supabase_realtime ADD TABLE users;

-- Step 3: Ensure the publication includes DELETE events
-- Check the publication events (should include 'delete')
-- Run this query to verify:
-- SELECT schemaname, tablename, pubname
-- FROM pg_publication_tables 
-- WHERE pubname = 'supabase_realtime' AND tablename = 'users';

-- Step 4: Alternative - Create a custom replica identity
-- This ensures Realtime knows which row was deleted
ALTER TABLE public.users REPLICA IDENTITY FULL;

-- Step 5: Verify the replica identity is set
-- Run this to check:
-- SELECT relname, relreplident 
-- FROM pg_class 
-- WHERE relname = 'users';
-- relreplident should be 'f' (FULL)

-- EXPLANATION:
-- REPLICA IDENTITY FULL means that when a row is deleted, 
-- the realtime system can see ALL column values of the deleted row,
-- not just the primary key. This is crucial for the filter to work.

-- After running this script:
-- 1. Restart your Flutter app
-- 2. Login as a test user
-- 3. Delete that user from Supabase
-- 4. The DELETE event should now be received!
