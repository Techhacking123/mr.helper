-- Add missing subscription columns to users table

-- 1. Add subscription_status status (e.g. 'active', 'expired')
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'inactive';

-- 2. Add subscription_end_date (redundant but good for safety)
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_end_date TIMESTAMP WITH TIME ZONE;

-- 3. Update existing active subscribers to have status='active'
UPDATE users 
SET subscription_status = 'active' 
WHERE is_subscribed = true;
