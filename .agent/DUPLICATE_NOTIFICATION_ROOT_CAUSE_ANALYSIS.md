# Root Cause Analysis: Duplicate Push Notifications

**Date:** December 30, 2025  
**Issue:** Providers and users receiving the same push notification twice

---

## 🔴 CRITICAL ISSUE FOUND

### **Dual Notification System**

Your application has **TWO independent systems** creating notifications for the **SAME event**, causing duplicates.

---

## 📍 Source #1: Flutter App Manual Insert

**File:** `lib/orders/order_create.dart`  
**Lines:** 133-148

```dart
if (isActive) {
  // Only send notification if provider has ACTIVE subscription
  await SupabaseConfig.supabase.from('notifications').insert({
    'user_id': widget.providerId,
    'order_id': orderId,
    'message': 'You have received a new order from a user.',
    'is_read': false,
  });
  debugPrint('✅ Notification sent to subscribed provider: ${widget.providerId}');
}
```

**What happens:**
- User creates an order
- Flutter app **directly inserts** a notification row
- **Trigger on notifications table** fires → Calls Edge Function → Sends FCM push (**1st notification**)

---

## 📍 Source #2: Database Trigger on Orders Table

**File:** `supabase/migrations/20241225221002_fix_provider_matching.sql`  
**Lines:** 43-47

```sql
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
CREATE TRIGGER on_new_order_notify
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_providers_on_order();
```

**Function:** `notify_providers_on_order()` (Lines 4-40)
```sql
-- Find matching providers (RELAXED CHECK)
FOR provider_record IN 
  SELECT id FROM users 
  WHERE is_provider = TRUE 
  AND service_id = NEW.service_id 
  -- ... subscription checks ...
LOOP
  -- Insert Notification
  INSERT INTO notifications (user_id, order_id, message, created_at)
  VALUES (provider_record.id, NEW.id, 'New Service Request: ...', NOW());
END LOOP;
```

**What happens:**
- Same order creation event
- Database trigger **automatically inserts** notification row(s) for matching providers
- **Trigger on notifications table** fires → Calls Edge Function → Sends FCM push (**2nd notification**)

---

## 🔥 The Complete Flow (Current - BROKEN)

```
User creates order in order_create.dart
         ↓
    INSERT into 'orders' table
         ↓
         ├─→ [Path A: Database Trigger]
         │      ↓
         │   notify_providers_on_order() executes
         │      ↓
         │   INSERT into 'notifications' table
         │      ↓
         │   trigger_send_fcm_notification fires
         │      ↓
         │   Edge Function sends FCM → NOTIFICATION #1
         │
         └─→ [Path B: Flutter Code - order_create.dart]
                ↓
             Manual INSERT into 'notifications' table
                ↓
             trigger_send_fcm_notification fires
                ↓
             Edge Function sends FCM → NOTIFICATION #2

RESULT: 2 IDENTICAL NOTIFICATIONS!
```

---

## 🛠️ SOLUTION OPTIONS

### **Option 1: Remove Flutter Manual Insert (RECOMMENDED)**

**Pros:**
- Single source of truth (database)
- Subscription logic centralized in database
- Easier to maintain and debug
- Automatic for all order creation paths

**Cons:**
- None (this is the correct architecture)

**Implementation:**
Delete lines 109-148 from `lib/orders/order_create.dart`

---

### **Option 2: Remove Database Trigger**

**Pros:**
- Application-level control
- Easier to customize per scenario

**Cons:**
- Must manually insert notification for EVERY order creation path
- Easy to forget in new features
- Duplication of subscription check logic

**Implementation:**
```sql
DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
DROP FUNCTION IF EXISTS notify_providers_on_order();
```

---

## ✅ RECOMMENDED FIX (Option 1)

### Step 1: Update order_create.dart

Remove the manual notification insert. The database trigger will handle it automatically.

### Step 2: Verify Database Trigger

Ensure only ONE trigger exists on the orders table:
```sql
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE event_object_table = 'orders';
```

Should show:
```
trigger_name              | event_manipulation | event_object_table
--------------------------+-------------------+-------------------
on_new_order_notify       | INSERT            | orders
```

### Step 3: Verify Notifications Trigger

```sql
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE event_object_table = 'notifications';
```

Should show:
```
trigger_name                     | event_manipulation | event_object_table
---------------------------------+-------------------+-------------------
trigger_send_fcm_notification   | INSERT            | notifications
```

### Step 4: Test

1. Create a new order
2. Check logs for single FCM send
3. Verify provider receives only ONE notification

---

## 🔍 ADDITIONAL POTENTIAL ISSUES

### 1. Automated Notifications System

**File:** `.agent/AUTOMATED_NOTIFICATIONS_SYSTEM.sql`

This script schedules periodic notifications for:
- Order deadline reminders (every hour)
- Subscription expiry reminders (twice daily)
- Fine alerts (trigger-based)

**Risk:** If cron jobs run multiple times or triggers overlap, could create duplicates.

**Verification Needed:**
- Check if cron jobs are properly configured
- Verify idempotency checks (lines 43-49, 189-198) are working

---

### 2. FCM Foreground Handling

**File:** `lib/firebase/fcm_service.dart`  
**Line:** 145-186

The `_handleForegroundMessage` function manually creates a local notification.

**Potential Issue:**
- If FCM already displays the notification automatically
- AND the local notification is shown manually
- Result: 2 notifications (1 from FCM, 1 local)

**Current Code:**
```dart
static Future<void> _handleForegroundMessage(RemoteMessage message) async {
  // ...
  await _localNotifications.show(
    notification.hashCode,
    notification.title,
    notification.body,
    // ...
  );
}
```

**Recommendation:**
- This is correct behavior for foreground messages
- Keep as-is unless you see duplicates ONLY when app is in foreground

---

### 3. Multiple FCM Listeners

**Check:** `lib/main.dart`

Ensure `FCMService.initialize()` is called only ONCE during app startup.

---

## 📋 TESTING CHECKLIST

After applying the fix:

- [ ] Clear app data / Reinstall app
- [ ] Login as provider on Device A
- [ ] Login as user on Device B
- [ ] Create order from user
- [ ] Verify provider receives ONLY 1 notification
- [ ] Check Supabase notifications table:
  ```sql
  SELECT user_id, order_id, message, created_at 
  FROM notifications 
  WHERE order_id = 'YOUR_TEST_ORDER_ID';
  ```
  Should show only 1 row per provider
- [ ] Check Edge Function logs in Supabase Dashboard
  Should show single invocation per notification

---

## 🎯 SUMMARY

**Root Cause:** Dual notification insertion (Flutter app + Database trigger) for the same event

**Fix:** Remove manual notification insert from `order_create.dart`, rely solely on database trigger

**Priority:** CRITICAL - This affects all order notifications

**Effort:** 5 minutes (delete code)

**Risk:** Low - Database trigger is more reliable

---

## 📞 NEXT STEPS

1. Apply the code fix (remove manual insert)
2. Run verification SQL queries
3. Test with real devices
4. Monitor for 24-48 hours
5. If issue persists, investigate FCM foreground handling

---

**Document created by:** Antigravity AI  
**Status:** Ready for implementation
