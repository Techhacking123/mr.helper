-- ============================================
-- CHAT SYSTEM FIX - Column Name + RLS Fix
-- ============================================
-- This fixes two issues:
-- 1. Uses buyer_id instead of user_id
-- 2. Adds SECURITY DEFINER to bypass RLS in triggers
-- Run this if you already executed the original migration
-- ============================================

-- Fix the create_chat_session_on_approval function
CREATE OR REPLACE FUNCTION create_chat_session_on_approval()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only create chat session when order is accepted/confirmed/verified
  IF NEW.status IN ('accepted', 'confirmed', 'verified') AND 
     (OLD.status IS NULL OR OLD.status NOT IN ('accepted', 'confirmed', 'verified')) THEN
    
    -- Check if session already exists
    IF NOT EXISTS (
      SELECT 1 FROM chat_sessions WHERE order_id = NEW.id
    ) THEN
      -- Create chat session (orders table uses buyer_id, not user_id)
      INSERT INTO chat_sessions (order_id, user_id, provider_id, is_active)
      VALUES (NEW.id, NEW.buyer_id, NEW.provider_id, true);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fix the cleanup function
CREATE OR REPLACE FUNCTION cleanup_chat_on_order_closure()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When order is completed or cancelled, delete all chat data
  IF NEW.status IN ('completed', 'cancelled', 'expired') AND 
     (OLD.status IS NULL OR OLD.status NOT IN ('completed', 'cancelled', 'expired')) THEN
    
    -- Delete all messages (cascade will handle this, but being explicit)
    DELETE FROM chat_messages WHERE order_id = NEW.id;
    
    -- Delete chat session
    DELETE FROM chat_sessions WHERE order_id = NEW.id;
    
    -- Log the cleanup for debugging
    RAISE NOTICE 'Chat cleaned up for order: %', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fix the get_or_create_chat_session RPC function
CREATE OR REPLACE FUNCTION get_or_create_chat_session(p_order_id UUID)
RETURNS TABLE (
  session_id UUID,
  order_id UUID,
  user_id UUID,
  provider_id UUID,
  is_active BOOLEAN,
  created_at TIMESTAMPTZ
) AS $$
DECLARE
  v_session_id UUID;
  v_user_id UUID;
  v_provider_id UUID;
  v_order_status TEXT;
BEGIN
  -- Get order details (orders table uses buyer_id, not user_id)
  SELECT o.buyer_id, o.provider_id, o.status
  INTO v_user_id, v_provider_id, v_order_status
  FROM orders o
  WHERE o.id = p_order_id;
  
  -- Check if caller is authorized (user or provider)
  IF auth.uid() != v_user_id AND auth.uid() != v_provider_id THEN
    RAISE EXCEPTION 'Unauthorized access to chat';
  END IF;
  
  -- Check if order is in valid status for chat
  IF v_order_status NOT IN ('accepted', 'confirmed', 'verified', 'working') THEN
    RAISE EXCEPTION 'Chat not available for order status: %', v_order_status;
  END IF;
  
  -- Get or create session
  SELECT cs.id INTO v_session_id
  FROM chat_sessions cs
  WHERE cs.order_id = p_order_id;
  
  IF v_session_id IS NULL THEN
    INSERT INTO chat_sessions (order_id, user_id, provider_id)
    VALUES (p_order_id, v_user_id, v_provider_id)
    RETURNING id INTO v_session_id;
  END IF;
  
  -- Return session details
  RETURN QUERY
  SELECT cs.id, cs.order_id, cs.user_id, cs.provider_id, cs.is_active, cs.created_at
  FROM chat_sessions cs
  WHERE cs.id = v_session_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fix the send_chat_message function to properly handle sender_id
-- NO SECURITY DEFINER - must run with user context to preserve auth.uid()
CREATE OR REPLACE FUNCTION send_chat_message(
  p_session_id UUID,
  p_order_id UUID,
  p_message TEXT
)
RETURNS UUID AS $$
DECLARE
  v_message_id UUID;
  v_user_id UUID;
  v_provider_id UUID;
  v_receiver_id UUID;
  v_sender_id UUID;
BEGIN
  -- Get the authenticated user ID
  v_sender_id := auth.uid();
  
  -- Verify user is authenticated
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'User not authenticated';
  END IF;
  
  -- Get session details
  SELECT cs.user_id, cs.provider_id
  INTO v_user_id, v_provider_id
  FROM chat_sessions cs
  WHERE cs.id = p_session_id;
  
  -- Check if session exists
  IF v_user_id IS NULL OR v_provider_id IS NULL THEN
    RAISE EXCEPTION 'Chat session not found';
  END IF;
  
  -- Verify caller is authorized
  IF v_sender_id != v_user_id AND v_sender_id != v_provider_id THEN
    RAISE EXCEPTION 'Unauthorized to send message';
  END IF;
  
  -- Insert message with explicit sender_id
  INSERT INTO chat_messages (session_id, order_id, sender_id, message)
  VALUES (p_session_id, p_order_id, v_sender_id, p_message)
  RETURNING id INTO v_message_id;
  
  -- Determine receiver
  IF v_sender_id = v_user_id THEN
    v_receiver_id := v_provider_id;
  ELSE
    v_receiver_id := v_user_id;
  END IF;
  
  -- Send notification to receiver
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
    -- Notification failed but message was sent - don't block
    RAISE WARNING 'Failed to send notification: %', SQLERRM;
  END;
  
  RETURN v_message_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VERIFICATION
-- ============================================

-- Test the fix by checking if functions were updated
SELECT 
  'Functions updated successfully!' as status,
  proname as function_name,
  pg_get_functiondef(oid)::text LIKE '%buyer_id%' as uses_buyer_id
FROM pg_proc
WHERE proname IN ('create_chat_session_on_approval', 'get_or_create_chat_session')
  AND pronamespace = 'public'::regnamespace;

-- ============================================
-- END OF FIX
-- ============================================
