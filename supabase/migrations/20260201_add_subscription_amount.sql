-- Add subscription_amount column to services table
-- This allows admins to set different subscription prices for each service type

ALTER TABLE public.services
ADD COLUMN IF NOT EXISTS subscription_amount NUMERIC DEFAULT 250;

-- Optional: Update existing services with default value
UPDATE public.services
SET subscription_amount = 250
WHERE subscription_amount IS NULL;
