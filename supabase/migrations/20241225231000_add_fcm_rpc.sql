-- Create a function to update FCM token that bypasses RLS
CREATE OR REPLACE FUNCTION update_fcm_token(p_user_id UUID, p_token TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- <--- This is the magic key. It runs as admin.
AS $$
BEGIN
  UPDATE users
  SET fcm_token = p_token
  WHERE id = p_user_id;
END;
$$;
