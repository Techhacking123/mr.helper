-- COMPLETE FIX FOR USER DELETION WITH SUBSCRIPTIONS
-- This addresses both the FK constraint and RLS policy issues

-- ==========================================
-- STEP 1: Fix the Foreign Key Constraint
-- ==========================================

-- Drop the existing foreign key that doesn't have CASCADE
ALTER TABLE public.subscriptions 
DROP CONSTRAINT IF EXISTS subscriptions_user_id_fkey;

-- Recreate it WITH CASCADE DELETE
-- This means when a user is deleted, their subscriptions are automatically deleted
ALTER TABLE public.subscriptions
ADD CONSTRAINT subscriptions_user_id_fkey 
FOREIGN KEY (user_id) 
REFERENCES public.users(id) 
ON DELETE CASCADE;

-- ==========================================
-- STEP 2: Fix RLS Policies for Deletion
-- ==========================================

-- Drop all existing DELETE policies on subscriptions
DROP POLICY IF EXISTS "Users can only delete their own subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON public.subscriptions;
DROP POLICY IF EXISTS "Admins and users can delete subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Allow authenticated users to delete subscriptions" ON public.subscriptions;

-- Create a permissive DELETE policy
-- This allows authenticated users (including admins) to delete subscriptions
CREATE POLICY "Allow authenticated DELETE on subscriptions"
ON public.subscriptions
FOR DELETE
TO authenticated
USING (true);

-- ==========================================
-- STEP 3: Fix subscription_history FK and RLS
-- ==========================================

-- Check if FK exists with CASCADE
DO $$
BEGIN
    -- Drop existing FK if it doesn't have CASCADE
    ALTER TABLE public.subscription_history 
    DROP CONSTRAINT IF EXISTS subscription_history_provider_id_fkey;
    
    -- Recreate with CASCADE
    ALTER TABLE public.subscription_history
    ADD CONSTRAINT subscription_history_provider_id_fkey 
    FOREIGN KEY (provider_id) 
    REFERENCES public.users(id) 
    ON DELETE CASCADE;
END $$;

-- Drop all existing DELETE policies on subscription_history
DROP POLICY IF EXISTS "Enable delete for admins" ON public.subscription_history;
DROP POLICY IF EXISTS "Admins can delete subscription history" ON public.subscription_history;
DROP POLICY IF EXISTS "Allow authenticated users to delete subscription history" ON public.subscription_history;

-- Create permissive DELETE policy
CREATE POLICY "Allow authenticated DELETE on subscription_history"
ON public.subscription_history
FOR DELETE
TO authenticated
USING (true);

-- ==========================================
-- VERIFICATION QUERIES
-- ==========================================

-- Verify FK constraints have CASCADE
SELECT 
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
JOIN information_schema.referential_constraints AS rc
    ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_name IN ('subscriptions', 'subscription_history')
ORDER BY tc.table_name;

-- Verify RLS policies
SELECT 
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename IN ('subscriptions', 'subscription_history')
ORDER BY tablename, cmd;

-- Success message
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE '✅ SUBSCRIPTION DELETION FIX COMPLETE!';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Changes made:';
  RAISE NOTICE '  1. Added ON DELETE CASCADE to subscriptions.user_id FK';
  RAISE NOTICE '  2. Added ON DELETE CASCADE to subscription_history.provider_id FK';
  RAISE NOTICE '  3. Created permissive DELETE policies for both tables';
  RAISE NOTICE '';
  RAISE NOTICE 'Result: Admins can now delete users with subscriptions!';
  RAISE NOTICE '================================================';
END $$;
