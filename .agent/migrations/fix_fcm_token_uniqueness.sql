-- Fix FCM token uniqueness to prevent cross-user notifications
-- This ensures that when a user signs in on a device, any previous user's
-- FCM token on that device is cleared from the database

-- Drop and recreate the function with uniqueness enforcement
DROP FUNCTION IF EXISTS update_fcm_token(UUID, TEXT);

CREATE OR REPLACE FUNCTION update_fcm_token(p_user_id UUID, p_token TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Run as admin to bypass RLS
AS $$
BEGIN
  -- If token is NULL, just clear it for this user
  IF p_token IS NULL THEN
    UPDATE users
    SET fcm_token = NULL
    WHERE id = p_user_id;
    RETURN;
  END IF;

  -- First, clear this token from ANY other user who might have it
  -- This handles the case where a device switches between users
  UPDATE users
  SET fcm_token = NULL
  WHERE fcm_token = p_token
    AND id != p_user_id;

  -- Then set the token for the current user
  UPDATE users
  SET fcm_token = p_token
  WHERE id = p_user_id;
  
  RAISE NOTICE 'FCM token updated for user %, cleared from other users if present', p_user_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION update_fcm_token(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_fcm_token(UUID, TEXT) TO anon;

COMMENT ON FUNCTION update_fcm_token(UUID, TEXT) IS 
'Updates FCM token for a user and ensures the token is unique across all users. 
Clears the token from any other user who had it previously.';
