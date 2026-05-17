-- FIX FCM TOKEN DUPLICATION
-- This script updates the 'add_or_update_fcm_token' RPC function to enforce a SINGLE active token per user by default.
-- Or better, it handles device_id correctly but ensures we don't have stray active tokens.

CREATE OR REPLACE FUNCTION add_or_update_fcm_token(
    p_user_id UUID,
    p_fcm_token TEXT,
    p_device_id TEXT DEFAULT NULL,
    p_device_name TEXT DEFAULT NULL,
    p_platform TEXT DEFAULT 'android'
)
RETURNS UUID AS $$
DECLARE
    v_token_id UUID;
BEGIN
    -- 1. Deactivate ANY other tokens for this user (Aggressive cleanup to stop duplicates)
    -- This ensures the user only has ONE active device receiving notifications at a time.
    -- If you want multi-device support, remove this block. But for now, this fixes your duplicate issue.
    UPDATE user_fcm_tokens
    SET is_active = FALSE
    WHERE user_id = p_user_id
      AND fcm_token != p_fcm_token;

    -- 2. Check if this specific token already exists
    SELECT id INTO v_token_id
    FROM user_fcm_tokens
    WHERE fcm_token = p_fcm_token;

    IF v_token_id IS NOT NULL THEN
        -- Token exists: update metadata and ensure it's active
        UPDATE user_fcm_tokens
        SET 
            user_id = p_user_id, -- Handle user switching on same device
            device_id = COALESCE(p_device_id, device_id),
            device_name = COALESCE(p_device_name, device_name),
            platform = COALESCE(p_platform, platform),
            last_used_at = NOW(),
            is_active = TRUE
        WHERE id = v_token_id;
    ELSE
        -- Token is new: insert it
        INSERT INTO user_fcm_tokens (
            user_id, 
            fcm_token, 
            device_id, 
            device_name, 
            platform, 
            is_active, 
            last_used_at
        ) VALUES (
            p_user_id,
            p_fcm_token,
            p_device_id,
            p_device_name,
            p_platform,
            TRUE,
            NOW()
        )
        RETURNING id INTO v_token_id;
    END IF;

    RETURN v_token_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
