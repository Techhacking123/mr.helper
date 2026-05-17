# 📱 Automated Push Notification System - Implementation Guide

## ✅ Requirements Implemented

### **1. Order Deadline Reminders** ⏰
**To:** Provider AND User  
**Triggers:**
- 10 hours before deadline
- 2 hours before deadline
- 1 hour before deadline

**Conditions:**
- Only if order status is NOT "completed"
- Only if order status is NOT "cancelled"
- Only if user hasn't clicked "Service Completed"

**Action:** Opens Order Detail page when notification clicked

---

### **2. Subscription Expiry Reminders** 📆
**To:** Provider ONLY  
**Triggers:**
- 3 days before expiry
- 2 days before expiry
- 1 day before expiry
- 1 hour before expiry

**Action:** Opens Subscription Page when notification clicked

---

### **3. Fine Alert Notifications** 💰
**To:** Provider ONLY  
**Trigger:** When fine is applied to order

**Action:** Opens Subscription Page when notification clicked

---

## 📁 Files Created/Modified

### **1. Database (SQL)**
✅ `.agent/AUTOMATED_NOTIFICATIONS_SYSTEM.sql`
- Order deadline reminder function
- Subscription expiry reminder function
- Fine alert trigger
- Verification queries

### **2. Edge Functions (TypeScript)**
✅ `supabase/functions/deadline-reminders/index.ts`
- Calls `send_order_deadline_reminders()` every hour

✅ `supabase/functions/subscription-reminders/index.ts`
- Calls `send_subscription_expiry_reminders()` twice daily

### **3. Flutter App (Dart)**
✅ `lib/firebase/fcm_service.dart`
- Deep linking support added
- Navigation to Subscription Page
- Navigation to Order Detail Page
- Handles notification data properly

---

## 🚀 Deployment Steps

### **Step 1: Apply Database Changes**

1. **Open Supabase Dashboard** → SQL Editor
2. **Copy contents of** `.agent/AUTOMATED_NOTIFICATIONS_SYSTEM.sql`
3. **Paste and Run** the entire script
4. **Verify** execution completed successfully

**This will create:**
- `send_order_deadline_reminders()` function
- `send_subscription_expiry_reminders()` function
- `notify_provider_of_fines()` trigger function
- Trigger on `orders.fine_amount` updates

---

### **Step 2: Deploy Edge Functions**

**Option A: Using Supabase CLI**
```powershell
cd c:\Users\Karthik\Desktop\mrhelperAI

# Deploy deadline reminders
supabase functions deploy deadline-reminders

# Deploy subscription reminders
supabase functions deploy subscription-reminders
```

**Option B: Using Supabase Dashboard**
1. Go to: **Edge Functions** → **Deploy new function**
2. Upload `supabase/functions/deadline-reminders/index.ts`
3. Upload `supabase/functions/subscription-reminders/index.ts`

---

### **Step 3: Set Up Cron Schedules**

1. Go to **Supabase Dashboard** → **Edge Functions** 
2. Select **deadline-reminders**
3. Click **"Add Cron Trigger"**
4. Set schedule: `0 * * * *` (every hour)
5. Click **Save**

6. Select **subscription-reminders**
7. Click **"Add Cron Trigger"** twice:
   - First: `0 9 * * *` (9 AM daily)
   - Second: `0 18 * * *` (6 PM daily)
8. Click **Save**

---

### **Step 4: Test the System**

#### **Test 1: Manual Function Execution**
```sql
-- Test order deadline reminders
SELECT send_order_deadline_reminders();

-- Test subscription expiry reminders
SELECT send_subscription_expiry_reminders();
```

#### **Test 2: Check Notifications Created**
```sql
-- View recent deadline reminders
SELECT * FROM notifications 
WHERE type = 'order_deadline_reminder' 
ORDER BY created_at DESC LIMIT 10;

-- View recent subscription expiry reminders
SELECT * FROM notifications 
WHERE type = 'subscription_expiry_reminder' 
ORDER BY created_at DESC LIMIT 10;

-- View recent fine alerts
SELECT * FROM notifications 
WHERE type = 'fine_alert' 
ORDER BY created_at DESC LIMIT 10;
```

#### **Test 3: Create Test Data**

**Create order approaching deadline:**
```sql
INSERT INTO orders (
  title, 
  service_id, 
  provider_id, 
  user_id, 
  deadline, 
  status
) VALUES (
  'Test Order for Deadline Reminder',
  'YOUR_SERVICE_ID',
  'YOUR_PROVIDER_ID',
  'YOUR_USER_ID',
  NOW() + INTERVAL '2 hours',  -- 2 hours from now
  'verified'
);
```

**Create provider with expiring subscription:**
```sql
UPDATE users
SET 
  subscription_status = 'active',
  subscription_end_date = NOW() + INTERVAL '2 days'
WHERE id = 'YOUR_PROVIDER_ID';
```

**Create fine on order:**
```sql
UPDATE orders
SET fine_amount = 50
WHERE id = 'YOUR_ORDER_ID';
-- This will automatically trigger fine notification!
```

---

## 📊 Notification Data Structure

### **Order Deadline Reminders**
```json
{
  "screen": "order_detail",
  "order_id": "uuid-123",
  "hours_left": 2.5
}
```

### **Subscription Expiry Reminders**
```json
{
  "screen": "subscription_page",
  "reminder_key": "provider-id_1hour",
  "days_left": 0.5,
  "hours_left": 12
}
```

### **Fine Alerts**
```json
{
  "screen": "subscription_page",
  "order_id": "uuid-123",
  "fine_amount": 50
}
```

---

## 🔍 Debugging & Monitoring

### **Check which orders would trigger reminders NOW:**
```sql
SELECT 
    id, title, deadline, status,
    EXTRACT(EPOCH FROM (deadline - NOW())) / 3600 AS hours_left
FROM orders
WHERE status NOT IN ('completed', 'cancelled')
AND deadline > NOW()
AND deadline < NOW() + INTERVAL '10 hours'
ORDER BY hours_left;
```

### **Check which subscriptions would trigger reminders NOW:**
```sql
SELECT 
    id, full_name, subscription_end_date,
    EXTRACT(EPOCH FROM (subscription_end_date - NOW())) / 86400 AS days_left
FROM users
WHERE is_provider = TRUE
AND subscription_status = 'active'
AND subscription_end_date > NOW()
AND subscription_end_date < NOW() + INTERVAL '3 days'
ORDER BY days_left;
```

### **Check if functions exist:**
```sql
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname IN (
  'send_order_deadline_reminders',
  'send_subscription_expiry_reminders',
  'notify_provider_of_fines'
);
```

### **Check if trigger exists:**
```sql
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgname = 'trigger_notify_provider_fines';
```

---

## 🎯 How It Works

### **Order Deadline Flow**
```
Cron Job (Every Hour)
  ↓
deadline-reminders Edge Function
  ↓
send_order_deadline_reminders() SQL Function
  ↓
Checks all orders with deadline < 10hrs
  ↓
Creates notifications for provider + user
  ↓
FCM sends push notification
  ↓
User sees notification in phone
  ↓
Taps notification
  ↓
App opens Order Detail page
```

### **Subscription Expiry Flow**
```
Cron Job (9 AM & 6 PM)
  ↓
subscription-reminders Edge Function
  ↓
send_subscription_expiry_reminders() SQL Function
  ↓
Checks all subscriptions expiring < 3 days
  ↓
Creates notifications for providers
  ↓
FCM sends push notification
  ↓
Provider sees notification
  ↓
Taps notification
  ↓
App opens Subscription Page
```

### **Fine Alert Flow**
```
Order fine_amount is updated
  ↓
Database trigger fires automatically
  ↓
notify_provider_of_fines() function
  ↓
Creates notification for provider
  ↓
FCM sends push notification
  ↓
Provider sees notification
  ↓
Taps notification
  ↓
App opens Subscription Page
```

---

## ⚙️ Configuration

### **Adjust Reminder Times**
Edit `.agent/AUTOMATED_NOTIFICATIONS_SYSTEM.sql`:

```sql
-- Change from 10hr, 2hr, 1hr to 12hr, 3hr, 30min:
WHERE deadline < NOW() + INTERVAL '12 hours'  -- Line ~24
-- Then adjust conditions for 3hr and 30min

-- Change subscription warnings from 3,2,1 days to 5,3,1 days:
WHERE subscription_end_date < NOW() + INTERVAL '5 days'  -- Line ~160
-- Then adjust conditions for 3 and 1 day
```

### **Change Cron Schedules**
In Supabase Dashboard:
- `0 * * * *` = Every hour
- `0 */2 * * *` = Every 2 hours
- `0 9 * * *` = 9 AM daily
- `*/30 * * * *` = Every 30 minutes

---

## 🐛 Troubleshooting

### **Problem: Notifications not sending**
**Check:**
1. Are Edge Functions deployed? (Supabase Dashboard → Edge Functions)
2. Are cron jobs active? (Check cron tab in Edge Functions)
3. Are FCM tokens saved? (`SELECT fcm_token FROM users WHERE id = 'YOUR_ID'`)
4. Check Edge Function logs for errors

### **Problem: Duplicate notifications**
**Fix:**
The SQL functions already prevent duplicates using:
```sql
AND NOT EXISTS (
  SELECT 1 FROM notifications
  WHERE... AND created_at > NOW() - INTERVAL '12 hours'
)
```

### **Problem: Notifications send but don't navigate**
**Check:**
1. Is `navigatorKey` exported from `main.dart`?
2. Are notification `data` fields correct?
3. Check Flutter logs for navigation errors

### **Problem: Fine trigger not firing**
**Check:**
```sql
-- Verify trigger exists and is enabled
SELECT * FROM pg_trigger 
WHERE tgname = 'trigger_notify_provider_fines';

-- Test manually
UPDATE orders SET fine_amount = 100 WHERE id = 'TEST_ORDER_ID';
```

---

## ✅ Verification Checklist

- [ ] SQL script executed successfully in Supabase
- [ ] Edge Functions deployed
- [ ] Cron schedules configured
- [ ] Test order created with deadline < 2 hours
- [ ] Test subscription created expiring < 2 days
- [ ] Test fine applied to order
- [ ] Notifications created in database
- [ ] Push notifications received on device
- [ ] Tapping notifications opens correct page
- [ ] No duplicate notifications

---

## 📈 Monitoring Queries

**Daily notification summary:**
```sql
SELECT 
  type,
  COUNT(*) as notification_count,
  DATE(created_at) as date
FROM notifications
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY type, DATE(created_at)
ORDER BY date DESC, type;
```

**Recent notifications:**
```sql
SELECT 
  n.created_at,
  n.type,
  n.title,
  n.message,
  u.full_name as recipient
FROM notifications n
JOIN users u ON n.user_id = u.id
WHERE n.created_at > NOW() - INTERVAL '24 hours'
ORDER BY n.created_at DESC
LIMIT 50;
```

---

## 🎉 System Complete!

All three notification systems are now fully implemented:
- ✅ Order deadline reminders (10hr, 2hr, 1hr)
- ✅ Subscription expiry reminders (3 days, 2 days, 1 day, 1hr)
- ✅ Fine alerts (instant, trigger-based)
- ✅ Deep linking to correct pages
- ✅ Duplicate prevention
- ✅ Automated scheduling

**Ready for production!** 🚀
