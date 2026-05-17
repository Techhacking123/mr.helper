# Chat Error: "User not authenticated"

## Problem

Getting error: `User not authenticated` when trying to send messages

## Root Causes

There are several possible reasons:

### 1. ❌ **User Not Logged In (Most Common)**
The user session has expired or the user is not authenticated.

**Solution:**
- Log out of the app
- Close the app completely
- Reopen and log back in
- Try the chat again

### 2. ❌ **Auth Token Not Passed**
Supabase client might not be sending the auth token with RPC calls.

**Check:**
```dart
// In Flutter debug console, look for:
Chat init: User ID = <some-uuid>
Sending message: User ID = <some-uuid>, Session = <session-id>
```

- If you see "User ID = null" → User is not authenticated
- If RPC fails → Auth token isn't being sent

### 3. ❌ **SQL Function Issue**
The function itself might have issues.

**Test in Supabase SQL Editor:**
```sql
-- Check if you're authenticated
SELECT auth.uid();
-- Should return your user ID, not NULL

-- Test the function
SELECT * FROM send_chat_message(
  '<session-id>'::uuid,
  '<order-id>'::uuid,
  'Test message'
);
```

## Solutions

### Quick Fix #1: Restart App
1. **Force close** the app (don't just minimize)
2. **Reopen** the app
3. **Log in** again
4. Try sending a message

### Quick Fix #2: Check Flutter Auth
Add this to your code temporarily:

```dart
// In order_chat_page.dart, in _sendMessage():
final currentUser = SupabaseConfig.supabase.auth.currentUser;
debugPrint('Current User: ${currentUser?.id}');
debugPrint('Is Authenticated: ${currentUser != null}');
```

Run the app and check terminal output.

### Quick Fix #3: Verify SQL Function
Run in Supabase SQL Editor:

```sql
-- Check function definition
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'send_chat_message';

-- Should NOT have SECURITY DEFINER
-- Should look like:
-- RETURNS uuid
-- AS $$
-- (no SECURITY DEFINER)
```

## Updated Files

I've updated `order_chat_page.dart` with:
- ✅ Authentication check before initializing chat
- ✅ Authentication check before sending messages
- ✅ Better error messages
- ✅ Debug logging

## Next Steps

1. **Hot restart** your app (press 'R' in terminal or restart)
2. Try opening chat again
3. Look at the Flutter debug console for these messages:
   ```
   Chat init: User ID = xxx
   Sending message: User ID = xxx, Session = xxx
   ```

4. If you see "User ID = null", **log out and log back in**

## If Still Not Working

The issue might be with how Supabase auth is initialized. Check:

```dart
// In main.dart or wherever Supabase is initialized
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_ANON_KEY',
);
```

Make sure the user is properly logged in before accessing chat.

---

**Most likely solution: Log out → Close app → Reopen → Log in → Try again**
