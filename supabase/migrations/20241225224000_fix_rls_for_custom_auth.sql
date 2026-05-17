-- RELAX RLS FOR CUSTOM AUTH
-- Since the app uses manual query-based auth instead of Supabase Auth,
-- auth.uid() is null, causing updates to fail.

-- 1. Drop the strict policy
DROP POLICY IF EXISTS "Update Own Profile" ON users;

-- 2. Create a permissive policy (allows checking by ID in WHERE clause instead of RLS)
-- Ideally, the app should use Supabase Auth to be secure.
-- For now, we trust the Client to only update its own row.
CREATE POLICY "Allow Public Update Users" 
ON users 
FOR UPDATE 
USING (true)
WITH CHECK (true);

-- 3. Ensure Insert is also allowed (if not already)
DROP POLICY IF EXISTS "Public Insert Users" ON users;
CREATE POLICY "Public Insert Users" ON users FOR INSERT WITH CHECK (true);
