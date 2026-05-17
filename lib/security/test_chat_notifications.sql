-- ==========================================
-- COMPREHENSIVE CHAT NOTIFICATION TEST
-- ==========================================

/*
TESTING PROCEDURE:
1. Find a real order in your database (or create one for testing)
2. Send a message from the PROVIDER to the USER
3. Run these queries to see what happened
4. Share the results with me
*/

-- ==========================================
-- STEP 1: Get Test Order Info
-- ==========================================
-- Find an order with both user and provider for testing
SELECT 
    o.id as order_id,
    o.buyer_id as customer_id,
    u_customer.full_name as customer_name,
    u_customer.is_provider as customer_is_provider,
    o.provider_id,
    u_provider.full_name as provider_name,
    u_provider.is_provider as provider_is_provider,
    o.status
FROM orders o
LEFT JOIN users u_customer ON u_customer.id = o.buyer_id
LEFT JOIN users u_provider ON u_provider.id = o.provider_id
WHERE o.status = 'approved'
LIMIT 5;

-- Copy an order_id from above, then replace 'YOUR_ORDER_ID_HERE' below

-- ==========================================
-- STEP 2: After sending a test message, check what happened
-- ==========================================

-- 2A. Show the latest chat message
SELECT 
    cm.id,
    cm.message,
    cm.sender_id,
    sender.full_name as sender_name,
    sender.is_provider as sender_is_provider,
    cm.session_id,
    cm.created_at
FROM chat_messages cm
LEFT JOIN users sender ON sender.id = cm.sender_id
ORDER BY cm.created_at DESC
LIMIT 1;

-- 2B. Show the latest notification created
SELECT 
    n.id,
    n.user_id as notification_receiver_id,
    receiver.full_name as receiver_name,
    receiver.is_provider as receiver_is_provider,
    n.title,
    n.message,
    n.type,
    n.order_id,
    n.created_at
FROM notifications n
LEFT JOIN users receiver ON receiver.id = n.user_id
WHERE n.type = 'chat_message'
ORDER BY n.created_at DESC
LIMIT 1;

-- ==========================================
-- STEP 3: Verify Push Notification Sent to Correct Person
-- ==========================================

-- This shows if FCM tokens exist for the notification receiver
SELECT 
    n.id as notification_id,
    n.user_id as should_notify_user_id,
    receiver.full_name as should_notify_user_name,
    receiver.is_provider as should_notify_is_provider,
    COUNT(t.fcm_token) as active_fcm_tokens
FROM notifications n
LEFT JOIN users receiver ON receiver.id = n.user_id
LEFT JOIN user_fcm_tokens t ON t.user_id = n.user_id AND t.is_active = true
WHERE n.type = 'chat_message'
GROUP BY n.id, n.user_id, receiver.full_name, receiver.is_provider
ORDER BY n.created_at DESC
LIMIT 5;

-- ==========================================
-- EXPECTED RESULTS IF WORKING CORRECTLY:
-- ==========================================
/*
If PROVIDER sends a message:
- Step 2A should show: sender_is_provider = true
- Step 2B should show: receiver_is_provider = false (the customer/buyer!)
- Step 3 should show: should_notify_is_provider = false with active_fcm_tokens > 0

If USER (customer) sends a message:
- Step 2A should show: sender_is_provider = false
- Step 2B should show: receiver_is_provider = true (the provider!)
- Step 3 should show: should_notify_is_provider = true with active_fcm_tokens > 0

ISSUE SCENARIOS:
A) If Step 2B shows receiver = sender: Trigger logic is WRONG ❌
B) If Step 2B is correct but push goes to wrong person: FCM token issue ❌
C) If Step 3 shows 0 tokens: User hasn't registered FCM token (won't get push) ⚠️
*/
