-- Add columns for negotiation
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS last_offer_by text CHECK (last_offer_by IN ('user', 'provider'));
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS provider_price numeric;

-- Ensure status check constraint includes 'negotiating' and 'rejected'
-- Note: If you have a strict CHECK constraint on status, you need to drop and re-add it.
-- checking existing constraint:
-- ALTER TABLE public.orders DROP CONSTRAINT orders_status_check;
-- ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'request_open', 'negotiating', 'rejected'));
