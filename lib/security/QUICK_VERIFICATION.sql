-- ==========================================
-- QUICK VERIFICATION SCRIPT
-- ==========================================
-- Copy and run this entire script in Supabase SQL Editor
-- to get an instant status report of your subscription system
-- ==========================================

-- Clear any previous notices
DO $$ BEGIN
  RAISE NOTICE '================================================';
  RAISE NOTICE 'SUBSCRIPTION SYSTEM VERIFICATION REPORT';
  RAISE NOTICE '================================================';
END $$;

-- ==========================================
-- CHECK 1: Subscription Columns Exist
-- ==========================================
DO $$
DECLARE
  col_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO col_count
  FROM information_schema.columns 
  WHERE table_name = 'users' 
  AND column_name IN ('is_subscribed', 'subscription_expiry');
  
  RAISE NOTICE '';
  RAISE NOTICE '1. SUBSCRIPTION COLUMNS CHECK';
  RAISE NOTICE '   Expected: 2 columns (is_subscribed, subscription_expiry)';
  RAISE NOTICE '   Found: % columns', col_count;
  
  IF col_count = 2 THEN
    RAISE NOTICE '   Status: ✅ PASS';
  ELSE
    RAISE NOTICE '   Status: ❌ FAIL - Run FIX_NOTIFICATIONS_SIMPLE.sql';
  END IF;
END $$;

-- ==========================================
-- CHECK 2: Notification Trigger Exists and Has Subscription Check
-- ==========================================
DO $$
DECLARE
  trigger_exists BOOLEAN;
  has_subscription_check BOOLEAN;
  function_code TEXT;
BEGIN
  -- Check if function exists
  SELECT EXISTS(
    SELECT 1 FROM pg_proc WHERE proname = 'notify_providers_on_order'
  ) INTO trigger_exists;
  
  -- Check if function has subscription logic
  IF trigger_exists THEN
    SELECT prosrc INTO function_code
    FROM pg_proc 
    WHERE proname = 'notify_providers_on_order';
    
    has_subscription_check := function_code LIKE '%is_subscribed%';
  ELSE
    has_subscription_check := FALSE;
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '2. NOTIFICATION TRIGGER CHECK';
  RAISE NOTICE '   Trigger exists: %', trigger_exists;
  RAISE NOTICE '   Has subscription check: %', has_subscription_check;
  
  IF trigger_exists AND has_subscription_check THEN
    RAISE NOTICE '   Status: ✅ PASS';
  ELSIF trigger_exists AND NOT has_subscription_check THEN
    RAISE NOTICE '   Status: ❌ FAIL - Trigger exists but NO subscription check';
    RAISE NOTICE '   Action: Run FIX_NOTIFICATIONS_SIMPLE.sql to update trigger';
  ELSE
    RAISE NOTICE '   Status: ❌ FAIL - Trigger does not exist';
    RAISE NOTICE '   Action: Run FIX_NOTIFICATIONS_SIMPLE.sql to create trigger';
  END IF;
END $$;

-- ==========================================
-- CHECK 3: Provider Subscription Status
-- ==========================================
DO $$
DECLARE
  total_providers INTEGER;
  active_providers INTEGER;
  unsubscribed_providers INTEGER;
  expired_providers INTEGER;
BEGIN
  -- Count providers by subscription status
  SELECT 
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE is_subscribed = TRUE AND (subscription_expiry IS NULL OR subscription_expiry > NOW())) as active,
    COUNT(*) FILTER (WHERE is_subscribed = FALSE OR subscription_expiry IS NULL) as unsubscribed,
    COUNT(*) FILTER (WHERE is_subscribed = TRUE AND subscription_expiry <= NOW()) as expired
  INTO total_providers, active_providers, unsubscribed_providers, expired_providers
  FROM users 
  WHERE is_provider = TRUE;
  
  RAISE NOTICE '';
  RAISE NOTICE '3. PROVIDER SUBSCRIPTION STATUS';
  RAISE NOTICE '   Total providers: %', total_providers;
  RAISE NOTICE '   ✅ Active subscriptions: %', active_providers;
  RAISE NOTICE '   ❌ Unsubscribed: %', unsubscribed_providers;
  RAISE NOTICE '   ⏰ Expired: %', expired_providers;
  
  IF active_providers > 0 THEN
    RAISE NOTICE '   Status: ✅ PASS - Some providers are subscribed';
  ELSE
    RAISE NOTICE '   Status: ⚠️  WARNING - No active subscriptions';
    RAISE NOTICE '   Note: This is OK for testing, activate a provider to test';
  END IF;
END $$;

-- ==========================================
-- CHECK 4: Recent Notification Leakage (Last 24 Hours)
-- ==========================================
DO $$
DECLARE
  notified_active INTEGER;
  notified_inactive INTEGER;
  total_notifications INTEGER;
BEGIN
  -- Check if any notifications went to unsubscribed providers
  SELECT 
    COUNT(*) FILTER (WHERE u.is_subscribed = TRUE AND (u.subscription_expiry IS NULL OR u.subscription_expiry > NOW())) as active,
    COUNT(*) FILTER (WHERE u.is_subscribed = FALSE OR (u.is_subscribed = TRUE AND u.subscription_expiry <= NOW()) OR u.subscription_expiry IS NULL) as inactive,
    COUNT(*) as total
  INTO notified_active, notified_inactive, total_notifications
  FROM notifications n
  JOIN users u ON n.user_id = u.id
  WHERE n.created_at > NOW() - INTERVAL '24 hours'
    AND u.is_provider = TRUE;
  
  RAISE NOTICE '';
  RAISE NOTICE '4. NOTIFICATION LEAKAGE CHECK (Last 24 Hours)';
  RAISE NOTICE '   Total notifications to providers: %', total_notifications;
  RAISE NOTICE '   ✅ To active subscribers: %', notified_active;
  RAISE NOTICE '   ❌ To inactive/unsubscribed: %', notified_inactive;
  
  IF total_notifications = 0 THEN
    RAISE NOTICE '   Status: ⚠️  No notifications in last 24h (cannot verify)';
  ELSIF notified_inactive = 0 THEN
    RAISE NOTICE '   Status: ✅ PASS - No leakage detected';
  ELSE
    RAISE NOTICE '   Status: ❌ FAIL - Unsubscribed providers received % notifications!', notified_inactive;
    RAISE NOTICE '   Action: Database trigger likely not updated. Run FIX_NOTIFICATIONS_SIMPLE.sql';
  END IF;
END $$;

-- ==========================================
-- CHECK 5: Sample Active Providers
-- ==========================================
DO $$
DECLARE
  provider_name TEXT;
  expiry_date TIMESTAMPTZ;
  rec RECORD;
  count INTEGER := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '5. SAMPLE ACTIVE PROVIDERS (Max 5)';
  
  FOR rec IN 
    SELECT full_name, subscription_expiry, service_id
    FROM users
    WHERE is_provider = TRUE
      AND is_subscribed = TRUE
      AND (subscription_expiry IS NULL OR subscription_expiry > NOW())
    LIMIT 5
  LOOP
    count := count + 1;
    IF rec.subscription_expiry IS NOT NULL THEN
      RAISE NOTICE '   % - % (expires: %)', count, rec.full_name, rec.subscription_expiry;
    ELSE
      RAISE NOTICE '   % - % (no expiry set)', count, rec.full_name;
    END IF;
  END LOOP;
  
  IF count = 0 THEN
    RAISE NOTICE '   (No active providers found)';
  END IF;
END $$;

-- ==========================================
-- CHECK 6: Sample Inactive Providers
-- ==========================================
DO $$
DECLARE
  rec RECORD;
  count INTEGER := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '6. SAMPLE INACTIVE PROVIDERS (Max 5)';
  
  FOR rec IN 
    SELECT 
      full_name, 
      is_subscribed,
      subscription_expiry,
      CASE
        WHEN is_subscribed = FALSE OR is_subscribed IS NULL THEN 'Not Subscribed'
        WHEN subscription_expiry <= NOW() THEN 'Expired'
        ELSE 'Unknown'
      END as reason
    FROM users
    WHERE is_provider = TRUE
      AND (is_subscribed = FALSE 
           OR is_subscribed IS NULL 
           OR (is_subscribed = TRUE AND subscription_expiry <= NOW()))
    LIMIT 5
  LOOP
    count := count + 1;
    RAISE NOTICE '   % - % (Reason: %)', count, rec.full_name, rec.reason;
  END LOOP;
  
  IF count = 0 THEN
    RAISE NOTICE '   (No inactive providers found)';
  END IF;
END $$;

-- ==========================================
-- FINAL SUMMARY
-- ==========================================
DO $$
DECLARE
  columns_ok BOOLEAN;
  trigger_ok BOOLEAN;
  no_leakage BOOLEAN;
  has_active BOOLEAN;
  
  col_count INTEGER;
  trigger_exists BOOLEAN;
  has_check BOOLEAN;
  function_code TEXT;
  leaked INTEGER;
  active_count INTEGER;
  
  overall_status TEXT;
BEGIN
  -- Re-check all conditions
  
  -- Columns
  SELECT COUNT(*) INTO col_count
  FROM information_schema.columns 
  WHERE table_name = 'users' 
  AND column_name IN ('is_subscribed', 'subscription_expiry');
  columns_ok := (col_count = 2);
  
  -- Trigger
  SELECT EXISTS(
    SELECT 1 FROM pg_proc WHERE proname = 'notify_providers_on_order'
  ) INTO trigger_exists;
  
  IF trigger_exists THEN
    SELECT prosrc INTO function_code
    FROM pg_proc 
    WHERE proname = 'notify_providers_on_order';
    has_check := function_code LIKE '%is_subscribed%';
  ELSE
    has_check := FALSE;
  END IF;
  trigger_ok := (trigger_exists AND has_check);
  
  -- Leakage
  SELECT COUNT(*) INTO leaked
  FROM notifications n
  JOIN users u ON n.user_id = u.id
  WHERE n.created_at > NOW() - INTERVAL '24 hours'
    AND u.is_provider = TRUE
    AND (u.is_subscribed = FALSE 
         OR (u.is_subscribed = TRUE AND u.subscription_expiry <= NOW()) 
         OR u.subscription_expiry IS NULL);
  no_leakage := (leaked = 0);
  
  -- Active providers
  SELECT COUNT(*) INTO active_count
  FROM users
  WHERE is_provider = TRUE
    AND is_subscribed = TRUE
    AND (subscription_expiry IS NULL OR subscription_expiry > NOW());
  has_active := (active_count > 0);
  
  -- Determine overall status
  IF columns_ok AND trigger_ok AND no_leakage THEN
    overall_status := '✅ SYSTEM HEALTHY';
  ELSIF NOT columns_ok OR NOT trigger_ok THEN
    overall_status := '❌ CRITICAL ISSUES - Action Required';
  ELSIF NOT no_leakage THEN
    overall_status := '⚠️  WARNING - Possible Leakage';
  ELSE
    overall_status := '⚠️  CHECK REQUIRED';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '================================================';
  RAISE NOTICE 'OVERALL STATUS: %', overall_status;
  RAISE NOTICE '================================================';
  RAISE NOTICE '';
  
  IF NOT columns_ok THEN
    RAISE NOTICE '🔥 CRITICAL: Subscription columns missing';
    RAISE NOTICE '   → Run FIX_NOTIFICATIONS_SIMPLE.sql immediately';
    RAISE NOTICE '';
  END IF;
  
  IF NOT trigger_ok THEN
    RAISE NOTICE '🔥 CRITICAL: Notification trigger not properly configured';
    RAISE NOTICE '   → Run FIX_NOTIFICATIONS_SIMPLE.sql immediately';
    RAISE NOTICE '';
  END IF;
  
  IF NOT no_leakage THEN
    RAISE NOTICE '⚠️  WARNING: % notifications sent to unsubscribed providers', leaked;
    RAISE NOTICE '   → Database trigger may not be updated';
    RAISE NOTICE '   → Run FIX_NOTIFICATIONS_SIMPLE.sql';
    RAISE NOTICE '';
  END IF;
  
  IF NOT has_active THEN
    RAISE NOTICE 'ℹ️  INFO: No active subscriptions';
    RAISE NOTICE '   → This is OK for testing';
    RAISE NOTICE '   → Activate a provider to test workflows';
    RAISE NOTICE '';
  END IF;
  
  IF columns_ok AND trigger_ok AND no_leakage THEN
    RAISE NOTICE '✅ All checks passed!';
    RAISE NOTICE '✅ System is working correctly';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Test workflows in WORKFLOW_VERIFICATION_CHECKLIST.md';
    RAISE NOTICE '  2. Verify Flutter app behavior';
    RAISE NOTICE '  3. Monitor notifications in production';
  END IF;
  
  RAISE NOTICE '================================================';
END $$;

-- Show detailed provider list for manual review
SELECT 
  id,
  full_name,
  is_provider,
  is_subscribed,
  subscription_expiry,
  CASE 
    WHEN is_provider = FALSE THEN 'Not Provider'
    WHEN is_subscribed = TRUE AND (subscription_expiry IS NULL OR subscription_expiry > NOW())
    THEN '✅ ACTIVE'
    WHEN is_subscribed = FALSE OR subscription_expiry IS NULL
    THEN '❌ UNSUBSCRIBED'
    WHEN subscription_expiry <= NOW()
    THEN '⏰ EXPIRED'
    ELSE '❓ UNKNOWN'
  END as status,
  CASE
    WHEN subscription_expiry IS NOT NULL AND subscription_expiry > NOW()
    THEN EXTRACT(DAY FROM (subscription_expiry - NOW())) || ' days remaining'
    WHEN subscription_expiry IS NOT NULL AND subscription_expiry <= NOW()
    THEN 'Expired ' || EXTRACT(DAY FROM (NOW() - subscription_expiry)) || ' days ago'
    ELSE 'No expiry set'
  END as expiry_info
FROM users
WHERE is_provider = TRUE
ORDER BY 
  is_subscribed DESC, 
  subscription_expiry DESC NULLS LAST
LIMIT 20;
