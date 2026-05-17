-- The 'orders' table has a check constraint that restricts values for the 'status' column.
-- The current constraint likely does not include 'verified' and 'ignored' (though 'ignored' is in order_offers, not orders).
-- We need to update the constraint to allow 'verified'.

-- 1. Drop the existing constraint (name might vary, usually orders_status_check)
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- 2. Add the new constraint with all allowed statuses
ALTER TABLE orders 
ADD CONSTRAINT orders_status_check 
CHECK (status IN ('request_open', 'pending', 'accepted', 'completed', 'cancelled', 'verified'));

-- 3. Also ensuring order_offers has correct status constraint if it exists
ALTER TABLE order_offers DROP CONSTRAINT IF EXISTS order_offers_status_check;
ALTER TABLE order_offers
ADD CONSTRAINT order_offers_status_check
CHECK (status IN ('pending', 'accepted', 'rejected', 'ignored'));
