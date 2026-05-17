# Quick Fix Verification

## ✅ What Was Fixed

**Problem:** When signing out and logging in with a different account, push notifications were going to the wrong user.

**Root Cause:** FCM tokens weren't being cleared from the database on logout, causing the same device token to be associated with multiple users.

## 🔧 Changes Made

### 1. **FCM Service** (`lib/firebase/fcm_service.dart`)
   - ✅ Added `clearTokenForCurrentUser()` method to remove tokens on logout

### 2. **Session Manager** (`lib/auth/session_manager.dart`)
   - ✅ Updated `clearSession()` to clear FCM token before clearing session data

### 3. **Database Function** (`.agent/migrations/fix_fcm_token_uniqueness.sql`)
   - ✅ Enhanced `update_fcm_token()` to ensure token uniqueness across users

## 🧪 Quick Test

1. **Apply Database Migration First**
   ```
   Navigate to: Supabase Dashboard → SQL Editor
   Run: .agent/migrations/fix_fcm_token_uniqueness.sql
   ```

2. **Test the Flow**
   ```
   Provider Login → Sign Out → User Login → Test Notification
   ```

3. **Verify in Logs**
   Look for these messages:
   - ✅ "Clearing FCM Token for user [id]"
   - ✅ "FCM token cleared via RPC"
   - ✅ "FCM token saved to database"

## 🎯 Expected Behavior

| Action | Expected Result |
|--------|----------------|
| Provider signs out | Token cleared from database |
| User signs in (same device) | Old token removed from provider, assigned to user |
| Order created | Notification goes to PROVIDER only, not user |
| User signs out, Provider signs in | Token reassigned correctly |

## 📊 Database Check

Run in Supabase SQL Editor:
```sql
-- Check for duplicate tokens (should return 0 rows)
SELECT fcm_token, COUNT(*) as count
FROM users
WHERE fcm_token IS NOT NULL
GROUP BY fcm_token
HAVING COUNT(*) > 1;
```

## 🚨 If Issues Persist

1. **Clear all existing tokens**
   ```sql
   UPDATE users SET fcm_token = NULL;
   ```

2. **Restart app completely** (force close)

3. **Re-login and check logs**

4. **Verify RPC function exists**
   ```sql
   SELECT routine_name 
   FROM information_schema.routines 
   WHERE routine_name = 'update_fcm_token';
   ```

---
**Status:** Ready to test
**Next Step:** Apply database migration, then test sign-out/sign-in flow
