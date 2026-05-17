-- Add 'cancelled' to subscription_status_enum
-- This is necessary because the admin cancellation function tries to set this status.
ALTER TYPE subscription_status_enum ADD VALUE IF NOT EXISTS 'cancelled';

-- Just in case, grant usage to anon/authenticated if needed (usually handled by type ownership)
-- GRANT USAGE ON TYPE subscription_status_enum TO anon, authenticated, service_role;
