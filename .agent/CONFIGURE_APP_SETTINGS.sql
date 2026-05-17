-- ==========================================
-- FIX: Configure App Settings for Edge Function
-- ==========================================
-- This sets up the configuration needed for the
-- database trigger to call the Edge Function
-- ==========================================

-- IMPORTANT: Replace these values with YOUR actual values
-- 1. Replace YOUR_PROJECT_REF with your Supabase project reference
--    (find it in your Supabase project URL: https://YOUR_PROJECT_REF.supabase.co)
-- 2. Replace YOUR_SERVICE_ROLE_KEY with your service role key
--    (find it in Supabase Dashboard → Settings → API → service_role key)

-- Set Supabase URL
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://rvrpsqdrbwfvllelyqhf.supabase.co';

-- Set Service Role Key
ALTER DATABASE postgres SET app.settings.service_role_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2cnBzcWRyYndmdmxsZWx5cWhmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTE1ODE5OSwiZXhwIjoyMDgwNzM0MTk5fQ.GyckF5tq300NJmV-invzTOLo-eBlv2U9AOoiMJtkMXc';

-- ==========================================
-- VERIFICATION
-- ==========================================

-- Check if settings were saved
SELECT current_setting('app.settings.supabase_url', true) as supabase_url;
SELECT current_setting('app.settings.service_role_key', true) as service_role_key;

-- Should show your actual values, NOT null

-- ==========================================
-- HOW TO FIND YOUR VALUES
-- ==========================================

-- 1. SUPABASE_URL:
--    - Go to Supabase Dashboard
--    - Look at your browser URL: https://supabase.com/dashboard/project/YOUR_PROJECT_REF
--    - Your URL is: https://YOUR_PROJECT_REF.supabase.co
--    
--    Example: If project ref is 'rvrpsqdrbwfvllelyqhf'
--    Then URL is: https://rvrpsqdrbwfvllelyqhf.supabase.co

-- 2. SERVICE_ROLE_KEY:
--    - Go to Supabase Dashboard
--    - Settings → API
--    - Under "Project API keys" section
--    - Copy the "service_role" key (NOT the anon key!)
--    - It starts with: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
--    - Should be very long (300+ characters)

-- ==========================================
-- AFTER RUNNING THIS, TEST
-- ==========================================

-- Create a test notification and it should trigger FCM:
/*
INSERT INTO notifications (user_id, message, created_at)
VALUES (
    'e1f887e4-40d5-4026-bbff-861733fdccd8',
    'TEST: This should trigger FCM!',
    NOW()
);
*/

-- Then check:
-- 1. Edge Function logs in Supabase Dashboard
-- 2. Your phone should receive the notification!

-- ==========================================
