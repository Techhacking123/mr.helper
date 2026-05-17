-- ==========================================
-- DEBUG CHAT NOTIFICATIONS
-- ==========================================
-- Run this query AFTER sending a test message to see what happened

-- 1. Check the last 5 chat messages sent
SELECT 
    cm.id as message_id,
    cm.message,
    cm.sender_id,
    cm.created_at,
    u.full_name as sender_name,
    u.user_type as sender_type
FROM chat_messages cm
LEFT JOIN users u ON u.id = cm.sender_id
ORDER BY cm.created_at DESC
LIMIT 5;

-- 2. Check the last 5 notifications created
SELECT 
    n.id as notification_id,
    n.user_id as receiver_id,
    n.title,
    n.message,
    n.type,
    n.created_at,
    u.full_name as receiver_name,
    u.user_type as receiver_type
FROM notifications n
LEFT JOIN users u ON u.id = n.user_id
WHERE n.type = 'chat_message'
ORDER BY n.created_at DESC
LIMIT 5;

-- 3. Cross-reference: Show who sent the message vs who received the notification
SELECT 
    cm.id as message_id,
    cm.message as chat_message,
    cm.created_at as message_time,
    sender.full_name as sender_name,
    sender.user_type as sender_type,
    o.buyer_id as order_buyer_id,
    o.provider_id as order_provider_id,
    receiver.full_name as notification_receiver_name,
    receiver.user_type as notification_receiver_type,
    n.title as notification_title,
    n.message as notification_body
FROM chat_messages cm
LEFT JOIN users sender ON sender.id = cm.sender_id
LEFT JOIN chat_sessions cs ON cs.session_id = cm.session_id
LEFT JOIN orders o ON o.id = cs.order_id
LEFT JOIN notifications n ON n.order_id = o.id 
    AND n.created_at BETWEEN cm.created_at - INTERVAL '5 seconds' AND cm.created_at + INTERVAL '5 seconds'
    AND n.type = 'chat_message'
LEFT JOIN users receiver ON receiver.id = n.user_id
WHERE cm.created_at > NOW() - INTERVAL '1 hour'
ORDER BY cm.created_at DESC
LIMIT 10;

-- ==========================================
-- TESTING INSTRUCTIONS
-- ==========================================
/*
1. Send a test message from PROVIDER to USER in your app
2. Run the queries above
3. Check if:
   - Query 1 shows the provider as the sender ✅
   - Query 2 shows the USER as the receiver (not provider) ✅
   - Query 3 shows sender ≠ receiver ✅
   
If Query 2 shows the PROVIDER receiving their own notification,
then we have a different issue (possibly in the Dart/Flutter code).
*/
