-- Replace subscription_amount with google_subscription_id
-- The actual amount will be fetched from Google Play using this subscription ID

-- Add google_subscription_id column to services table
ALTER TABLE public.services
ADD COLUMN IF NOT EXISTS google_subscription_id TEXT DEFAULT 'mrhelper_monthly_pro';

-- Set default Google subscription ID for all existing services
UPDATE public.services
SET google_subscription_id = 'mrhelper_monthly_pro'
WHERE google_subscription_id IS NULL;

-- Note: We keep subscription_amount column for backward compatibility / fallback display
-- but it will no longer be editable from admin panel.
-- The actual price is now determined by the Google Play subscription product.
