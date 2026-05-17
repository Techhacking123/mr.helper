-- SIMPLE FIX: Grant SELECT permission on users table
-- This is the most straightforward solution

-- Just grant SELECT to allow reading users table
GRANT SELECT ON users TO authenticated, anon, service_role;

-- If RLS is enabled and blocking, add a permissive SELECT policy
DO $$
BEGIN
    -- Check if RLS is enabled on users table
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'users' AND c.relrowsecurity = true
    ) THEN
        -- Drop any conflicting policy
        DROP POLICY IF EXISTS "Allow select for notifications" ON users;
        
        -- Create a SELECT policy that allows reading
        CREATE POLICY "Allow select for notifications" ON users
            FOR SELECT
            USING (true);
    END IF;
END $$;

-- Verify
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    cmd,
    qual
FROM pg_policies 
WHERE tablename = 'users' AND cmd = 'SELECT'
ORDER BY policyname;
