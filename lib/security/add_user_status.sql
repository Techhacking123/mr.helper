-- Add status column to users table
-- 'active' for normal users
-- 'pending' for new providers
-- 'approved' for approved providers
-- 'rejected' for rejected providers
-- 'suspended' for suspended users

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- Optional: Create an index for faster filtering by status
CREATE INDEX IF NOT EXISTS idx_users_status ON public.users(status);
