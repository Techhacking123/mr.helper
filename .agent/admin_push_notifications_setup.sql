-- Admin Push Notifications System
-- This migration creates tables and functions for admin to send push notifications

-- 1. Create scheduled_notifications table
CREATE TABLE IF NOT EXISTS scheduled_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('all_users', 'all_providers', 'selected_users', 'selected_providers')),
    recipient_ids JSONB DEFAULT '[]'::jsonb, -- Array of user IDs if recipient_type is 'selected_users' or 'selected_providers'
    scheduled_at TIMESTAMPTZ, -- NULL for immediate send
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'scheduled')),
    sent_at TIMESTAMPTZ,
    sent_count INTEGER DEFAULT 0,
    failed_count INTEGER DEFAULT 0,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    error_message TEXT
);

-- 2. Create index for performance
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_status ON scheduled_notifications(status);
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_scheduled_at ON scheduled_notifications(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_created_at ON scheduled_notifications(created_at);

-- 3. Enable RLS
ALTER TABLE scheduled_notifications ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS Policies (Admin only access)
-- Note: Admin is identified by email 'adime' (hardcoded in login)
CREATE POLICY "Admins can view all scheduled notifications" ON scheduled_notifications
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE users.id = auth.uid() 
            AND users.email = 'adime'
        )
        OR 
        -- Fallback: Allow if authenticated user's email is 'adime'
        (SELECT email FROM auth.users WHERE id = auth.uid()) = 'adime'
    );

CREATE POLICY "Admins can insert scheduled notifications" ON scheduled_notifications
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users 
            WHERE users.id = auth.uid() 
            AND users.email = 'adime'
        )
        OR 
        -- Fallback: Allow if authenticated user's email is 'adime'
        (SELECT email FROM auth.users WHERE id = auth.uid()) = 'adime'
    );

CREATE POLICY "Admins can update scheduled notifications" ON scheduled_notifications
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE users.id = auth.uid() 
            AND users.email = 'adime'
        )
        OR 
        -- Fallback: Allow if authenticated user's email is 'adime'
        (SELECT email FROM auth.users WHERE id = auth.uid()) = 'adime'
    );

-- 5. Function to send push notification to specific users
CREATE OR REPLACE FUNCTION send_admin_push_notification(
    p_title TEXT,
    p_message TEXT,
    p_user_ids UUID[]
)
RETURNS TABLE (
    success_count INTEGER,
    failed_count INTEGER
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_success_count INTEGER := 0;
    v_failed_count INTEGER := 0;
BEGIN
    -- Loop through each user and insert notification
    FOREACH v_user_id IN ARRAY p_user_ids
    LOOP
        BEGIN
            INSERT INTO notifications (user_id, title, message, type, data, is_read)
            VALUES (
                v_user_id,
                p_title,
                p_message,
                'admin_broadcast',
                jsonb_build_object('title', p_title),
                false
            );
            v_success_count := v_success_count + 1;
        EXCEPTION WHEN OTHERS THEN
            v_failed_count := v_failed_count + 1;
        END;
    END LOOP;
    
    RETURN QUERY SELECT v_success_count, v_failed_count;
END;
$$;

-- 6. Function to get recipient user IDs based on criteria
CREATE OR REPLACE FUNCTION get_recipient_user_ids(
    p_recipient_type TEXT,
    p_selected_ids JSONB DEFAULT '[]'::jsonb
)
RETURNS UUID[]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_ids UUID[];
BEGIN
    CASE p_recipient_type
        WHEN 'all_users' THEN
            SELECT ARRAY_AGG(id) INTO v_user_ids
            FROM users
            WHERE is_provider = false AND email != 'adime' AND fcm_token IS NOT NULL;
            
        WHEN 'all_providers' THEN
            SELECT ARRAY_AGG(id) INTO v_user_ids
            FROM users
            WHERE is_provider = true AND email != 'adime' AND fcm_token IS NOT NULL;
            
        WHEN 'selected_users' THEN
            SELECT ARRAY_AGG(id::UUID) INTO v_user_ids
            FROM jsonb_array_elements_text(p_selected_ids) AS id
            WHERE EXISTS (
                SELECT 1 FROM users 
                WHERE users.id = id::UUID 
                AND users.is_provider = false 
                AND users.email != 'adime'
                AND users.fcm_token IS NOT NULL
            );
            
        WHEN 'selected_providers' THEN
            SELECT ARRAY_AGG(id::UUID) INTO v_user_ids
            FROM jsonb_array_elements_text(p_selected_ids) AS id
            WHERE EXISTS (
                SELECT 1 FROM users 
                WHERE users.id = id::UUID 
                AND users.is_provider = true 
                AND users.email != 'adime'
                AND users.fcm_token IS NOT NULL
            );
            
        ELSE
            v_user_ids := ARRAY[]::UUID[];
    END CASE;
    
    RETURN COALESCE(v_user_ids, ARRAY[]::UUID[]);
END;
$$;

-- 7. Function to process scheduled notifications (called by cron job)
CREATE OR REPLACE FUNCTION process_scheduled_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_notification RECORD;
    v_user_ids UUID[];
    v_result RECORD;
BEGIN
    -- Get all pending scheduled notifications that are due
    FOR v_notification IN 
        SELECT * FROM scheduled_notifications
        WHERE status = 'scheduled'
        AND scheduled_at <= NOW()
    LOOP
        BEGIN
            -- Get recipient user IDs
            v_user_ids := get_recipient_user_ids(
                v_notification.recipient_type,
                v_notification.recipient_ids
            );
            
            -- Send notifications
            SELECT * INTO v_result
            FROM send_admin_push_notification(
                v_notification.title,
                v_notification.message,
                v_user_ids
            );
            
            -- Update scheduled notification status
            UPDATE scheduled_notifications
            SET 
                status = 'sent',
                sent_at = NOW(),
                sent_count = v_result.success_count,
                failed_count = v_result.failed_count
            WHERE id = v_notification.id;
            
        EXCEPTION WHEN OTHERS THEN
            -- Mark as failed if error occurs
            UPDATE scheduled_notifications
            SET 
                status = 'failed',
                error_message = SQLERRM
            WHERE id = v_notification.id;
        END;
    END LOOP;
END;
$$;

-- 8. Create a trigger to auto-send immediate notifications
CREATE OR REPLACE FUNCTION trigger_send_immediate_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_ids UUID[];
    v_result RECORD;
BEGIN
    -- Only process if status is 'pending' and scheduled_at is NULL (immediate send)
    IF NEW.status = 'pending' AND NEW.scheduled_at IS NULL THEN
        -- Get recipient user IDs
        v_user_ids := get_recipient_user_ids(
            NEW.recipient_type,
            NEW.recipient_ids
        );
        
        -- Send notifications
        SELECT * INTO v_result
        FROM send_admin_push_notification(
            NEW.title,
            NEW.message,
            v_user_ids
        );
        
        -- Update the record
        NEW.status := 'sent';
        NEW.sent_at := NOW();
        NEW.sent_count := v_result.success_count;
        NEW.failed_count := v_result.failed_count;
    ELSIF NEW.status = 'pending' AND NEW.scheduled_at IS NOT NULL THEN
        -- Mark as scheduled
        NEW.status := 'scheduled';
    END IF;
    
    RETURN NEW;
END;
$$;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS trg_send_immediate_notification ON scheduled_notifications;

-- Create trigger
CREATE TRIGGER trg_send_immediate_notification
    BEFORE INSERT ON scheduled_notifications
    FOR EACH ROW
    EXECUTE FUNCTION trigger_send_immediate_notification();

COMMENT ON TABLE scheduled_notifications IS 'Stores admin-created push notifications for immediate or scheduled delivery';
COMMENT ON FUNCTION send_admin_push_notification IS 'Sends push notifications to specified users';
COMMENT ON FUNCTION get_recipient_user_ids IS 'Gets user IDs based on recipient type and selection';
COMMENT ON FUNCTION process_scheduled_notifications IS 'Processes scheduled notifications (run via cron)';
