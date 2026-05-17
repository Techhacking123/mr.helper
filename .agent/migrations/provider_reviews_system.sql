-- ========================================
-- PROVIDER REVIEWS SYSTEM
-- ========================================
-- Allows users to rate and review providers after service completion

-- ========================================
-- Step 1: Create reviews table
-- ========================================

CREATE TABLE IF NOT EXISTS provider_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure one review per order
  CONSTRAINT unique_review_per_order UNIQUE(order_id)
);

-- Add indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_provider_reviews_provider_id ON provider_reviews(provider_id);
CREATE INDEX IF NOT EXISTS idx_provider_reviews_user_id ON provider_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_provider_reviews_order_id ON provider_reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_provider_reviews_rating ON provider_reviews(rating);

-- ========================================
-- Step 2: Add average rating to users table
-- ========================================

ALTER TABLE users
ADD COLUMN IF NOT EXISTS average_rating DECIMAL(3, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;

-- ========================================
-- Step 3: Create function to update provider ratings
-- ========================================

CREATE OR REPLACE FUNCTION update_provider_rating(p_provider_id UUID)
RETURNS VOID AS $$
DECLARE
  avg_rating DECIMAL(3, 2);
  review_count INTEGER;
BEGIN
  -- Calculate average rating and count
  SELECT 
    COALESCE(ROUND(AVG(rating)::numeric, 2), 0),
    COUNT(*)
  INTO avg_rating, review_count
  FROM provider_reviews
  WHERE provider_id = p_provider_id;
  
  -- Update provider's stats
  UPDATE users
  SET 
    average_rating = avg_rating,
    total_reviews = review_count
  WHERE id = p_provider_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- Step 4: Create trigger to auto-update ratings
-- ========================================

CREATE OR REPLACE FUNCTION trigger_update_provider_rating()
RETURNS TRIGGER AS $$
BEGIN
  -- Update on INSERT
  IF (TG_OP = 'INSERT') THEN
    PERFORM update_provider_rating(NEW.provider_id);
    RETURN NEW;
  END IF;
  
  -- Update on UPDATE (if rating changed)
  IF (TG_OP = 'UPDATE') THEN
    PERFORM update_provider_rating(NEW.provider_id);
    RETURN NEW;
  END IF;
  
  -- Update on DELETE
  IF (TG_OP = 'DELETE') THEN
    PERFORM update_provider_rating(OLD.provider_id);
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS update_rating_on_review_change ON provider_reviews;
CREATE TRIGGER update_rating_on_review_change
AFTER INSERT OR UPDATE OR DELETE ON provider_reviews
FOR EACH ROW
EXECUTE FUNCTION trigger_update_provider_rating();

-- ========================================
-- Step 5: Enable RLS on provider_reviews
-- ========================================

ALTER TABLE provider_reviews ENABLE ROW LEVEL SECURITY;

-- Users can view all reviews
CREATE POLICY "Anyone can view reviews"
ON provider_reviews FOR SELECT
USING (true);

-- Users can insert their own reviews
CREATE POLICY "Users can insert own reviews"
ON provider_reviews FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own reviews
CREATE POLICY "Users can update own reviews"
ON provider_reviews FOR UPDATE
USING (auth.uid() = user_id);

-- Users can delete their own reviews
CREATE POLICY "Users can delete own reviews"
ON provider_reviews FOR DELETE
USING (auth.uid() = user_id);

-- ========================================
-- Step 6: Create view for provider reviews with user info
-- ========================================

CREATE OR REPLACE VIEW provider_reviews_with_details AS
SELECT 
  pr.id,
  pr.order_id,
  pr.provider_id,
  pr.user_id,
  pr.rating,
  pr.review_text,
  pr.created_at,
  u.full_name as reviewer_name,
  p.full_name as provider_name,
  p.average_rating,
  p.total_reviews
FROM provider_reviews pr
JOIN users u ON pr.user_id = u.id
JOIN users p ON pr.provider_id = p.id;

-- ========================================
-- Step 7: Grant permissions
-- ========================================

GRANT SELECT ON provider_reviews TO authenticated;
GRANT INSERT ON provider_reviews TO authenticated;
GRANT UPDATE ON provider_reviews TO authenticated;
GRANT DELETE ON provider_reviews TO authenticated;
GRANT SELECT ON provider_reviews_with_details TO authenticated;
GRANT EXECUTE ON FUNCTION update_provider_rating(UUID) TO authenticated;

-- ========================================
-- COMMENTS
-- ========================================

COMMENT ON TABLE provider_reviews IS 'Stores user reviews and ratings for service providers';
COMMENT ON COLUMN provider_reviews.rating IS 'Rating from 1 to 5 stars';
COMMENT ON COLUMN provider_reviews.review_text IS 'Optional text review/feedback';
COMMENT ON COLUMN users.average_rating IS 'Provider average rating (0.00 to 5.00)';
COMMENT ON COLUMN users.total_reviews IS 'Total number of reviews received';
COMMENT ON FUNCTION update_provider_rating IS 'Recalculates and updates provider average rating';
