-- ========================================
-- UPDATE: Make order_id optional in provider_reviews
-- ========================================
-- This allows users to review providers directly from their profile

-- Make order_id nullable (allow reviews without orders)
ALTER TABLE provider_reviews 
ALTER COLUMN order_id DROP NOT NULL;

-- Drop the old unique constraint properly
ALTER TABLE provider_reviews 
DROP CONSTRAINT IF EXISTS unique_review_per_order;

-- Add new constraint: one review per order (if order_id is not null)
-- OR one direct review per user-provider pair (if order_id is null)
CREATE UNIQUE INDEX unique_review_per_order_if_exists
ON provider_reviews (order_id)
WHERE order_id IS NOT NULL;

CREATE UNIQUE INDEX unique_direct_review_per_user_provider
ON provider_reviews (user_id, provider_id)
WHERE order_id IS NULL;

-- Verify
SELECT 
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'provider_reviews';
