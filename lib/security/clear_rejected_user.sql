-- Function to safely delete a user if they are rejected
-- This allows them to sign up again from scratch
CREATE OR REPLACE FUNCTION clear_rejected_user(email_input TEXT)
RETURNS VOID AS $$
BEGIN
  -- Only delete if the status is strictly 'rejected'
  DELETE FROM users 
  WHERE email = email_input 
    AND status = 'rejected';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
