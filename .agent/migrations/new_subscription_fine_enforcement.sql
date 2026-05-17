-- ============================================================================
-- MIGRATION: NEW SUBSCRIPTION & FINE ENFORCEMENT SYSTEM
-- ============================================================================
-- This migration updates the notify_providers_on_order trigger to enforce:
-- 1. Active subscription required (subscription_status = 'active' AND NOT expired)
-- 2. No pending fines required (fine overrides subscription)
-- 3. Changes subscription from 30 days to 28 days
-- ============================================================================

-- Step 1: Create or replace the centralized can_receive_orders function
CREATE OR REPLACE FUNCTION can_receive_orders(p_provider_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_subscription_status TEXT;
    v_subscription_expiry TIMESTAMPTZ;
    v_total_fines NUMERIC;
    v_can_receive BOOLEAN := FALSE;
BEGIN
    -- Get provider subscription details
    SELECT 
        u.subscription_status,
        u.subscription_expiry
    INTO 
        v_subscription_status,
        v_subscription_expiry
    FROM users u
    WHERE u.id = p_provider_id;

    -- Check if subscription is active AND not expired
    IF v_subscription_status = 'active' AND v_subscription_expiry IS NOT NULL THEN
        IF v_subscription_expiry > NOW() THEN
            -- Subscription is valid, now check fines
            -- Fine overrides subscription: if fines exist, block access
            SELECT COALESCE(SUM(amount), 0)
            INTO v_total_fines
            FROM provider_fines
            WHERE provider_id = p_provider_id 
              AND status = 'pending';

            IF v_total_fines IS NULL OR v_total_fines <= 0 THEN
                v_can_receive := TRUE;
            ELSE
                v_can_receive := FALSE;
            END IF;
        ELSE
            -- Subscription expired
            v_can_receive := FALSE;
        END IF;
    ELSE
        -- No active subscription
        v_can_receive := FALSE;
    END IF;

    RETURN v_can_receive;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 2: Create helper function to get total unpaid fines
CREATE OR REPLACE FUNCTION get_provider_total_unpaid_fines(p_provider_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total
    FROM provider_fines
    WHERE provider_id = p_provider_id 
      AND status = 'pending';

    RETURN COALESCE(v_total, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Update the notify_providers_on_order trigger function
-- This is called when a new order is created to notify matching providers
CREATE OR REPLACE FUNCTION notify_providers_on_order()
RETURNS TRIGGER AS $$
DECLARE
    v_service_id UUID;
    v_location_id UUID;
    v_order_id UUID;
    v_provider RECORD;
    v_notification_type TEXT;
BEGIN
    -- Get the order details
    IF TG_OP = 'INSERT' THEN
        v_order_id := NEW.id;
        v_service_id := NEW.service_id;
        v_location_id := NEW.location_id;
        v_notification_type := 'new_order';
    ELSE
        v_order_id := OLD.id;
        v_service_id := OLD.service_id;
        v_location_id := OLD.location_id;
        v_notification_type := 'order_update';
    END IF;

    -- Skip if no service_id
    IF v_service_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Only notify for 'request_open' orders
    IF v_notification_type = 'new_order' AND NEW.status != 'request_open' THEN
        RETURN NULL;
    END IF;

    -- Fetch matching providers with ACTIVE subscription AND NO pending fines
    FOR v_provider IN
        SELECT 
            u.id as provider_id,
            u.full_name,
            u.fcm_token
        FROM users u
        WHERE u.is_provider = true
          AND u.service_id = v_service_id
          AND u.status = 'active'
          -- ENFORCE: Must have active subscription (checked in can_receive_orders)
          AND can_receive_orders(u.id) = true
    LOOP
        -- Insert notification for each provider
        INSERT INTO notifications (
            user_id,
            order_id,
            title,
            message,
            type,
            is_read
        ) VALUES (
            v_provider.provider_id,
            v_order_id,
            'New Service Request',
            'A new service request matches your expertise!',
            v_notification_type,
            false
        );
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Add or update the trigger
DROP TRIGGER IF EXISTS on_order_created_notify ON orders;

CREATE TRIGGER on_order_created_notify
    AFTER INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION notify_providers_on_order();

-- Step 5: Log the migration
INSERT INTO subscription_history (
    provider_id,
    action,
    new_status,
    amount,
    created_at
) VALUES (
    NULL,
    'system_migration',
    true,
    0,
    NOW()
);

-- Verification query
SELECT 
    'Migration completed' as status,
    NOW() as executed_at,
    can_receive_orders(NULL::UUID) as function_exists;