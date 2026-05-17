-- ==========================================
-- COMPLETE SECURE LOGIN UPDATE
-- ==========================================
-- ACTION REQUIRED: Run this entire script in your Supabase SQL Editor to fix the login error.

-- 1. Create RATE_LIMITS table (if not exists)
CREATE TABLE IF NOT EXISTS rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address TEXT,
    action TEXT, -- e.g. 'login_attempt'
    identifier TEXT, -- e.g. username/email
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_ip_action ON rate_limits(ip_address, action);
CREATE INDEX IF NOT EXISTS idx_rate_limits_created_at ON rate_limits(created_at);

-- 2. Create CHECK_RATE_LIMIT function
CREATE OR REPLACE FUNCTION check_rate_limit(
    p_action TEXT,
    p_window_seconds INT,
    p_max_requests INT,
    p_identifier TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_ip_address TEXT;
    v_count INT;
BEGIN
    -- Try to get IP from Supabase headers
    BEGIN
        v_ip_address := current_setting('request.headers', true)::json->>'x-forwarded-for';
    EXCEPTION WHEN OTHERS THEN
        v_ip_address := 'unknown';
    END;
    
    -- Handle proxy chains (comma separated IPs)
    IF v_ip_address IS NOT NULL AND position(',' in v_ip_address) > 0 THEN
        v_ip_address := split_part(v_ip_address, ',', 1);
    END IF;
    
    IF v_ip_address IS NULL THEN
        v_ip_address := 'unknown';
    END IF;

    -- Count recent requests
    SELECT COUNT(*) INTO v_count
    FROM rate_limits
    WHERE 
        action = p_action
        AND (
            ip_address = v_ip_address 
            OR (p_identifier IS NOT NULL AND identifier = p_identifier)
        )
        AND created_at > (NOW() - (p_window_seconds || ' seconds')::INTERVAL);

    -- Block if limit exceeded
    IF v_count >= p_max_requests THEN
        RETURN FALSE;
    END IF;

    -- Log this request
    INSERT INTO rate_limits (ip_address, action, identifier)
    VALUES (v_ip_address, p_action, p_identifier);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create LOGIN_SECURE function (This is what your app is looking for!)
CREATE OR REPLACE FUNCTION login_secure(
    p_username TEXT,
    p_password_hash TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user RECORD;
    v_pending RECORD;
BEGIN
    -- A. CHECK RATE LIMIT: 5 attempts per 15 minutes (900 seconds)
    IF NOT check_rate_limit('login_attempt', 900, 5, p_username) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Too many login attempts. Please try again in 15 minutes.'
        );
    END IF;

    -- B. CHECK PENDING PROVIDERS (Provider application under review)
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

    -- C. CHECK ACTIVE USERS
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

    -- D. CHECK USER STATUS
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

    -- E. SUCCESS
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
