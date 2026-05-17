-- Fix: Allow admin to read users table for sending notifications
-- This creates a function that bypasses RLS for admin user list

-- 1. Create function to get users/providers for admin
CREATE OR REPLACE FUNCTION get_users_for_admin(
    p_is_provider BOOLEAN
)
RETURNS TABLE (
    id UUID,
    full_name TEXT,
    email TEXT,
    phone TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER -- This allows the function to bypass RLS
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.full_name,
        u.email,
        u.phone
    FROM users u
    WHERE u.is_provider = p_is_provider
    AND u.email != 'adime' -- Exclude admin
    AND u.fcm_token IS NOT NULL
    ORDER BY u.full_name;
END;
$$;

-- 2. Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_users_for_admin(BOOLEAN) TO authenticated;

COMMENT ON FUNCTION get_users_for_admin IS 'Returns list of users/providers for admin to select notification recipients. Bypasses RLS.';
