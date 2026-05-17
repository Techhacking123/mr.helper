-- 1. DROP the existing check constraint
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- 2. RE-ADD the constraint with ALL possible statuses
ALTER TABLE public.orders 
ADD CONSTRAINT orders_status_check 
CHECK (status IN (
  'pending', 
  'accepted',    -- Missed this one previously!
  'confirmed', 
  'completed', 
  'cancelled', 
  'request_open', 
  'negotiating', 
  'verified',
  'rejected'
));

-- 3. Ensure the new columns exist (in case they weren't added)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS last_offer_by text DEFAULT 'user';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS provider_price numeric;
