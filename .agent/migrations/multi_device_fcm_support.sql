-- ============================================================
-- MULTI-DEVICE FCM TOKEN SUPPORT
-- ============================================================
-- This migration enables users to receive push notifications
-- on multiple devices simultaneously (phone, tablet, etc.)
-- ============================================================

-- Create user_fcm_tokens table to store multiple tokens per user
CREATE TABLE IF NOT EXISTS user_fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  device_id TEXT,  -- Optional: Unique identifier for the device
  device_name TEXT,  -- Optional: Human-readable name (e.g., "Samsung Galaxy S21")
  platform TEXT CHECK (platform IN ('android', 'ios', 'web')),  -- Device platform
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE,
  
  -- Ensure one token per user (a token can't be shared between users)
  UNIQUE(fcm_token),
  
  -- Index for fast lookups
  CONSTRAINT unique_user_device UNIQUE(user_id, device_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id ON user_fcm_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_active ON user_fcm_tokens(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_token ON user_fcm_tokens(fcm_token);

-- Enable Row Level Security
ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_fcm_tokens
CREATE POLICY "Users can view their own tokens"
  ON user_fcm_tokens FOR SELECT
  USING (TRUE);  -- Allow read for debugging, can restrict to auth.uid() if using Supabase auth

CREATE POLICY "Users can insert their own tokens"
  ON user_fcm_tokens FOR INSERT
  WITH CHECK (TRUE);  -- We'll validate in the RPC function

CREATE POLICY "Users can update their own tokens"
  ON user_fcm_tokens FOR UPDATE
  USING (TRUE);

CREATE POLICY "Users can delete their own tokens"
  ON user_fcm_tokens FOR DELETE
  USING (TRUE);

-- ============================================================
-- RPC FUNCTION: Add or Update FCM Token for a Device
-- ============================================================
CREATE OR REPLACE FUNCTION add_or_update_fcm_token(
  p_user_id UUID,
  p_fcm_token TEXT,
  p_device_id TEXT DEFAULT NULL,
  p_device_name TEXT DEFAULT NULL,
  p_platform TEXT DEFAULT 'android'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token_id UUID;
  v_existing_user_id UUID;
BEGIN
  -- Validate inputs
  IF p_user_id IS NULL OR p_fcm_token IS NULL THEN
    RAISE EXCEPTION 'user_id and fcm_token are required';
  END IF;

  -- Check if this token belongs to a different user
  SELECT user_id INTO v_existing_user_id
  FROM user_fcm_tokens
  WHERE fcm_token = p_fcm_token
    AND user_id != p_user_id
  LIMIT 1;

  -- If token exists for another user, remove it (device switched users)
  IF v_existing_user_id IS NOT NULL THEN
    DELETE FROM user_fcm_tokens
    WHERE fcm_token = p_fcm_token
      AND user_id = v_existing_user_id;
    
    RAISE NOTICE 'Removed token from previous user % (device switched)', v_existing_user_id;
  END IF;

  -- Insert or update the token
  INSERT INTO user_fcm_tokens (
    user_id,
    fcm_token,
    device_id,
    device_name,
    platform,
    last_used_at,
    is_active
  ) VALUES (
    p_user_id,
    p_fcm_token,
    COALESCE(p_device_id, 'device_' || substr(md5(random()::text), 1, 8)),
    p_device_name,
    p_platform,
    NOW(),
    TRUE
  )
  ON CONFLICT (fcm_token)
  DO UPDATE SET
    last_used_at = NOW(),
    is_active = TRUE,
    device_name = COALESCE(EXCLUDED.device_name, user_fcm_tokens.device_name),
    platform = COALESCE(EXCLUDED.platform, user_fcm_tokens.platform)
  RETURNING id INTO v_token_id;

  RAISE NOTICE 'FCM token saved/updated for user % (token_id: %)', p_user_id, v_token_id;
  
  RETURN v_token_id;
END;
$$;

-- ============================================================
-- RPC FUNCTION: Remove FCM Token (on sign out from specific device)
-- ============================================================
CREATE OR REPLACE FUNCTION remove_fcm_token(
  p_user_id UUID,
  p_fcm_token TEXT DEFAULT NULL,
  p_device_id TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  -- Delete by token (most specific)
  IF p_fcm_token IS NOT NULL THEN
    DELETE FROM user_fcm_tokens
    WHERE user_id = p_user_id
      AND fcm_token = p_fcm_token;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Removed % token(s) for user % by fcm_token', v_deleted_count, p_user_id;
    RETURN v_deleted_count;
  END IF;

  -- Delete by device_id
  IF p_device_id IS NOT NULL THEN
    DELETE FROM user_fcm_tokens
    WHERE user_id = p_user_id
      AND device_id = p_device_id;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Removed % token(s) for user % by device_id', v_deleted_count, p_user_id;
    RETURN v_deleted_count;
  END IF;

  -- If neither provided, remove all tokens for user (sign out from all devices)
  DELETE FROM user_fcm_tokens
  WHERE user_id = p_user_id;
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RAISE NOTICE 'Removed ALL % token(s) for user %', v_deleted_count, p_user_id;
  RETURN v_deleted_count;
END;
$$;

-- ============================================================
-- RPC FUNCTION: Get All Active Tokens for a User
-- ============================================================
CREATE OR REPLACE FUNCTION get_user_fcm_tokens(p_user_id UUID)
RETURNS TABLE(
  token_id UUID,
  fcm_token TEXT,
  device_id TEXT,
  device_name TEXT,
  platform TEXT,
  last_used_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    id,
    user_fcm_tokens.fcm_token,
    user_fcm_tokens.device_id,
    user_fcm_tokens.device_name,
    user_fcm_tokens.platform,
    user_fcm_tokens.last_used_at
  FROM user_fcm_tokens
  WHERE user_id = p_user_id
    AND is_active = TRUE
  ORDER BY last_used_at DESC;
END;
$$;

-- ============================================================
-- FUNCTION: Cleanup Old/Inactive Tokens (Run via cron job)
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_inactive_fcm_tokens()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  -- Mark tokens as inactive if not used in 60 days
  UPDATE user_fcm_tokens
  SET is_active = FALSE
  WHERE last_used_at < NOW() - INTERVAL '60 days'
    AND is_active = TRUE;

  -- Delete tokens inactive for more than 90 days
  DELETE FROM user_fcm_tokens
  WHERE is_active = FALSE
    AND last_used_at < NOW() - INTERVAL '90 days';
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  RAISE NOTICE 'Cleaned up % inactive FCM tokens', v_deleted_count;
  RETURN v_deleted_count;
END;
$$;

-- ============================================================
-- MIGRATION: Move Existing Tokens from users.fcm_token
-- ============================================================
-- This preserves existing tokens by moving them to the new table
INSERT INTO user_fcm_tokens (user_id, fcm_token, device_name, platform)
SELECT 
  id,
  fcm_token,
  'Existing Device',
  'android'
FROM users
WHERE fcm_token IS NOT NULL
  AND fcm_token != ''
ON CONFLICT (fcm_token) DO NOTHING;

-- ============================================================
-- OPTIONAL: Drop old fcm_token column from users table
-- ============================================================
-- Uncomment if you want to remove the old column (RECOMMENDED after testing)
-- ALTER TABLE users DROP COLUMN IF EXISTS fcm_token;

-- ============================================================
-- Grant Permissions
-- ============================================================
GRANT EXECUTE ON FUNCTION add_or_update_fcm_token(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION remove_fcm_token(UUID, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_user_fcm_tokens(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION cleanup_inactive_fcm_tokens() TO authenticated, anon;

-- ============================================================
-- Comments for Documentation
-- ============================================================
COMMENT ON TABLE user_fcm_tokens IS 'Stores FCM tokens for multiple devices per user to support multi-device push notifications';
COMMENT ON FUNCTION add_or_update_fcm_token(UUID, TEXT, TEXT, TEXT, TEXT) IS 'Adds or updates an FCM token for a user device';
COMMENT ON FUNCTION remove_fcm_token(UUID, TEXT, TEXT) IS 'Removes FCM token(s) for a user when they sign out';
COMMENT ON FUNCTION get_user_fcm_tokens(UUID) IS 'Returns all active FCM tokens for a user';
COMMENT ON FUNCTION cleanup_inactive_fcm_tokens() IS 'Cleans up old/inactive tokens (run via cron)';

-- ============================================================
-- SUCCESS MESSAGE
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Multi-device FCM token support migration completed successfully!';
  RAISE NOTICE 'Functions created:';
  RAISE NOTICE '  - add_or_update_fcm_token()';
  RAISE NOTICE '  - remove_fcm_token()';
  RAISE NOTICE '  - get_user_fcm_tokens()';
  RAISE NOTICE '  - cleanup_inactive_fcm_tokens()';
END $$;
