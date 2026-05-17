# Multi-Device Push Notification Support - Implementation Guide

## 🎯 Overview

This implementation enables users to receive push notifications on **multiple devices simultaneously** (phone, tablet, etc.). When a user signs in on multiple devices, all devices will receive notifications.

---

## 📋 What Changed

### 1. **Database Layer** ✅
- Created `user_fcm_tokens` table to store multiple tokens per user
- Created RPC functions for managing tokens
- Migrated existing tokens from `users.fcm_token` column

### 2. **Flutter App** ✅
- Updated `FCMService` to use multi-device RPC functions
- Added device ID generation and tracking
- Updated sign-out to only clear current device's token

### 3. **Edge Function** ✅
- Updated `push_notifications` to send to ALL user devices
- Added automatic cleanup of invalid/expired tokens
- Improved error handling and logging

---

## 🚀 Deployment Steps

### Step 1: Apply Database Migration

**Option A: Via Supabase Dashboard**
1. Go to Supabase Dashboard → SQL Editor
2. Open `.agent/migrations/multi_device_fcm_support.sql`
3. Copy and paste the entire contents
4. Click "Run"
5. Verify success message: ✅ "Multi-device FCM token support migration completed successfully!"

**Option B: Via Supabase CLI**
```bash
cd supabase
supabase db push
```

### Step 2: Deploy Updated Edge Function

```bash
# Deploy the updated push_notifications function
supabase functions deploy push_notifications
```

### Step 3: Test the Flutter App

```bash
flutter run
```

---

## 🧪 Testing Scenarios

### Scenario 1: Single Device (Works as Before)
```
1. Login on Phone A
2. Create a notification trigger
3. ✅ Phone A receives notification
```

### Scenario 2: Two Devices, Both Active
```
1. Login on Phone A → Device A registered
2. Login on Phone B (same user) → Device B registered
3. Create a notification trigger
4. ✅ BOTH Phone A and Phone B receive notification
```

### Scenario 3: Sign Out from One Device
```
1. Login on Phone A → Device A registered
2. Login on Phone B → Device B registered
3. Sign Out on Phone A → Device A token removed
4. Create a notification trigger
5. ✅ Only Phone B receives notification
6. ❌ Phone A does NOT receive notification
```

### Scenario 4: User Switches Accounts on Same Device
```
1. Provider logs in on Phone A → Token saved for Provider
2. Provider signs out → Token removed from Provider
3. User logs in on Phone A → Token saved for User
4. Create order notification
5. ✅ Notification goes to PROVIDER (on other orders)
6. ❌ User does NOT receive provider notifications
```

---

## 📊 Database Verification Queries

### Check All Active Tokens
```sql
SELECT 
  u.full_name,
  u.role,
  t.device_id,
  t.device_name,
  t.platform,
  t.created_at,
  t.last_used_at,
  t.is_active
FROM user_fcm_tokens t
JOIN users u ON t.user_id = u.id
WHERE t.is_active = TRUE
ORDER BY u.full_name, t.created_at DESC;
```

### Count Devices Per User
```sql
SELECT 
  u.id,
  u.full_name,
  COUNT(t.id) as device_count
FROM users u
LEFT JOIN user_fcm_tokens t ON u.id = t.user_id AND t.is_active = TRUE
GROUP BY u.id, u.full_name
HAVING COUNT(t.id) > 0
ORDER BY device_count DESC;
```

### Find Users with Multiple Devices
```sql
SELECT 
  u.full_name,
  COUNT(t.id) as device_count,
  STRING_AGG(t.device_name, ', ') as devices
FROM users u
JOIN user_fcm_tokens t ON u.id = t.user_id
WHERE t.is_active = TRUE
GROUP BY u.id, u.full_name
HAVING COUNT(t.id) > 1;
```

### Check for Duplicate Tokens (Should Return 0 Rows)
```sql
SELECT fcm_token, COUNT(*) as count
FROM user_fcm_tokens
WHERE is_active = TRUE
GROUP BY fcm_token
HAVING COUNT(*) > 1;
```

---

## 🔍 How It Works

### Device Registration Flow

```
User Opens App
    ↓
Firebase generates FCM token
    ↓
FCMService.saveTokenForCurrentUser() called
    ↓
Generate/retrieve unique device_id
    ↓
Call add_or_update_fcm_token RPC
    ↓
Database checks if token belongs to another user
    ↓
If yes: Remove from old user
    ↓
Save token to user_fcm_tokens table
    ↓
✅ Device registered
```

### Notification Sending Flow

```
Notification triggered (e.g., new order)
    ↓
Insert into notifications table
    ↓
Database trigger calls push_notifications Edge Function
    ↓
Query user_fcm_tokens for ALL active tokens
    ↓
Use sendEachForMulticast() to send to all devices
    ↓
Handle failures:
  - Invalid tokens → Remove from database
  - Network errors → Retry
    ↓
✅ Notifications delivered to all devices
```

### Sign Out Flow

```
User clicks Sign Out
    ↓
SessionManager.clearSession() called
    ↓
FCMService.clearTokenForCurrentUser() called
    ↓
Get current device's FCM token
    ↓
Get current device_id
    ↓
Call remove_fcm_token RPC with both
    ↓
Database removes ONLY this device's token
    ↓
Other devices for same user: STILL ACTIVE
    ↓
Clear local session data
    ↓
✅ Signed out (other devices unaffected)
```

---

## 🛠️ RPC Functions Reference

### `add_or_update_fcm_token()`
**Purpose:** Add or update FCM token for a device

**Parameters:**
- `p_user_id` (UUID) - The user's ID
- `p_fcm_token` (TEXT) - The FCM token
- `p_device_id` (TEXT, optional) - Unique device identifier
- `p_device_name` (TEXT, optional) - Human-readable device name
- `p_platform` (TEXT, default='android') - Platform type

**Returns:** UUID of the token record

**Usage:**
```dart
final tokenId = await SupabaseConfig.supabase.rpc(
  'add_or_update_fcm_token',
  params: {
    'p_user_id': userId,
    'p_fcm_token': fcmToken,
    'p_device_id': deviceId,
    'p_device_name': 'Samsung Galaxy S21',
    'p_platform': 'android',
  },
);
```

### `remove_fcm_token()`
**Purpose:** Remove FCM token(s) on sign out

**Parameters:**
- `p_user_id` (UUID) - The user's ID
- `p_fcm_token` (TEXT, optional) - Specific token to remove
- `p_device_id` (TEXT, optional) - Specific device to remove

**Returns:** Number of tokens removed

**Usage:**
```dart
// Remove specific token
await supabase.rpc('remove_fcm_token', params: {
  'p_user_id': userId,
  'p_fcm_token': token,
});

// Remove all tokens for user (sign out from all devices)
await supabase.rpc('remove_fcm_token', params: {
  'p_user_id': userId,
});
```

### `get_user_fcm_tokens()`
**Purpose:** Get all active tokens for a user

**Parameters:**
- `p_user_id` (UUID) - The user's ID

**Returns:** Table of tokens with device info

**Usage:**
```dart
final tokens = await supabase.rpc('get_user_fcm_tokens', params: {
  'p_user_id': userId,
});
```

### `cleanup_inactive_fcm_tokens()`
**Purpose:** Clean up old/inactive tokens (run via cron)

**Returns:** Number of tokens cleaned up

**Schedule:** Recommended to run daily via Supabase Cron

**Cron Setup:**
```sql
SELECT cron.schedule(
  'cleanup_fcm_tokens',
  '0 2 * * *', -- Run at 2 AM daily
  $$SELECT cleanup_inactive_fcm_tokens()$$
);
```

---

## 📱 Expected Logs

### On Login
```
💾 Saving FCM Token for user <uuid> (multi-device)
📱 Generated new device ID: device_1704067200000_1234
✅ FCM token saved (token_id: <uuid>) for user: <uuid>
```

### On Sign Out
```
🗑️ Clearing FCM Token for user <uuid> on THIS device
✅ Removed 1 token(s) for user: <uuid>
Local FCM token reference cleared
```

### On Notification Send
```
📱 Found 2 active device(s) for user <uuid>
✅ Notification sent to 2/2 devices
```

---

## 🐛 Troubleshooting

### Issue: No notifications received on any device
**Check:**
1. Verify tokens exist: `SELECT * FROM user_fcm_tokens WHERE user_id = '<uuid>';`
2. Check Edge Function logs in Supabase Dashboard
3. Verify Firebase service account credentials are set

### Issue: Only one device receives notifications
**Check:**
1. Verify both devices have active tokens in database
2. Check Edge Function is using `sendEachForMulticast` (not `send`)
3. Look for "Failed to send" errors in Edge Function logs

### Issue: Old device still receives notifications after sign out
**Check:**
1. Verify `remove_fcm_token` was called in logs
2. Check token was actually deleted from database
3. Manually remove: `DELETE FROM user_fcm_tokens WHERE fcm_token = '<token>';`

---

## ⚙️ Optional: Cleanup Old Column

After verifying everything works, you can remove the old `fcm_token` column from users table:

```sql
-- ONLY run this after confirming multi-device works perfectly
ALTER TABLE users DROP COLUMN IF EXISTS fcm_token;
```

---

## 📈 Performance Considerations

- **Token Limit:** Firebase allows up to 500 tokens per multicast
- **For >500 devices:** Batch into multiple multicasts
- **Database Load:** Indexed queries on `user_id` and `is_active`
- **Cleanup:** Automatic removal of invalid tokens on send failure

---

## 🔐 Security Notes

- RLS policies allow users to manage their own tokens
- SECURITY DEFINER functions bypass RLS for admin operations
- Tokens are device-specific and cleared on sign out
- Invalid tokens automatically removed on send failure

---

**Status:** ✅ Ready for Testing  
**Last Updated:** 2026-01-01  
**Version:** 2.0 (Multi-Device Support)
