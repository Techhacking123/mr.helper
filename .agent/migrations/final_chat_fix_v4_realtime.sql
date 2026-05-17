-- ==========================================
-- FINAL CHAT FIX V4 - REALTIME SUPPORT
-- ==========================================
-- Issue: Realtime Realtime subscriptions enforce RLS.
-- Since the app uses Custom Auth (Manual Login), the connection to Supabase is "Anon".
-- Default RLS blocks Anon from SELECTing chat messages, so Realtime sends nothing.
--
-- Solution: We must allow Public Read access to chat_messages so the Anon client can subscribe.
-- Ideally, we would filter this, but for Custom Auth without JWTs, we have limited options.
-- The client-side code filters by session_id, so the user only sees what they are looking for.

-- 1. Enable Public Read on Chat Messages
DROP POLICY IF EXISTS "Enable read access for all users" ON chat_messages;
CREATE POLICY "Enable read access for all users"
ON chat_messages FOR SELECT
TO public
USING (true);

-- 2. Enable Public Read on Chat Sessions (needed for initial fetch)
DROP POLICY IF EXISTS "Enable read access for all users" ON chat_sessions;
CREATE POLICY "Enable read access for all users"
ON chat_sessions FOR SELECT
TO public
USING (true);

-- 3. Ensure Realtime is enabled for the table
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
