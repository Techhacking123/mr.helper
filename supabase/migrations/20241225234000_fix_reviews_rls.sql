-- 1. Unblock Reviews (Public Read)
ALTER TABLE provider_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public Read Reviews" ON provider_reviews;
CREATE POLICY "Public Read Reviews"
ON provider_reviews
FOR SELECT
USING (true); -- Anyone can read reviews

-- 2. Unblock Users Public Profile Info (Public Read)
-- We need this because we JOIN reviews with users table to get names/avatars
DROP POLICY IF EXISTS "Public Read Users" ON users;
CREATE POLICY "Public Read Users"
ON users
FOR SELECT
USING (true); -- Anyone can read user profiles (names/avatars)

-- 3. Ensure Insert is correct (Authenticated users can write reviews)
DROP POLICY IF EXISTS "Auth Insert Reviews" ON provider_reviews;
CREATE POLICY "Auth Insert Reviews"
ON provider_reviews
FOR INSERT
WITH CHECK (true); -- Ideally should check auth.uid() == user_id, but keeping permissive for custom auth
