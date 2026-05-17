# Subscription-Based Notification System - Complete Overview

## Current Status: ⚠️ PARTIALLY IMPLEMENTED

### ✅ What's Already Working
1. **Flutter App - Direct Hire** (`order_create.dart`)
   - When user hires a specific provider
   - ✅ Checks if provider has active subscription before sending notification
   - Code: Lines 109-140 in `order_create.dart`

2. **Subscription Management** (`subscription_page.dart`)
   - ✅ Razorpay integration working
   - ✅ Updates `is_subscribed` and `subscription_expiry` fields
   - ✅ Payment verification working

### ❌ What Needs to be Fixed
**Database Trigger for Broadcast Orders**
- File: Database function `notify_providers_on_order()`
- Issue: Currently notifies ALL providers, not checking subscription status
- Fix: Update the function to filter by `is_subscribed` and `subscription_expiry`

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    USER PLACES ORDER                        │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │  Order Type?   │
         └────┬──────┬────┘
              │      │
    ┌─────────┘      └──────────┐
    │                           │
    ▼                           ▼
┌───────────────┐        ┌─────────────────┐
│ BROADCAST     │        │  DIRECT HIRE    │
│ (request_open)│        │  (pending)      │
└───────┬───────┘        └────────┬────────┘
        │                         │
        ▼                         ▼
┌──────────────────┐      ┌────────────────────┐
│ DB Trigger Fires │      │ order_create.dart  │
│ notify_providers │      │ Manual Check       │
│ _on_order()      │      └────────┬───────────┘
└────────┬─────────┘               │
         │                         │
         │ ❌ NEEDS FIX            │ ✅ ALREADY WORKING
         │                         │
         ▼                         ▼
    ┌─────────────────────────────────────┐
    │  Check Provider Subscription:       │
    │  • is_subscribed = TRUE             │
    │  • subscription_expiry > NOW()      │
    └──────┬──────────────────────────────┘
           │
           ▼
    ┌─────────────────┐
    │ Send Notification│
    │ to Provider      │
    └─────────────────┘
```

---

## Implementation Details

### 1. Database Schema

**users table:**
```sql
Column              | Type         | Description
--------------------|--------------|----------------------------------
is_provider         | BOOLEAN      | Is this user a service provider?
is_subscribed       | BOOLEAN      | Has active subscription?
subscription_expiry | TIMESTAMPTZ  | When does subscription expire?
service_id          | UUID         | What service provider offers
location            | TEXT         | Provider's location
```

### 2. Notification Logic

#### A. Broadcast Orders (request_open)
**Trigger:** `notify_providers_on_order()`
**When:** Order created with status = 'request_open'
**Current Logic:**
```sql
SELECT id FROM users 
WHERE is_provider = TRUE 
AND service_id = NEW.service_id 
AND location matches
```

**Updated Logic (NEEDS TO BE APPLIED):**
```sql
SELECT id FROM users 
WHERE is_provider = TRUE 
AND service_id = NEW.service_id 
AND is_subscribed = TRUE              ← NEW
AND (subscription_expiry IS NULL       ← NEW
     OR subscription_expiry > NOW())   ← NEW
AND location matches
```

#### B. Direct Hire (pending)
**File:** `order_create.dart`
**When:** User selects specific provider to hire
**Logic (ALREADY IMPLEMENTED):**
```dart
// Lines 109-140
final providerData = await SupabaseConfig.supabase
  .from('users')
  .select('is_subscribed, subscription_expiry')
  .eq('id', widget.providerId)
  .single();

final isSubscribed = providerData['is_subscribed'] == true;
final expiryStr = providerData['subscription_expiry'];

bool isActive = false;
if (isSubscribed && expiryStr != null) {
  final expiry = DateTime.parse(expiryStr);
  isActive = expiry.isAfter(DateTime.now());
}

if (isActive) {
  // Send notification
} else {
  // Don't send notification
}
```

---

## How to Apply the Fix

### Quick Method: Run SQL Script

1. **Open Supabase Dashboard** → SQL Editor
2. **Copy the contents** of `lib/security/APPLY_SUBSCRIPTION_FILTER.sql`
3. **Paste** in SQL Editor
4. **Click "Run"**
5. **Done!** ✅

The script will:
- Ensure subscription columns exist
- Update the `notify_providers_on_order()` function
- Apply changes immediately (no app restart needed)

---

## Testing Scenarios

### Scenario 1: Subscribed Provider
```
Provider Setup:
├─ is_subscribed: TRUE
├─ subscription_expiry: 2025-12-30T00:00:00Z
└─ service_id: Cleaning

User Action:
└─ Places broadcast order for "Cleaning"

Expected Result:
✅ Provider receives notification
```

### Scenario 2: Unsubscribed Provider
```
Provider Setup:
├─ is_subscribed: FALSE
├─ subscription_expiry: NULL
└─ service_id: Cleaning

User Action:
└─ Places broadcast order for "Cleaning"

Expected Result:
❌ Provider DOES NOT receive notification
```

### Scenario 3: Expired Subscription
```
Provider Setup:
├─ is_subscribed: TRUE
├─ subscription_expiry: 2025-12-15T00:00:00Z (PAST)
└─ service_id: Cleaning

User Action:
└─ Places broadcast order for "Cleaning"

Expected Result:
❌ Provider DOES NOT receive notification
```

---

## Verification Queries

### Check Provider Subscription Status
```sql
SELECT 
  full_name,
  is_subscribed,
  subscription_expiry,
  CASE 
    WHEN is_subscribed AND (subscription_expiry IS NULL OR subscription_expiry > NOW())
    THEN '✅ ACTIVE'
    ELSE '❌ INACTIVE'
  END as status
FROM users 
WHERE is_provider = TRUE;
```

### Check Recent Notifications
```sql
SELECT 
  u.full_name,
  u.is_subscribed,
  n.message,
  n.created_at
FROM notifications n
JOIN users u ON n.user_id = u.id
WHERE n.created_at > NOW() - INTERVAL '1 hour'
ORDER BY n.created_at DESC;
```

---

## Files Reference

| File | Purpose | Status |
|------|---------|--------|
| `lib/security/APPLY_SUBSCRIPTION_FILTER.sql` | Quick fix SQL script | ✅ Ready to run |
| `lib/security/fix_subscription_filter.sql` | Original migration | ✅ Created |
| `lib/security/SUBSCRIPTION_FILTER_FIX.md` | Original docs | ✅ Created |
| `.agent/subscription_notification_fix.md` | Implementation guide | ✅ Created |
| `lib/orders/order_create.dart` | Direct hire logic | ✅ Already fixed |
| `lib/subscription/subscription_page.dart` | Subscription UI | ✅ Working |

---

## Summary

**What you need to do:**
1. Open Supabase SQL Editor
2. Run `lib/security/APPLY_SUBSCRIPTION_FILTER.sql`
3. Test by placing orders

**Result:**
- Subscribed providers: ✅ Get notifications
- Unsubscribed providers: ❌ No notifications
- Expired subscriptions: ❌ No notifications

**Time to implement:** < 5 minutes
