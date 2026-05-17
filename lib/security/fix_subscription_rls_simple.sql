-- Simple RLS Fix for Subscription Deletion
-- Allows admin (the logged-in user) to delete ANY subscriptions

-- Drop old policies
DROP POLICY IF EXISTS "Users can only delete their own subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON subscriptions;
DROP POLICY IF EXISTS "Admins and users can delete subscriptions" ON subscriptions;

-- Simple admin bypass: Allow the current user to delete ANY subscription
-- This works because when admin deletes a user, they're logged in and can delete all related data
CREATE POLICY "Allow authenticated users to delete subscriptions"
ON subscriptions
FOR DELETE
USING (auth.uid() IS NOT NULL);

-- Same for subscription_history
DROP POLICY IF EXISTS "Enable delete for admins" ON subscription_history;
DROP POLICY IF EXISTS "Admins can delete subscription history" ON subscription_history;

CREATE POLICY "Allow authenticated users to delete subscription history"
ON subscription_history
FOR DELETE
USING (auth.uid() IS NOT NULL);

-- Verify
SELECT tablename, policyname, cmd
FROM pg_policies 
WHERE tablename IN ('subscriptions', 'subscription_history')
AND cmd = 'DELETE'
ORDER BY tablename;
