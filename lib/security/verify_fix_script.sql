-- VERIFY NOTIFICATION FIX (TEST SCRIPT)
-- This script safely simulates an order creation and update to prove duplicates are gone.
-- Run this in your Supabase SQL Editor.

DO $$
DECLARE
    v_provider_id UUID;
    v_buyer_id UUID;
    v_service_id UUID;
    v_location_id UUID;  -- location_id in orders is typically text or uuid depending on schema, usually matches locations.id
    v_order_id UUID;
    v_initial_count INTEGER;
    v_final_count INTEGER;
    v_debug_msg TEXT;
BEGIN
    RAISE NOTICE '--- STARTING NOTIFICATION VERIFICATION ---';

    -- 1. SETUP: FIND VALID DATA
    -- Get a service
    SELECT id INTO v_service_id FROM services LIMIT 1;
    -- Get a location
    SELECT id INTO v_location_id FROM locations LIMIT 1;
    
    -- Find an active provider for this service
    SELECT id INTO v_provider_id FROM users 
    WHERE is_provider = true 
    AND service_id = v_service_id 
    AND subscription_status = 'active'
    LIMIT 1;

    IF v_provider_id IS NULL THEN
        RAISE NOTICE '⚠️ SKIP: No active provider found for Service ID %. Please approve/subscribe a provider to test.', v_service_id;
        RETURN;
    END IF;

    RAISE NOTICE 'Found Provider: %', v_provider_id;

    -- Find a buyer (just use the provider ID if no others exist, self-notification is allowed in this test logic)
    SELECT id INTO v_buyer_id FROM users WHERE id != v_provider_id LIMIT 1;
    IF v_buyer_id IS NULL THEN v_buyer_id := v_provider_id; END IF;

    -- 2. TEST PART 1: INSERT (Normal Order)
    INSERT INTO orders (
        buyer_id, 
        service_id, 
        location_id, 
        status, 
        description, 
        user_price
    ) VALUES (
        v_buyer_id, 
        v_service_id, 
        v_location_id, 
        'request_open', 
        'TEST ORDER - VERIFICATION SCRIPT', 
        100
    )
    RETURNING id INTO v_order_id;
    
    -- Count notifications
    SELECT COUNT(*) INTO v_initial_count FROM notifications WHERE order_id = v_order_id;
    
    RAISE NOTICE 'Step 1 (New Order): Notifications created = %', v_initial_count;

    -- 3. TEST PART 2: UPDATE (Simulate Image Upload)
    -- This UPDATE keeps status as 'request_open', so it should NOT trigger a new notification
    UPDATE orders 
    SET description = 'TEST ORDER - UPDATED DESCRIPTION' 
    WHERE id = v_order_id;
    
    -- Count notifications again
    SELECT COUNT(*) INTO v_final_count FROM notifications WHERE order_id = v_order_id;
    
    RAISE NOTICE 'Step 2 (Order Update): Notifications count = %', v_final_count;

    -- 4. CLEANUP (Delete test data)
    DELETE FROM notifications WHERE order_id = v_order_id;
    DELETE FROM orders WHERE id = v_order_id;
    
    -- 5. ANALYZE RESULT
    IF v_initial_count = v_final_count AND v_initial_count > 0 THEN
        RAISE NOTICE '✅ SUCCESS: Notification count remained at % (No duplicate sent!)', v_initial_count;
    ELSIF v_initial_count = 0 THEN
        RAISE NOTICE '⚠️ CHECK: No notifications were sent at all. Check Provider Subscription/Location matching.';
    ELSE
        RAISE NOTICE '❌ FAILED: Notification count increased from % to % (Duplicate sent!)', v_initial_count, v_final_count;
    END IF;

    RAISE NOTICE '--- VERIFICATION COMPLETE ---';
END $$;
