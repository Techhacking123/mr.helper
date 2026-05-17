-- Add subscription_expiry column to users table
-- This column tracks when a provider's subscription expires

ALTER TABLE users 
ADD COLUMN subscription_expiry TIMESTAMP WITH TIME ZONE;

-- Optional: Add index for faster querying of expired subscriptions
CREATE INDEX idx_users_subscription_expiry ON users(subscription_expiry);

-- Optional: Add comment to document the column
COMMENT ON COLUMN users.subscription_expiry IS 'Timestamp when the provider subscription expires (7 days from payment)';
