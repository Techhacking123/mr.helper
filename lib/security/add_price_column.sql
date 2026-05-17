-- Add 'price' column if it doesn't exist
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS price numeric;
