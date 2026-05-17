-- Add FCM token column to users table for push notifications
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Create index for faster FCM token lookups
CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token) WHERE fcm_token IS NOT NULL;

-- Add comment to document the column
COMMENT ON COLUMN users.fcm_token IS 'Firebase Cloud Messaging token for push notifications';
