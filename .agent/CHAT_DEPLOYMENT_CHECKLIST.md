# Chat Feature Implementation - Step-by-Step Checklist

## ✅ Code Implementation (COMPLETED)

- [x] Created database migration file (`order_chat_system.sql`)
  - [x] `chat_sessions` table with proper foreign keys
  - [x] `chat_messages` table with cascade delete
  - [x] Trigger for auto-creation on approval
  - [x] Trigger for auto-deletion on completion/cancellation
  - [x] RLS policies for security
  - [x] RPC functions (get_or_create, send_message, mark_read)
  - [x] Realtime subscriptions enabled

- [x] Created chat UI component (`order_chat_page.dart`)
  - [x] Real-time message display
  - [x] Message sending functionality
  - [x] Modern chat bubble design
  - [x] Timestamp formatting
  - [x] Auto-scroll to latest
  - [x] Error handling
  - [x] Empty states

- [x] Integrated chat into Order Details page
  - [x] Added import for chat page
  - [x] Added Chat button for providers
  - [x] Added Chat button for users
  - [x] Conditional rendering based on order status
  - [x] Navigation to chat page

- [x] Created documentation
  - [x] ORDER_CHAT_SYSTEM.md (detailed guide)
  - [x] CHAT_FEATURE_SUMMARY.md (visual summary)
  - [x] This checklist file

- [x] Code quality
  - [x] Flutter analyzer warnings fixed
  - [x] No compilation errors
  - [x] Clean code structure

## 📋 Deployment Checklist (TODO - User Action Required)

### Step 1: Database Migration
- [ ] Open Supabase Dashboard
- [ ] Navigate to SQL Editor
- [ ] Copy contents of `.agent/migrations/order_chat_system.sql`
- [ ] Paste in SQL Editor
- [ ] Click "Run" to execute migration
- [ ] Verify no errors in output

### Step 2: Verify Database Objects Created
Run these verification queries in Supabase SQL Editor:

```sql
-- Check tables exist
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('chat_sessions', 'chat_messages');
-- Expected: 2 rows

-- Check RLS is enabled
SELECT tablename, rowsecurity FROM pg_tables 
WHERE tablename IN ('chat_sessions', 'chat_messages');
-- Expected: Both should show rowsecurity = true

-- Check triggers exist
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE trigger_name LIKE '%chat%';
-- Expected: 2 triggers (create and cleanup)

-- Check RPC functions exist
SELECT proname FROM pg_proc 
WHERE proname IN (
  'get_or_create_chat_session',
  'send_chat_message',
  'mark_messages_as_read'
);
-- Expected: 3 functions

-- Check realtime is enabled
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime' 
AND tablename IN ('chat_sessions', 'chat_messages');
-- Expected: 2 rows
```

- [ ] All verification queries return expected results

### Step 3: Test End-to-End Flow

#### Test Case 1: Provider Accepts Order
1. [ ] User creates an order
2. [ ] Provider accepts the order
3. [ ] Verify Chat button appears on Order Details for both user and provider
4. [ ] Verify chat session is created in database:
   ```sql
   SELECT * FROM chat_sessions WHERE order_id = 'YOUR_ORDER_ID';
   ```

#### Test Case 2: Send Messages
1. [ ] Provider clicks Chat button
2. [ ] Provider sends message: "Hello, I'm on my way"
3. [ ] Verify message appears in provider's chat
4. [ ] User clicks Chat button
5. [ ] Verify user sees provider's message
6. [ ] User sends reply: "Great, see you soon!"
7. [ ] Verify provider sees user's reply in real-time
8. [ ] Verify messages in database:
   ```sql
   SELECT sender_id, message, created_at 
   FROM chat_messages 
   WHERE order_id = 'YOUR_ORDER_ID' 
   ORDER BY created_at;
   ```

#### Test Case 3: Notifications
1. [ ] Send a message from user to provider
2. [ ] Verify provider receives notification
3. [ ] Check notification in database:
   ```sql
   SELECT * FROM notifications 
   WHERE type = 'chat_message' 
   AND order_id = 'YOUR_ORDER_ID';
   ```

#### Test Case 4: Complete Order and Verify Cleanup
1. [ ] User marks order as "Service Completed"
2. [ ] Wait 2-3 seconds for trigger to execute
3. [ ] Verify chat session is deleted:
   ```sql
   SELECT * FROM chat_sessions WHERE order_id = 'YOUR_ORDER_ID';
   -- Expected: 0 rows
   ```
4. [ ] Verify all messages are deleted:
   ```sql
   SELECT * FROM chat_messages WHERE order_id = 'YOUR_ORDER_ID';
   -- Expected: 0 rows
   ```
5. [ ] Chat button is no longer accessible (order completed)

#### Test Case 5: Cancel Order and Verify Cleanup
1. [ ] Create new order and get it accepted
2. [ ] Exchange some chat messages
3. [ ] User cancels the order
4. [ ] Verify chat is deleted (same queries as above)

#### Test Case 6: Security Test
1. [ ] Create two different orders
2. [ ] Try to access chat of Order A using Order B's user
3. [ ] Verify: Should see "Chat Not Available" error
4. [ ] Try to send message to wrong session via direct API call
5. [ ] Verify: Should be blocked by RLS policy

### Step 4: Performance Testing
- [ ] Test with 50+ messages in a chat
  - [ ] Verify scroll works smoothly
  - [ ] Verify realtime updates still work
  - [ ] No lag in UI
- [ ] Test with multiple concurrent chats
  - [ ] Create 5 different orders
  - [ ] Open all 5 chats simultaneously
  - [ ] Verify messages go to correct chats
  - [ ] No cross-contamination

### Step 5: Edge Cases
- [ ] Test chat access before approval (should show error)
- [ ] Test chat access after completion (button shouldn't appear)
- [ ] Test sending empty message (should be prevented)
- [ ] Test very long message (200+ characters)
- [ ] Test special characters in messages (emojis, etc.)
- [ ] Test rapid message sending (5 messages in quick succession)
- [ ] Test network disconnect while chatting (should queue and send when reconnected)

## 🐛 Troubleshooting Guide

### Issue: Chat button doesn't appear
**Check:**
- [ ] Order status is accepted/confirmed/verified/working
- [ ] User is either the customer or the provider of that order
- [ ] Order has provider_id assigned

**Fix:**
```dart
// Debug in order_detail.dart around line 1252
debugPrint('Order Status: $status');
debugPrint('IsProvider: $isProvider');
debugPrint('Provider Phone: ${_order['provider']?['phone_number']}');
```

### Issue: "Chat Not Available" error
**Check:**
- [ ] Chat session was created in database
- [ ] RLS policies are correctly applied
- [ ] User is authenticated (check auth.uid())

**Fix:**
```sql
-- Check if session exists
SELECT * FROM chat_sessions WHERE order_id = 'YOUR_ORDER_ID';

-- Check RLS policies
SELECT * FROM pg_policies WHERE tablename = 'chat_sessions';

-- Test RPC function manually
SELECT * FROM get_or_create_chat_session('YOUR_ORDER_ID');
```

### Issue: Messages not appearing in real-time
**Check:**
- [ ] Realtime is enabled in Supabase project settings
- [ ] Realtime subscription is active (check browser console)
- [ ] Messages are being inserted (check database directly)

**Fix:**
```dart
// Add debug in order_chat_page.dart _setupRealtimeSubscription
.onPostgresChanges(
  callback: (payload) {
    debugPrint('Realtime update: ${payload.newRecord}');
    // ... rest of code
  },
)
```

### Issue: Chat not deleting on completion
**Check:**
- [ ] Triggers are created and enabled
- [ ] Order status is actually changing to 'completed' or 'cancelled'

**Fix:**
```sql
-- Check if triggers exist
SELECT * FROM pg_trigger WHERE tgname LIKE '%chat%';

-- Enable trigger logging
ALTER TABLE orders ENABLE ALWAYS TRIGGER trigger_cleanup_chat_on_closure;

-- Test trigger manually
UPDATE orders SET status = 'completed' WHERE id = 'YOUR_ORDER_ID';
-- Then check if chat was deleted
```

### Issue: Duplicate sessions or messages
**Check:**
- [ ] UNIQUE constraint on order_id in chat_sessions
- [ ] No duplicate triggers

**Fix:**
```sql
-- Check for duplicates
SELECT order_id, COUNT(*) 
FROM chat_sessions 
GROUP BY order_id 
HAVING COUNT(*) > 1;

-- Clean up duplicates (keep only most recent)
DELETE FROM chat_sessions 
WHERE id NOT IN (
  SELECT DISTINCT ON (order_id) id 
  FROM chat_sessions 
  ORDER BY order_id, created_at DESC
);
```

## 📊 Success Metrics

After deployment, verify these metrics:

- [ ] Chat sessions created: Should match number of approved orders
- [ ] Average messages per chat: Monitor engagement
- [ ] Chat deletion rate: Should be 100% on order completion
- [ ] No orphan records: Run cleanup query weekly
- [ ] User adoption: Track how many users click Chat vs Call

```sql
-- Check metrics
-- Total chat sessions (active)
SELECT COUNT(*) FROM chat_sessions WHERE is_active = true;

-- Average messages per session
SELECT AVG(msg_count) FROM (
  SELECT session_id, COUNT(*) as msg_count 
  FROM chat_messages 
  GROUP BY session_id
) subq;

-- Check for orphan sessions (order completed but chat exists)
SELECT cs.* FROM chat_sessions cs
JOIN orders o ON cs.order_id = o.id
WHERE o.status IN ('completed', 'cancelled', 'expired');
-- Expected: 0 rows

-- Check for orphan messages (session doesn't exist)
SELECT cm.* FROM chat_messages cm
LEFT JOIN chat_sessions cs ON cm.session_id = cs.id
WHERE cs.id IS NULL;
-- Expected: 0 rows
```

## 🎯 Final Sign-Off

- [ ] All code files created and reviewed
- [ ] Database migration tested in staging
- [ ] Database migration applied to production
- [ ] All test cases passed
- [ ] No orphan records found
- [ ] Performance is acceptable
- [ ] Documentation is complete
- [ ] Team trained on new feature

## 📝 Notes

**Date Implemented:** _________________

**Deployed By:** _________________

**Production URL:** _________________

**Issues Encountered:** 
_________________________________________________________________
_________________________________________________________________

**Resolution:** 
_________________________________________________________________
_________________________________________________________________

**Sign-off:** _________________ (Name & Date)

---

## Support Contacts

**Technical Issues:** Check ORDER_CHAT_SYSTEM.md  
**Database Questions:** Review SQL migration file  
**UI/UX Feedback:** See CHAT_FEATURE_SUMMARY.md  

---
*End of Checklist*
