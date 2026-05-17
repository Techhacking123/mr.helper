-- Add subscription_start_date column to users table
-- This tracks when a provider's subscription started

-- Add the column (if it doesn't exist)
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS subscription_start_date TIMESTAMP WITH TIME ZONE;

-- Set the start date to the current subscription_end_date minus 30 days for existing active subscriptions
-- This provides a reasonable default for existing subscriptions
UPDATE users
SET subscription_start_date = subscription_end_date - INTERVAL '30 days'
WHERE subscription_status = 'active' 
  AND subscription_end_date IS NOT NULL
  AND subscription_start_date IS NULL;

-- Comment for documentation
COMMENT ON COLUMN users.subscription_start_date IS 'Timestamp when the current subscription period started';
