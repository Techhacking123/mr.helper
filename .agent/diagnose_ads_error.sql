-- ==========================================
-- DIAGNOSTIC: ADS UPLOAD ERROR ROOT CAUSE
-- ==========================================
-- Run this to understand WHY the 403 error is happening
-- ==========================================

-- 1. Check if ads table exists
SELECT '=== ADS TABLE EXISTS? ===' as check_name;
SELECT 
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'ads';

-- 2. Check all RLS policies on ads table
SELECT '=== ADS TABLE POLICIES ===' as check_name;
SELECT 
  policyname,
  cmd,
  roles::text,
  permissive,
  CASE 
    WHEN qual IS NOT NULL THEN substring(qual::text, 1, 100)
    ELSE 'No USING clause'
  END as using_clause,
  CASE 
    WHEN with_check IS NOT NULL THEN substring(with_check::text, 1, 100)
    ELSE 'No WITH CHECK clause'
  END as with_check_clause
FROM pg_policies 
WHERE tablename = 'ads'
AND schemaname = 'public';

-- 3. Check storage bucket policies
SELECT '=== STORAGE BUCKET POLICIES ===' as check_name;
SELECT 
  policyname,
  cmd,
  roles::text
FROM pg_policies 
WHERE tablename = 'objects' 
AND schemaname = 'storage'
AND policyname LIKE '%ads%';

-- 4. Test if the table allows INSERT with current role
SELECT '=== TEST INSERT SIMULATION ===' as check_name;
-- This will show what policies would apply
SELECT 
  policyname,
  cmd,
  roles::text as allowed_roles
FROM pg_policies 
WHERE tablename = 'ads'
AND cmd = 'INSERT'
AND schemaname = 'public';

-- 5. Check what the default role grant is
SELECT '=== TABLE GRANTS ===' as check_name;
SELECT 
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
AND table_name = 'ads';

-- 6. Show table structure
SELECT '=== ADS TABLE STRUCTURE ===' as check_name;
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'ads'
ORDER BY ordinal_position;

-- Summary and Recommendations
DO $$ 
BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE 'DIAGNOSTIC COMPLETE';
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Look for these issues:';
  RAISE NOTICE '1. RLS enabled = true on ads table?';
  RAISE NOTICE '2. Policy for INSERT exists for public/anon role?';
  RAISE NOTICE '3. WITH CHECK clause allows the insert?';
  RAISE NOTICE '';
  RAISE NOTICE 'If no INSERT policy for anon/public role exists:';
  RAISE NOTICE '  -> Run fix_ads_table_rls.sql';
  RAISE NOTICE '';
  RAISE NOTICE 'If policies exist but still failing:';
  RAISE NOTICE '  -> The app may be using service_role key';
  RAISE NOTICE '  -> Or there is a WITH CHECK condition failing';
  RAISE NOTICE '================================================';
END $$;
