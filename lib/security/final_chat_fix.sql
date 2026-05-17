-- FIX CHAT DUPLICATE NOTIFICATIONS (ROOT CAUSE ANALYSIS & FIX)
-- ============================================================
-- Root Cause:
-- The user is receiving two notifications:
-- 1. One with Title = "Sender Name" and Body = "Message content"
-- 2. One with Title = "New Message" (or similar generic title)
--
-- This confirms there are TWO sources triggering notifications:
-- Source A: Our custom trigger 'on_chat_message_insert_v3' (which sends the correct "Sender Name" title).
-- Source B: ANOTHER hidden trigger or conflicting RPC function causing the second generic one.
--
-- A common culprit is a trigger named 'on_chat_message_created' or logic inside 'send_chat_message' RPC.
--
-- FIX STRATEGY:
-- 1. Aggressively find and DROP ALL triggers on 'chat_messages' table.
-- 2. Check and clean up the 'send_chat_message' RPC to ensure it does NOT insert into notifications manually.
-- 3. Re-apply ONLY our single, correct trigger logic.

-- STEP 1: DROP ALL KNOWN AND UNKNOWN TRIGGER NAMES
DROP TRIGGER IF EXISTS on_chat_message_insert ON chat_messages;
DROP TRIGGER IF EXISTS on_chat_message_insert_v2 ON chat_messages;
DROP TRIGGER IF EXISTS on_chat_message_insert_v3 ON chat_messages;
DROP TRIGGER IF EXISTS notify_chat_message ON chat_messages;
DROP TRIGGER IF EXISTS send_chat_notification ON chat_messages;
DROP TRIGGER IF EXISTS chat_notification_trigger ON chat_messages;
DROP TRIGGER IF EXISTS tr_chat_notification ON chat_messages;
DROP TRIGGER IF EXISTS on_new_message ON chat_messages;
DROP TRIGGER IF EXISTS notify_provider_on_chat ON chat_messages;
DROP TRIGGER IF EXISTS on_message_created ON chat_messages; -- Common automated name
DROP TRIGGER IF EXISTS "notify_chat_message" ON chat_messages; -- Quoted variant

-- STEP 2: INSPECT/FIX RPC (send_chat_message)
-- We strictly redefine the RPC to ONLY insert the message. 
-- We REMOVE any notification logic from inside the RPC to rely solely on the Trigger.
DROP FUNCTION IF EXISTS send_chat_message(uuid, uuid, text, uuid);

CREATE OR REPLACE FUNCTION send_chat_message(
    p_session_id UUID,
    p_order_id UUID,
    p_message TEXT,
    p_sender_id UUID
)
RETURNS VOID AS $$
BEGIN
    -- 1. Insert the message (Include order_id explicitly)
    INSERT INTO chat_messages (session_id, sender_id, message, order_id)
    VALUES (p_session_id, p_sender_id, p_message, p_order_id);
    
    -- DO NOT insert into notifications here. The trigger will handle it.
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- STEP 3: RE-APPLY THE CORRECT TRIGGER FUNCTION (Single Point of Truth)
CREATE OR REPLACE FUNCTION notify_chat_message_final()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id UUID;
    v_customer_id UUID; 
    v_provider_id UUID; 
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_msg_content TEXT;
BEGIN
    -- A. Resolve Order ID
    SELECT order_id INTO v_order_id FROM chat_sessions WHERE id = NEW.session_id;
    IF v_order_id IS NULL THEN RETURN NEW; END IF;

    -- B. Resolve Participants
    SELECT buyer_id, provider_id INTO v_customer_id, v_provider_id FROM orders WHERE id = v_order_id;
    IF v_customer_id IS NULL OR v_provider_id IS NULL THEN RETURN NEW; END IF;

    -- C. Identify Receiver
    IF NEW.sender_id = v_provider_id THEN
        v_receiver_id := v_customer_id;
    ELSIF NEW.sender_id = v_customer_id THEN
        v_receiver_id := v_provider_id;
    ELSE
        RETURN NEW; 
    END IF;

    -- D. Get Sender Name
    SELECT full_name INTO v_sender_name FROM users WHERE id = NEW.sender_id;
    IF v_sender_name IS NULL OR v_sender_name = '' THEN 
        v_sender_name := 'New Message'; 
    END IF;

    -- E. Formatting
    v_msg_content := SUBSTRING(NEW.message FROM 1 FOR 150);
    
    -- F. Insert Notification (IDEMPOTENCY CHECK)
    -- Check if a notification for this exact message content was created in the last 2 seconds
    IF NOT EXISTS (
        SELECT 1 FROM notifications 
        WHERE user_id = v_receiver_id 
        AND type = 'chat_message'
        AND message = v_msg_content 
        AND created_at > NOW() - INTERVAL '2 seconds'
    ) THEN
        INSERT INTO notifications (
            user_id, 
            order_id, 
            title,          
            message,        
            type, 
            created_at,
            is_read
        ) VALUES (
            v_receiver_id,
            v_order_id,
            v_sender_name,  -- Title = Sender Name
            v_msg_content,  -- Body = Message Content
            'chat_message',
            NOW(),
            FALSE
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- STEP 4: CREATE THE TRIGGER
DROP TRIGGER IF EXISTS on_chat_message_insert_final ON chat_messages;

CREATE TRIGGER on_chat_message_insert_final
AFTER INSERT ON chat_messages
FOR EACH ROW
EXECUTE FUNCTION notify_chat_message_final();
