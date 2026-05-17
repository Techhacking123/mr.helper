-- FIX: Add columns and correctly populate data to satisfy constraints

-- 1. Add columns if they don't exist
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'inactive';

ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_end_date TIMESTAMP WITH TIME ZONE;

-- 2. Update existing active subscribers CAREFULLY
-- We set end_date to 7 days from now as a fallback if it's missing,
-- to satisfy the "Active subscription must have an end_date" constraint.
UPDATE users 
SET 
    subscription_status = 'active',
    subscription_end_date = COALESCE(subscription_expiry, NOW() + INTERVAL '7 days')
WHERE 
    is_subscribed = true 
    AND (subscription_status IS NULL OR subscription_status != 'active');
