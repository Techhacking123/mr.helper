-- ==========================================
-- ENSURE subscription_expiry column exists
-- ==========================================
-- This adds the subscription_expiry column to users table if it doesn't exist

ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expiry TIMESTAMPTZ;
