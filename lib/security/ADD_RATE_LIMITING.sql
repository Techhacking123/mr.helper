-- ==========================================
-- RATE LIMITING SYSTEM
-- ==========================================

-- 1. Create a table to track actions
CREATE TABLE IF NOT EXISTS rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address TEXT,
    action TEXT, -- e.g. 'signup', 'login_attempt', 'send_otp'
    identifier TEXT, -- Optional: email or user_id if known
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_rate_limits_ip_action ON rate_limits(ip_address, action);
CREATE INDEX IF NOT EXISTS idx_rate_limits_created_at ON rate_limits(created_at);

-- 2. Clean up old logs automatically (PG_CRON recommended, or call manually)
-- For now, we can just delete old records during the check to keep table small
-- (Optional optimization)

-- 3. The Rate Limit Check Function
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
    -- Note: This works when called via API/PostgREST
    BEGIN
        v_ip_address := current_setting('request.headers', true)::json->>'x-forwarded-for';
    EXCEPTION WHEN OTHERS THEN
        v_ip_address := 'unknown';
    END;
    
    -- If multiple IPs (proxy chain), take the first one
    IF v_ip_address IS NOT NULL AND position(',' in v_ip_address) > 0 THEN
        v_ip_address := split_part(v_ip_address, ',', 1);
    END IF;
    
    IF v_ip_address IS NULL THEN
        v_ip_address := 'unknown';
    END IF;

    -- Count requests in the window
    SELECT COUNT(*) INTO v_count
    FROM rate_limits
    WHERE 
        action = p_action
        AND (
            ip_address = v_ip_address 
            OR (p_identifier IS NOT NULL AND identifier = p_identifier)
        )
        AND created_at > (NOW() - (p_window_seconds || ' seconds')::INTERVAL);

    IF v_count >= p_max_requests THEN
        RETURN FALSE;
    END IF;

    -- Log the request
    INSERT INTO rate_limits (ip_address, action, identifier)
    VALUES (v_ip_address, p_action, p_identifier);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. EXAMPLE USAGE IN AN RPC (Secure Signup)
/*
CREATE OR REPLACE FUNCTION signup_secure(
    email TEXT,
    password_hash TEXT,
    full_name TEXT
) RETURNS JSON AS $$
BEGIN
    -- Limit to 3 signups per hour per IP
    IF NOT check_rate_limit('signup', 3600, 3, email) THEN
        RAISE EXCEPTION 'Signup rate limit exceeded. Please try again later.';
    END IF;

    INSERT INTO users (email, password, full_name) VALUES (email, password_hash, full_name);
    
    RETURN '{"success": true}'::JSON;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
*/
