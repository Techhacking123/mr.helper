# FCM Token Session Management Fix

## Problem Description

When users sign out and another user signs in on the same device, push notifications were being sent to the wrong user. This happened because:

1. **Device FCM token stays the same** - Firebase Cloud Messaging tokens are tied to the device/app installation, not the user
2. **No token cleanup on logout** - When a user signed out, their FCM token remained in the database
3. **Token collision** - When a new user logged in, the FCM token was updated, but notifications might still reference old data

### Example Scenario

1. Provider logs in → FCM token `ABC123` saved with Provider's user ID
2. Provider signs out → Token `ABC123` still in database for Provider
3. User logs in (same device) → Token `ABC123` updated to User's ID
4. Notification sent → Due to timing or cached data, notification goes to wrong account

## Solution

### 1. Clear FCM Token on Sign Out ✅

**File:** `lib/firebase/fcm_service.dart`

Added `clearTokenForCurrentUser()` method that:
- Removes FCM token from database when user signs out
- Clears local token reference
- Uses RPC with fallback for reliability

```dart
static Future<void> clearTokenForCurrentUser() async {
  final userId = await SessionManager.getUserId();
  if (userId == null) return;
  
  // Clear from database via RPC
  await SupabaseConfig.supabase.rpc(
    'update_fcm_token',
    params: {'p_user_id': userId, 'p_token': null},
  );
  
  // Clear local reference
  _fcmToken = null;
}
```

### 2. Update Session Manager ✅

**File:** `lib/auth/session_manager.dart`

Modified `clearSession()` to call `FCMService.clearTokenForCurrentUser()` before clearing session data:

```dart
static Future<void> clearSession() async {
  // IMPORTANT: Clear FCM token BEFORE clearing session
  await FCMService.clearTokenForCurrentUser();
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(keyUserId);
  // ... rest of the cleanup
}
```

### 3. Enforce Token Uniqueness in Database ✅

**File:** `.agent/migrations/fix_fcm_token_uniqueness.sql`

Updated the `update_fcm_token` RPC function to:
- Clear the token from any other user before assigning it
- Handle NULL tokens (for sign out)
- Ensure one device = one user at a time

```sql
CREATE OR REPLACE FUNCTION update_fcm_token(p_user_id UUID, p_token TEXT)
RETURNS void AS $$
BEGIN
  -- Clear token from any other user first
  UPDATE users
  SET fcm_token = NULL
  WHERE fcm_token = p_token AND id != p_user_id;
  
  -- Then assign to current user
  UPDATE users
  SET fcm_token = p_token
  WHERE id = p_user_id;
END;
$$;
```

## Testing Instructions

### Test Case 1: Provider → User Switch

1. **Login as Provider**
   - Login with provider account
   - Check terminal logs: "FCM token saved to database"
   - Note the token value

2. **Sign Out Provider**
   - Click "Sign Out" in profile page
   - Check terminal logs: "Clearing FCM Token for user [provider-id]"
   - Check terminal logs: "FCM token cleared via RPC"

3. **Login as User**
   - Login with user account
   - Check terminal logs: "FCM token saved to database"
   - Verify same token is now assigned to user

4. **Create Order (from User account)**
   - Create a new service request
   - Verify notification goes to PROVIDER, not User

5. **Check Provider's Notifications**
   - Sign out User, login as Provider
   - Verify provider receives the notification

### Test Case 2: User → Provider Switch

1. Login as User
2. Sign Out
3. Login as Provider
4. Have admin/another user create an order request
5. Verify notification goes to Provider ONLY

### Test Case 3: Multiple Sign Outs/Sign Ins

1. Login → Sign Out → Login → Sign Out (repeat 3-4 times)
2. Check database: `SELECT id, full_name, fcm_token FROM users WHERE fcm_token IS NOT NULL;`
3. Verify only ONE user has the device's FCM token

## Database Migration

Run this SQL in Supabase SQL Editor:

```sql
-- Copy contents of .agent/migrations/fix_fcm_token_uniqueness.sql
```

Or use the Supabase CLI:
```bash
supabase db push
```

## Verification Queries

### Check Current FCM Tokens
```sql
SELECT 
  id,
  full_name,
  role,
  fcm_token,
  updated_at
FROM users
WHERE fcm_token IS NOT NULL
ORDER BY updated_at DESC;
```

### Find Duplicate Tokens (Should return 0 rows after fix)
```sql
SELECT 
  fcm_token,
  COUNT(*) as user_count,
  STRING_AGG(full_name, ', ') as users
FROM users
WHERE fcm_token IS NOT NULL
GROUP BY fcm_token
HAVING COUNT(*) > 1;
```

## Expected Behavior After Fix

1. ✅ **On Sign Out:** FCM token is cleared from database
2. ✅ **On Sign In:** FCM token is assigned to new user (and cleared from old user if exists)
3. ✅ **Notifications:** Only sent to the currently logged-in user on each device
4. ✅ **No Cross-User Leakage:** Provider notifications don't go to users and vice versa

## Potential Issues & Troubleshooting

### Issue: "RPC clear failed" in logs
**Solution:** Run the database migration to update the `update_fcm_token` function

### Issue: Still receiving wrong notifications
**Solution:** 
1. Check logs for FCM token values
2. Run duplicate tokens query
3. Manually clear all tokens: `UPDATE users SET fcm_token = NULL;`
4. Re-login and test

### Issue: No notifications at all
**Solution:**
1. Check notification permissions in Android settings
2. Verify FCM token is being saved: Check logs for "FCM token saved"
3. Test with a direct notification from Firebase Console

## Code Changes Summary

| File | Change | Purpose |
|------|--------|---------|
| `fcm_service.dart` | Added `clearTokenForCurrentUser()` | Clear token on logout |
| `session_manager.dart` | Updated `clearSession()` | Call FCM clear before session clear |
| `fix_fcm_token_uniqueness.sql` | Updated `update_fcm_token()` RPC | Enforce token uniqueness |

## Related Files

- `lib/firebase/fcm_service.dart` - FCM token management
- `lib/auth/session_manager.dart` - Session lifecycle
- `lib/auth/login.dart` - Saves token on login
- `lib/profile/profile_page.dart` - Sign out handler
- `supabase/migrations/20241225231000_add_fcm_rpc.sql` - Original RPC function

## Additional Security Measures

Consider implementing these additional safeguards:

1. **Token Expiration:** Add a `fcm_token_updated_at` timestamp and ignore tokens older than 30 days
2. **Notification Validation:** Always verify the notification's target user matches the recipient
3. **Audit Logging:** Log all FCM token changes for debugging
4. **Rate Limiting:** Prevent rapid sign-in/sign-out abuse

---

**Last Updated:** 2026-01-01  
**Status:** ✅ FIXED  
**Priority:** CRITICAL
