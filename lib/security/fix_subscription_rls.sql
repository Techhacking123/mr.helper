-- Fix Subscription Deletion RLS Policy for Admin
-- This allows admins to delete subscriptions when deleting users

-- Grant admin permission to delete subscriptions
-- Check current policies
-- SELECT * FROM pg_policies WHERE tablename = 'subscriptions';

-- Drop any restrictive delete policies
DROP POLICY IF EXISTS "Users can only delete their own subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON subscriptions;

-- Create admin-friendly delete policy
CREATE POLICY "Admins and users can delete subscriptions"
ON subscriptions
FOR DELETE
USING (
  -- Allow if user is deleting their own subscription
  auth.uid() = user_id
  OR
  -- Allow if user is an admin (check if username is 'adime' or is_admin flag)
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND (users.username = 'adime' OR users.is_admin = true)
  )
);

-- Also ensure INSERT and UPDATE policies exist for subscriptions
CREATE POLICY IF NOT EXISTS "Users can insert their own subscriptions"
ON subscriptions
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users and admins can update subscriptions"
ON subscriptions
FOR UPDATE
USING (
  auth.uid() = user_id
  OR
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND (users.username = 'adime' OR users.is_admin = true)
  )
);

-- Grant admin permission to delete from subscription_history as well
DROP POLICY IF EXISTS "Enable delete for admins" ON subscription_history;

CREATE POLICY "Admins can delete subscription history"
ON subscription_history
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND (users.username = 'adime' OR users.is_admin = true)
  )
);

-- Verify policies were created
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies 
WHERE tablename IN ('subscriptions', 'subscription_history')
ORDER BY tablename, policyname;
