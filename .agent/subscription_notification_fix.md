# Subscription Notification Filter - Implementation Guide

## Issue
Unsubscribed providers are receiving notifications about service requests. Only providers with **active subscriptions** should receive these notifications.

## Current Implementation Status

### ✅ Already Implemented
1. **Subscription Fields in Database**
   - `is_subscribed` boolean column in `users` table
   - `subscription_expiry` timestamptz column in `users` table

2. **Direct Hire Notifications** (order_create.dart)
   - ✅ Already checks subscription status before sending notifications
   - Only sends notifications to subscribed providers with valid expiry dates

3. **SQL Migration Files**
   - ✅ `fix_subscription_filter.sql` - Contains the updated trigger function
   - ✅ `SUBSCRIPTION_FILTER_FIX.md` - Documentation

### ❌ Needs to be Applied
The database trigger function `notify_providers_on_order()` needs to be updated in your Supabase database to filter out unsubscribed providers.

---

## Solution: Apply Database Trigger Update

### Step 1: Verify Subscription Columns Exist

Run this SQL in Supabase SQL Editor to ensure the columns exist:

```sql
-- Check if subscription columns exist
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'users' 
AND column_name IN ('is_subscribed', 'subscription_expiry');
```

If the columns don't exist, run:

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_subscribed BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expiry TIMESTAMPTZ;
```

### Step 2: Update the Notification Trigger Function

Copy and paste this SQL into your Supabase SQL Editor and click "Run":

```sql
-- ==========================================
-- FIX: Only notify subscribed providers
-- ==========================================
-- This updates the notify_providers_on_order function
-- to only send order notifications to providers with active subscriptions

CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
  provider_record RECORD;
BEGIN
  -- Only run for open requests
  IF NEW.status = 'request_open' THEN
    -- Find matching providers (same service, same location, AND subscribed with valid expiry)
    FOR provider_record IN 
      SELECT id FROM users 
      WHERE is_provider = TRUE 
      AND service_id = NEW.service_id 
      AND is_subscribed = TRUE  -- Only notify subscribed providers
      AND (subscription_expiry IS NULL OR subscription_expiry > NOW())  -- Check subscription hasn't expired
      AND (location = (SELECT name FROM locations WHERE id = NEW.location_id) OR location IS NULL)
    LOOP
      -- Insert Notification
      INSERT INTO notifications (user_id, order_id, message, created_at)
      VALUES (provider_record.id, NEW.id, 'New service request available match!', NOW());
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The existing trigger will automatically use the updated function
-- No need to recreate the trigger
```

### Step 3: Verify the Fix

After applying the SQL, verify it's working:

```sql
-- Check the function definition
SELECT prosrc 
FROM pg_proc 
WHERE proname = 'notify_providers_on_order';
```

You should see `is_subscribed = TRUE` and the `subscription_expiry` check in the function definition.

---

## How It Works

### Before Fix
```
User places order → Trigger fires → All providers (service + location match) get notification
```

### After Fix
```
User places order → Trigger fires → Only SUBSCRIBED providers (service + location match) get notification
```

### Notification Flow

1. **Broadcast Orders** (status = 'request_open')
   - User places order without specific provider
   - Trigger `notify_providers_on_order()` fires
   - ✅ Checks: `is_provider = TRUE` AND `service_id` matches AND `is_subscribed = TRUE` AND `subscription_expiry > NOW()`
   - Only matching subscribed providers receive notifications

2. **Direct Hire** (status = 'pending')
   - User hires specific provider directly
   - `order_create.dart` manually checks subscription status
   - ✅ Already implemented - only sends notification if provider is subscribed

---

## Testing Checklist

### Test 1: Subscribed Provider Receives Notification
- [ ] Create/Update a provider: Set `is_subscribed = TRUE`, `subscription_expiry = (future date)`
- [ ] Place a broadcast order matching that provider's service and location
- [ ] ✅ Provider SHOULD receive notification

### Test 2: Unsubscribed Provider Does NOT Receive Notification 
- [ ] Create/Update a provider: Set `is_subscribed = FALSE`
- [ ] Place a broadcast order matching that provider's service and location
- [ ] ✅ Provider should NOT receive notification

### Test 3: Expired Subscription - No Notification
- [ ] Create/Update a provider: Set `is_subscribed = TRUE`, `subscription_expiry = (past date)`
- [ ] Place a broadcast order matching that provider's service and location
- [ ] ✅ Provider should NOT receive notification

### Test 4: Direct Hire - Already Working
- [ ] Hire a specific unsubscribed provider directly
- [ ] ✅ Provider should NOT receive notification (already implemented in `order_create.dart`)

---

## SQL Debugging Queries

### Check Provider Subscription Status
```sql
SELECT 
  id, 
  full_name, 
  is_provider,
  is_subscribed, 
  subscription_expiry,
  CASE 
    WHEN is_subscribed = TRUE AND (subscription_expiry IS NULL OR subscription_expiry > NOW()) 
    THEN 'ACTIVE'
    ELSE 'INACTIVE'
  END as subscription_status
FROM users 
WHERE is_provider = TRUE;
```

### Check Recent Notifications
```sql
SELECT 
  n.id,
  n.user_id,
  u.full_name as provider_name,
  u.is_subscribed,
  u.subscription_expiry,
  n.message,
  n.created_at
FROM notifications n
JOIN users u ON n.user_id = u.id
WHERE n.created_at > NOW() - INTERVAL '1 hour'
ORDER BY n.created_at DESC;
```

### Manually Test Trigger Logic
```sql
-- Check which providers would be notified for a specific service and location
SELECT 
  id, 
  full_name,
  is_subscribed,
  subscription_expiry,
  service_id,
  location
FROM users 
WHERE is_provider = TRUE 
AND service_id = 'YOUR_SERVICE_ID_HERE'
AND is_subscribed = TRUE
AND (subscription_expiry IS NULL OR subscription_expiry > NOW())
AND location = 'YOUR_LOCATION_NAME_HERE';
```

---

## Related Files

- `lib/security/fix_subscription_filter.sql` - SQL migration file
- `lib/security/SUBSCRIPTION_FILTER_FIX.md` - Original documentation
- `lib/orders/order_create.dart` - Direct hire with subscription check
- `lib/orders/provider_requests.dart` - Provider view of requests
- `lib/subscription/subscription_page.dart` - Subscription UI

---

## Summary

**What needs to be done:**
1. ✅ Verify subscription columns exist in database
2. ✅ Run the SQL to update `notify_providers_on_order()` function
3. ✅ Test with subscribed and unsubscribed providers

**Expected Result:**
- Only providers with:
  - `is_subscribed = TRUE` 
  - AND `subscription_expiry > NOW()` (or NULL)
  - AND matching service + location
  
  Will receive notifications for broadcast orders.
