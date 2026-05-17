-- Add latitude and longitude columns to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Optional: Create an index for spatial queries if needed later
-- CREATE INDEX IF NOT EXISTS idx_users_location ON users USING gist (ll_to_earth(latitude, longitude));
