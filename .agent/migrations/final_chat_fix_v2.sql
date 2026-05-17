-- ==========================================
-- FINAL CHAT FIX V2
-- This script completely resets the chat sending function
-- to ensure NO Security Definer issues remain.
-- ==========================================

-- 1. Explicitly DROP the function to remove any sticky attributes
DROP FUNCTION IF EXISTS send_chat_message(UUID, UUID, TEXT);

-- 2. Recreate the function WITHOUT 'SECURITY DEFINER'
-- This ensures it runs with the permissions of the caller (the logged-in user)
CREATE OR REPLACE FUNCTION send_chat_message(
  p_session_id UUID,
  p_order_id UUID,
  p_message TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_message_id UUID;
  v_sender_id UUID;
  v_user_id UUID;
  v_provider_id UUID;
  v_receiver_id UUID;
BEGIN
  -- Get the ID of the user calling this function
  v_sender_id := auth.uid();
  
  -- Debug/Safety check
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'User not authenticated (auth.uid() is NULL). Ensure usage of authenticated Supabase client.';
  END IF;
  
  -- Get session details
  SELECT user_id, provider_id
  INTO v_user_id, v_provider_id
  FROM chat_sessions
  WHERE id = p_session_id;
  
  -- Verify session exists
  IF v_user_id IS NULL OR v_provider_id IS NULL THEN
    RAISE EXCEPTION 'Chat session not found';
  END IF;
  
  -- Verify the sender is actually part of this chat session
  IF v_sender_id != v_user_id AND v_sender_id != v_provider_id THEN
    RAISE EXCEPTION 'Unauthorized: User % is not in this chat session', v_sender_id;
  END IF;
  
  -- Insert the message
  INSERT INTO chat_messages (session_id, order_id, sender_id, message)
  VALUES (p_session_id, p_order_id, v_sender_id, p_message)
  RETURNING id INTO v_message_id;
  
  -- Determine receiver for notification
  IF v_sender_id = v_user_id THEN
    v_receiver_id := v_provider_id;
  ELSE
    v_receiver_id := v_user_id;
  END IF;
  
  -- Send notification (safely)
  BEGIN
    INSERT INTO notifications (user_id, order_id, type, title, message, data)
    VALUES (
      v_receiver_id,
      p_order_id,
      'chat_message',
      'New Chat Message',
      LEFT(p_message, 100),
      jsonb_build_object(
        'session_id', p_session_id,
        'sender_id', v_sender_id
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- Log error but don't fail the message send
    RAISE WARNING 'Failed to send notification: %', SQLERRM;
  END;
  
  RETURN v_message_id;
END;
$$;

-- 3. Ensure RLS policies exist for direct insert (backup method)
DROP POLICY IF EXISTS "Users can insert messages in their sessions" ON chat_messages;

CREATE POLICY "Users can insert messages in their sessions"
ON chat_messages
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM chat_sessions
    WHERE chat_sessions.id = chat_messages.session_id
    AND (
      chat_sessions.user_id = auth.uid() 
      OR chat_sessions.provider_id = auth.uid()
    )
  )
);
