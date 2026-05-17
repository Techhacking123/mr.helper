-- ==========================================
-- FINAL CHAT FIX V3 - CUSTOM AUTH SUPPORT
-- ==========================================
-- Since the app uses manual login (checking users table directly)
-- instead of Supabase Auth, we cannot rely on auth.uid().
-- We must pass the user ID explicitly.

-- 1. Drop existing functions to avoid signature conflicts
DROP FUNCTION IF EXISTS send_chat_message(UUID, UUID, TEXT);

-- 2. Create function that accepts sender_id explicitly
CREATE OR REPLACE FUNCTION send_chat_message(
  p_session_id UUID,
  p_order_id UUID,
  p_message TEXT,
  p_sender_id UUID -- Added parameter
)
RETURNS UUID
SECURITY DEFINER -- Crucial: As we have no auth token (Anon role), we need this to write to tables
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_message_id UUID;
  v_user_id UUID;
  v_provider_id UUID;
  v_receiver_id UUID;
BEGIN
  -- Validate inputs
  IF p_sender_id IS NULL THEN
    RAISE EXCEPTION 'Sender ID is required';
  END IF;

  -- Get session details to verify sender belongs to session
  SELECT user_id, provider_id
  INTO v_user_id, v_provider_id
  FROM chat_sessions
  WHERE id = p_session_id;
  
  -- Verify session exists
  IF v_user_id IS NULL OR v_provider_id IS NULL THEN
    RAISE EXCEPTION 'Chat session not found';
  END IF;
  
  -- Verify the sender is part of this chat session
  IF p_sender_id != v_user_id AND p_sender_id != v_provider_id THEN
    RAISE EXCEPTION 'Unauthorized: User % is not in this chat session', p_sender_id;
  END IF;
  
  -- Insert the message using the passed sender_id
  INSERT INTO chat_messages (session_id, order_id, sender_id, message)
  VALUES (p_session_id, p_order_id, p_sender_id, p_message)
  RETURNING id INTO v_message_id;
  
  -- Determine receiver for notification (User <-> Provider)
  IF p_sender_id = v_user_id THEN
    v_receiver_id := v_provider_id;
  ELSE
    v_receiver_id := v_user_id;
  END IF;
  
  -- Send notification
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
        'sender_id', p_sender_id
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to send notification: %', SQLERRM;
  END;
  
  RETURN v_message_id;
END;
$$;
