-- ==========================================
-- VERIFY AND FIX CHAT NOTIFICATIONS
-- ==========================================
-- This script will:
-- 1. Show you what triggers currently exist
-- 2. Clean up ALL old triggers
-- 3. Apply the correct v3 logic

-- STEP 1: CHECK CURRENT TRIGGERS
-- Run this first to see what's currently active:
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'chat_messages'
ORDER BY trigger_name;

-- Expected output: Should show you any triggers currently on chat_messages table
-- If you see OLD triggers (v1, v2, or unnamed ones), that's your problem!

-- ==========================================
-- STEP 2: APPLY THE FIX
-- ==========================================

-- 2a. DROP ALL POSSIBLE TRIGGERS ON 'chat_messages'
DROP TRIGGER IF EXISTS on_chat_message_insert ON chat_messages;
DROP TRIGGER IF EXISTS on_chat_message_insert_v2 ON chat_messages;
DROP TRIGGER IF EXISTS on_chat_message_insert_v3 ON chat_messages;
DROP TRIGGER IF EXISTS notify_chat_message ON chat_messages;
DROP TRIGGER IF EXISTS send_chat_notification ON chat_messages;
DROP TRIGGER IF EXISTS chat_notification_trigger ON chat_messages;
DROP TRIGGER IF EXISTS tr_chat_notification ON chat_messages;
DROP TRIGGER IF EXISTS on_new_message ON chat_messages;
DROP TRIGGER IF EXISTS notify_provider_on_chat ON chat_messages;

-- 2b. Ensure notifications table has necessary columns
DO $$
BEGIN
    -- Add 'title' column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'notifications' AND column_name = 'title') THEN
        ALTER TABLE notifications ADD COLUMN title TEXT;
    END IF;

    -- Add 'type' column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'notifications' AND column_name = 'type') THEN
        ALTER TABLE notifications ADD COLUMN type TEXT DEFAULT 'general';
    END IF;
    
    -- Add 'order_id' column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'notifications' AND column_name = 'order_id') THEN
        ALTER TABLE notifications ADD COLUMN order_id UUID REFERENCES orders(id);
    END IF;
END $$;

-- 2c. CREATE THE CORRECT NOTIFICATION FUNCTION
CREATE OR REPLACE FUNCTION notify_chat_message_v3()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id UUID;
    v_customer_id UUID; 
    v_provider_id UUID; 
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_receiver_role TEXT;
    v_msg_content TEXT;
BEGIN
    -- A. Resolve Order ID
    BEGIN
        SELECT order_id INTO v_order_id
        FROM chat_sessions
        WHERE id = NEW.session_id;
    EXCEPTION WHEN OTHERS THEN
        RETURN NEW;
    END;

    IF v_order_id IS NULL THEN RETURN NEW; END IF;

    -- B. Resolve Participants
    SELECT buyer_id, provider_id INTO v_customer_id, v_provider_id
    FROM orders
    WHERE id = v_order_id;
    
    IF v_customer_id IS NULL OR v_provider_id IS NULL THEN RETURN NEW; END IF;

    -- C. Identify Sender & Receiver (THE CRITICAL LOGIC)
    IF NEW.sender_id = v_provider_id THEN
        -- Provider sent the message → User should receive notification
        v_receiver_id := v_customer_id;
        v_receiver_role := 'user';
    ELSIF NEW.sender_id = v_customer_id THEN
        -- User sent the message → Provider should receive notification
        v_receiver_id := v_provider_id;
        v_receiver_role := 'provider';
    ELSE
        RETURN NEW; -- System/Admin message - no notification
    END IF;

    -- D. Get Sender Name
    SELECT full_name INTO v_sender_name FROM users WHERE id = NEW.sender_id;
    IF v_sender_name IS NULL OR v_sender_name = '' THEN 
        v_sender_name := 'New Message'; 
    END IF;

    -- E. Format message content
    v_msg_content := SUBSTRING(NEW.message FROM 1 FOR 150);
    IF LENGTH(NEW.message) > 150 THEN v_msg_content := v_msg_content || '...'; END IF;

    -- F. Insert Notification to the RECEIVER (not sender!)
    INSERT INTO notifications (
        user_id,        -- This is the RECEIVER
        order_id, 
        title,          -- Sender Name as Title
        message,        -- Message Content as Body
        type, 
        created_at,
        is_read
    )
    VALUES (
        v_receiver_id,  -- RECEIVER gets the notification
        v_order_id,
        v_sender_name,  -- Title = "John Doe"
        v_msg_content,  -- Body = "Hello, when can you come?"
        'chat_message',
        NOW(),
        FALSE
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2d. APPLY THE CORRECT TRIGGER
CREATE TRIGGER on_chat_message_insert_v3
AFTER INSERT ON chat_messages
FOR EACH ROW
EXECUTE FUNCTION notify_chat_message_v3();

-- ==========================================
-- STEP 3: VERIFY THE FIX
-- ==========================================
-- Run this again to confirm only v3 trigger exists:
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'chat_messages'
ORDER BY trigger_name;

-- Expected output: Should show ONLY "on_chat_message_insert_v3"
