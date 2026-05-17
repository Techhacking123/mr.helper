-- ========================================
-- ADD NEW ORDER STATUSES TO CHECK CONSTRAINT
-- ========================================
-- This fixes the error: "violates check constraint orders_status_check"
-- Adds: working, cancelled, expired to allowed statuses

-- Drop the existing constraint
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- Create new constraint with all statuses including new ones
ALTER TABLE orders ADD CONSTRAINT orders_status_check 
CHECK (status IN (
  'pending',
  'request_open',
  'accepted',
  'confirmed',
  'verified',
  'working',        -- NEW
  'completed',
  'cancelled',      -- NEW
  'expired',        -- NEW
  'rejected',
  'negotiating'
));

-- Verify the constraint was created
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conname = 'orders_status_check';
