-- =====================================================
-- DEBUG QUERIES - Check Fine System Data
-- =====================================================

-- 1. Check if fine_transactions table has data
SELECT * FROM fine_transactions ORDER BY created_at DESC LIMIT 10;

-- 2. Check if orders have fines marked
SELECT id, title, provider_id, is_expired, fine_amount, fine_paid, deadline
FROM orders 
WHERE fine_amount > 0
ORDER BY created_at DESC
LIMIT 10;

-- 3. Check provider's total_unpaid_fines
SELECT id, full_name, total_unpaid_fines, total_fines_paid
FROM users
WHERE total_unpaid_fines > 0 OR total_fines_paid > 0;

-- 4. Test the get_provider_unpaid_fines function
-- Replace 'YOUR_PROVIDER_ID' with actual provider UUID
SELECT get_provider_unpaid_fines('YOUR_PROVIDER_ID_HERE');

-- 5. Check if there are any expired orders that haven't been processed
SELECT id, title, provider_id, deadline, is_expired, fine_amount, status
FROM orders
WHERE deadline < NOW()
  AND status NOT IN ('completed', 'cancelled')
  AND is_expired = FALSE
ORDER BY deadline DESC;
