-- ==========================================
-- FIX CHAT NOTIFICATIONS (SENDER NAME & DUPLICATES)
-- ==========================================

-- 1. CLEANUP ALL POSSIBLE EXISTING TRIGGERS on chat_messages
-- We must drop any trigger that might be currently sending duplicate/wrong notifications.
DROP TRIGGER IF EXISTS on_chat_message_insert ON chat_messages;
DROP TRIGGER IF EXISTS notify_chat_message ON chat_messages;
DROP TRIGGER IF EXISTS send_chat_notification ON chat_messages;
DROP TRIGGER IF EXISTS chat_notification_trigger ON chat_messages;
DROP TRIGGER IF EXISTS tr_chat_notification ON chat_messages;
DROP TRIGGER IF EXISTS on_new_message ON chat_messages;

-- 2. CREATE ROBUST NOTIFICATION FUNCTION
CREATE OR REPLACE FUNCTION notify_chat_message_v2()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id UUID;
    v_customer_id UUID; -- The user who requested the service
    v_provider_id UUID; -- The provider assigned
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_msg_content TEXT;
BEGIN
    -- A. Resolve Order ID
    -- We assume chat_messages links to chat_sessions via session_id
    BEGIN
        SELECT order_id INTO v_order_id
        FROM chat_sessions
        WHERE session_id = NEW.session_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error fetching order_id for session %', NEW.session_id;
        RETURN NEW;
    END;

    IF v_order_id IS NULL THEN
        -- Fallback: Check if order_id is in chat_messages directly (if schema changed)
        -- IF (NEW ? 'order_id') THEN ... END IF;
        -- For now, assume session link is mandatory.
        RETURN NEW;
    END IF;

    -- B. Resolve Participants from Order
    SELECT user_id, provider_id INTO v_customer_id, v_provider_id
    FROM orders
    WHERE id = v_order_id;
    
    IF v_customer_id IS NULL OR v_provider_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- C. Identify Sender Name
    SELECT full_name INTO v_sender_name FROM users WHERE id = NEW.sender_id;
    IF v_sender_name IS NULL OR v_sender_name = '' THEN 
        v_sender_name := 'User'; 
    END IF;

    -- D. Identify Receiver
    -- If Sender is Provider -> Receiver is Customer
    IF NEW.sender_id = v_provider_id THEN
        v_receiver_id := v_customer_id;
    -- If Sender is Customer -> Receiver is Provider
    ELSIF NEW.sender_id = v_customer_id THEN
        v_receiver_id := v_provider_id;
    ELSE
        -- Sender is neither? (Possibly Admin or System) - Do not notify
        RETURN NEW;
    END IF;

    -- E. Format Message Content
    -- Truncate message for notification body
    v_msg_content := SUBSTRING(NEW.message FROM 1 FOR 100);
    IF LENGTH(NEW.message) > 100 THEN
        v_msg_content := v_msg_content || '...';
    END IF;

    -- F. Insert Notification
    -- This inserts into the notifications table. 
    -- The existing trigger on 'notifications' table (trigger_send_fcm_notification) 
    -- will pick this up and send the Push Notification via Edge Function.
    INSERT INTO notifications (user_id, order_id, message, created_at)
    VALUES (
        v_receiver_id,
        v_order_id,
        'Message from ' || v_sender_name || ': ' || v_msg_content,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. APPLY NEW TRIGGER
CREATE TRIGGER on_chat_message_insert_v2
AFTER INSERT ON chat_messages
FOR EACH ROW
EXECUTE FUNCTION notify_chat_message_v2();
