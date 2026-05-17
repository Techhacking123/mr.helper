-- ==========================================
-- SECURE LOGIN WITH RATE LIMITING
-- ==========================================

-- Relies on 'rate_limits' table and 'check_rate_limit' function created previously.

CREATE OR REPLACE FUNCTION login_secure(
    p_username TEXT,
    p_password_hash TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user RECORD;
    v_pending RECORD;
    v_response JSON;
BEGIN
    -- 1. CHECK RATE LIMIT: 5 attempts per 15 minutes per IP
    IF NOT check_rate_limit('login_attempt', 900, 5, p_username) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Too many login attempts. Please try again in 15 minutes.'
        );
    END IF;

    -- 2. CHECK PENDING PROVIDERS
    SELECT * INTO v_pending
    FROM pending_providers
    WHERE full_name = p_username 
    AND password = p_password_hash 
    AND status = 'pending';

    IF v_pending IS NOT NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Your account is under review by Admin. Please wait for approval.'
        );
    END IF;

    -- 3. CHECK ACTIVE USERS
    SELECT * INTO v_user
    FROM users
    WHERE full_name = p_username 
    AND password = p_password_hash;

    IF v_user IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Invalid Username or Password'
        );
    END IF;

    -- 4. CHECK USER STATUS
    IF v_user.is_provider THEN
        IF v_user.status = 'pending' THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Your account is pending Admin approval.'
            );
        ELSIF v_user.status = 'rejected' THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Your account application was rejected.'
            );
        ELSIF v_user.status = 'suspended' THEN
            RETURN json_build_object(
                'success', false,
                'message', 'Your account has been suspended.'
            );
        END IF;
    END IF;

    -- 5. SUCCESS
    RETURN json_build_object(
        'success', true,
        'user', json_build_object(
            'id', v_user.id,
            'full_name', v_user.full_name,
            'is_provider', v_user.is_provider,
            'status', v_user.status
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
