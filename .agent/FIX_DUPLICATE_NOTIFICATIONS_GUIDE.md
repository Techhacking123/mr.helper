# FIX DUPLICATE NOTIFICATIONS - STEP BY STEP GUIDE

## 🎯 PROBLEM
Users and providers are receiving the **same push notification twice** for a single event.

## 🔍 ROOT CAUSE
**Dual Notification System:** Your app has TWO independent systems creating notifications for the same event:

1. **Flutter App** (`order_create.dart` lines 109-148) - Manually inserts notification
2. **Database Trigger** (`20241225221002_fix_provider_matching.sql`) - Automatically inserts notification

Both trigger the FCM Edge Function, resulting in 2 identical push notifications.

---

## ✅ SOLUTION - 3 Steps

### **STEP 1: Fix Flutter Code (order_create.dart)**

**Location:** `lib/orders/order_create.dart`

**Action:** Delete lines 109-148 and replace with a simple comment.

**Before (Lines 107-148):**
```dart
      final orderId = orderRes['id'];

      // 2. CRITICAL: Check Provider Subscription Status Before Sending Notification
      final providerData = await SupabaseConfig.supabase
          .from('users')
          .select(
            'subscription_status, subscription_end_date, is_subscribed, subscription_expiry',
          )
          .eq('id', widget.providerId)
          .single();

      // Use new subscription_status field (with fallback)
      final subscriptionStatus =
          providerData['subscription_status'] ??
          (providerData['is_subscribed'] == true ? 'active' : 'none');

      final endDateStr =
          providerData['subscription_end_date'] ??
          providerData['subscription_expiry'];

      bool isActive = false;
      if (subscriptionStatus == 'active' && endDateStr != null) {
        final endDate = DateTime.parse(endDateStr);
        isActive = endDate.isAfter(DateTime.now());
      }

      if (isActive) {
        // Only send notification if provider has ACTIVE subscription
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': widget.providerId,
          'order_id': orderId,
          'message': 'You have received a new order from a user.',
          'is_read': false,
        });
        debugPrint(
          '✅ Notification sent to subscribed provider: ${widget.providerId}',
        );
      } else {
        debugPrint(
          '❌ Notification BLOCKED - Provider subscription inactive/expired: ${widget.providerId}',
        );
      }
```

**After (Replace lines 107-148 with):**
```dart
      final orderId = orderRes['id'];

      // Notification is automatically handled by database trigger
      // See: supabase/migrations/20241225221002_fix_provider_matching.sql
      // The 'on_new_order_notify' trigger sends notifications to matching providers
      // with proper subscription status and expiry validation
      debugPrint('✅ Order created. Database trigger will handle notifications.');
```

**How to do it:**
1. Open `lib/orders/order_create.dart` in your editor
2. Find line 107 (`final orderId = orderRes['id'];`)  
3. Delete everything from line 109 to line 148 (the entire subscription check and notification insert)
4. Add the 5-line comment shown above
5. Save the file

---

### **STEP 2: Verify Database Triggers**

**Run this SQL in Supabase SQL Editor:**

```sql
-- Check for duplicate triggers
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE event_object_table IN ('orders', 'notifications')
ORDER BY event_object_table, trigger_name;
```

**Expected Result:**
```
trigger_name                    | event_object_table
-------------------------------+-------------------
on_new_order_notify            | orders
trigger_send_fcm_notification  | notifications
```

**If you see MORE than 2 triggers total**, you have duplicates. Run:

```sql
-- Drop duplicate triggers
DROP TRIGGER IF EXISTS notify_providers_trigger ON orders;
DROP TRIGGER IF EXISTS notify_providers_on_order_trigger ON orders;
DROP TRIGGER IF EXISTS tr_notify_providers ON orders;

-- Keep ONLY 'on_new_order_notify' on orders table
-- Keep ONLY 'trigger_send_fcm_notification' on notifications table
```

---

### **STEP 3: Test the Fix**

1. **Hot Restart Flutter App:**
   - In terminal: Press `R` (shift + R) for full restart
   - Or stop and run: `flutter run`

2. **Test Notification Flow:**
   - Login as **Provider** on Device A
   - Login as **User** on Device B
   - Create an order as User
   - **Verify**: Provider receives ONLY 1 notification

3. **Check Database:**
   ```sql
   SELECT user_id, order_id, message, created_at 
   FROM notifications 
   WHERE order_id = 'YOUR_ORDER_ID_HERE'
   ORDER BY created_at DESC;
   ```
   
   Should show **exactly 1 row** per provider for this order.

4. **Check Edge Function Logs:**
   - Go to Supabase Dashboard
   - Functions → `push_notifications` → Logs
   - Should show **single invocation** per notification

---

## 🔧 ADDITIONAL CHECKS

### If Duplicates Persist After Fix:

#### Check 1: FCM Topic Subscriptions
Make sure providers aren't subscribed to FCM topics multiple times.

**File:** `lib/auth/login.dart`  
**Verify:** Topic subscription happens only once with cleanup:

```dart
// Unsubscribe from all topics first
await FCMService.unsubscribeFromTopic('admins');
await FCMService.unsubscribeFromTopic('providers');
await FCMService.unsubscribeFromTopic('users');

// Subscribe to correct topic
if (role == 'provider') {
  await FCMService.subscribeToTopic('providers');
}
```

#### Check 2: Automated Notification Cron Jobs

If you've enabled the automated notification system (`.agent/AUTOMATED_NOTIFICATIONS_SYSTEM.sql`), verify cron jobs aren't running multiple times.

**In Supabase SQL Editor:**
```sql
-- Check recent automated notifications
SELECT * FROM notifications 
WHERE type IN ('order_deadline_reminder', 'subscription_expiry_reminder', 'fine_alert')
AND created_at > NOW() - INTERVAL '1 day'
ORDER BY created_at DESC;
```

#### Check 3: Multiple FCM Listeners

**File:** `lib/main.dart`  
**Verify:** `FCMService.initialize()` is called only ONCE:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FCMService.initialize(); // Should appear ONLY once
  // ... rest of main
}
```

---

## 📊 VERIFICATION QUERIES

Run these after the fix to ensure success:

```sql
-- 1. No duplicate notifications in last 24 hours
SELECT user_id, order_id, COUNT(*) as count
FROM notifications
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY user_id, order_id
HAVING COUNT(*) > 1;
-- Should return: 0 rows

-- 2. Trigger count check
SELECT COUNT(*) as trigger_count
FROM information_schema.triggers 
WHERE event_object_table = 'orders';
-- Should return: 1

SELECT COUNT(*) as trigger_count
FROM information_schema.triggers 
WHERE event_object_table = 'notifications';
-- Should return: 1
```

---

## 🚨 ROLLBACK (If Something Breaks)

If you need to revert the change:

1. **Restore order_create.dart:**
   - Use Git: `git checkout lib/orders/order_create.dart`
   - Or manually restore lines 109-148 from backup

2. **Disable Database Trigger:**
   ```sql
   DROP TRIGGER IF EXISTS on_new_order_notify ON orders;
   ```

This will revert to app-level notification control.

---

## 📝 SUMMARY

| Component | Issue | Fix |
|-----------|-------|-----|
| **order_create.dart** | Manual notification insert | ✅ Removed (lines 109-148) |
| **Database Trigger** | Auto notification insert | ✅ Keep (handles everything) |
| **Result** | Duplicate notifications | ✅ Single notification |

---

## 🎯 NEXT STEPS

1. ✅ Apply Step 1 (Edit order_create.dart)
2. ✅ Run Step 2 (Verify database triggers)
3. ✅ Execute Step 3 (Test the fix)
4. ✅ Monitor for 24-48 hours
5. ✅ If successful, close this issue

---

**Created:** December 30, 2025  
**Priority:** CRITICAL  
**Estimated Time:** 10 minutes  
**Confidence:** High (95%)
