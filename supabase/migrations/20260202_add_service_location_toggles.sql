-- Migration: Add current/destination location toggle options to services table
-- This allows admins to configure whether a service requires current location, destination location, or both

-- Add toggle columns to services table
ALTER TABLE services
ADD COLUMN IF NOT EXISTS require_current_location BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS require_destination_location BOOLEAN DEFAULT false;

-- Add destination location columns to orders table for services that need it
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS destination_latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS destination_longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS destination_address TEXT;

-- Update existing services to have default false values
UPDATE services 
SET require_current_location = false, 
    require_destination_location = false
WHERE require_current_location IS NULL 
   OR require_destination_location IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN services.require_current_location IS 'If true, user must provide their current location when booking this service';
COMMENT ON COLUMN services.require_destination_location IS 'If true, user must provide a destination location when booking this service (e.g., for transport services)';
COMMENT ON COLUMN orders.destination_latitude IS 'Destination latitude for services that require destination location';
COMMENT ON COLUMN orders.destination_longitude IS 'Destination longitude for services that require destination location';
COMMENT ON COLUMN orders.destination_address IS 'Destination address text for services that require destination location';
