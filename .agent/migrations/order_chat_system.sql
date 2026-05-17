-- ============================================
-- Order-Based Real-Time Chat System
-- ============================================
-- This migration creates a chat system linked to specific orders:
-- 1. Chat sessions tied to order_id
-- 2. Messages stored with timestamps
-- 3. Automatic cleanup when order is completed/canceled
-- 4. RLS policies to restrict access to approved users only
-- ============================================

-- Drop existing tables if they exist (for clean migration)
DROP TABLE IF EXISTS chat_messages CASCADE;
DROP TABLE IF EXISTS chat_sessions CASCADE;

-- ============================================
-- TABLES
-- ============================================

-- Chat Sessions Table: One session per order
CREATE TABLE chat_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN DEFAULT true,
  UNIQUE(order_id) -- One chat session per order
);

-- Create index for faster lookups
CREATE INDEX idx_chat_sessions_order ON chat_sessions(order_id);
CREATE INDEX idx_chat_sessions_user ON chat_sessions(user_id);
CREATE INDEX idx_chat_sessions_provider ON chat_sessions(provider_id);

-- Chat Messages Table: All messages for a session
CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  is_read BOOLEAN DEFAULT false
);

-- Create index for faster message retrieval
CREATE INDEX idx_chat_messages_session ON chat_messages(session_id, created_at DESC);
CREATE INDEX idx_chat_messages_order ON chat_messages(order_id);
CREATE INDEX idx_chat_messages_sender ON chat_messages(sender_id);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function: Create chat session when provider is approved
-- SECURITY DEFINER allows trigger to bypass RLS when creating sessions
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

-- Function: Automatically delete chat on order completion/cancellation
-- SECURITY DEFINER allows trigger to bypass RLS when cleaning up
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

-- ============================================
-- TRIGGERS
-- ============================================

-- Trigger: Create chat session on provider approval
DROP TRIGGER IF EXISTS trigger_create_chat_on_approval ON orders;
CREATE TRIGGER trigger_create_chat_on_approval
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION create_chat_session_on_approval();

-- Trigger: Cleanup chat on order completion/cancellation
DROP TRIGGER IF EXISTS trigger_cleanup_chat_on_closure ON orders;
CREATE TRIGGER trigger_cleanup_chat_on_closure
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION cleanup_chat_on_order_closure();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS chat_sessions_access_policy ON chat_sessions;
DROP POLICY IF EXISTS chat_messages_access_policy ON chat_messages;
DROP POLICY IF EXISTS chat_messages_insert_policy ON chat_messages;

-- Policy: Only approved user and provider can view their chat session
CREATE POLICY chat_sessions_access_policy ON chat_sessions
  FOR SELECT
  USING (
    auth.uid() = user_id OR auth.uid() = provider_id
  );

-- Policy: Only approved user and provider can view messages
CREATE POLICY chat_messages_access_policy ON chat_messages
  FOR SELECT
  USING (
    session_id IN (
      SELECT id FROM chat_sessions 
      WHERE user_id = auth.uid() OR provider_id = auth.uid()
    )
  );

-- Policy: Only approved user and provider can send messages
CREATE POLICY chat_messages_insert_policy ON chat_messages
  FOR INSERT
  WITH CHECK (
    session_id IN (
      SELECT id FROM chat_sessions 
      WHERE user_id = auth.uid() OR provider_id = auth.uid()
    )
  );

-- Policy: Allow users to update message read status
DROP POLICY IF EXISTS chat_messages_update_policy ON chat_messages;
CREATE POLICY chat_messages_update_policy ON chat_messages
  FOR UPDATE
  USING (
    session_id IN (
      SELECT id FROM chat_sessions 
      WHERE user_id = auth.uid() OR provider_id = auth.uid()
    )
  );

-- ============================================
-- REALTIME PUBLICATION
-- ============================================

-- Enable realtime for chat tables
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE chat_sessions;

-- ============================================
-- RPC FUNCTIONS FOR FRONTEND
-- ============================================

-- Function: Get or create chat session for an order
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

-- Function: Send a chat message
-- NO SECURITY DEFINER - needs to run with user context to get auth.uid()
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
  
  -- Send notification to receiver (with elevated privileges for this operation)
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

-- Function: Mark messages as read
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_session_id UUID)
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE chat_messages
  SET is_read = true
  WHERE session_id = p_session_id
    AND sender_id != auth.uid()
    AND is_read = false;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT ON chat_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON chat_messages TO authenticated;

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION get_or_create_chat_session(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION send_chat_message(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_messages_as_read(UUID) TO authenticated;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE chat_sessions IS 'One chat session per order, created when provider is approved';
COMMENT ON TABLE chat_messages IS 'All messages for a chat session';
COMMENT ON FUNCTION create_chat_session_on_approval() IS 'Automatically creates chat session when provider is approved';
COMMENT ON FUNCTION cleanup_chat_on_order_closure() IS 'Automatically deletes all chat data when order is completed or cancelled';
COMMENT ON FUNCTION get_or_create_chat_session(UUID) IS 'Gets existing or creates new chat session for an order';
COMMENT ON FUNCTION send_chat_message(UUID, UUID, TEXT) IS 'Sends a chat message and notifies the receiver';
COMMENT ON FUNCTION mark_messages_as_read(UUID) IS 'Marks all unread messages in a session as read';

-- ============================================
-- END OF MIGRATION
-- ============================================
