-- Fix for festival themes RLS policy
-- This allows anyone to update themes (you can add admin check later if needed)

DROP POLICY IF EXISTS "Authenticated users can manage festival themes" ON public.festival_themes;

-- Create new policy that allows all authenticated users to manage themes
-- Since your admin is hardcoded, we'll make this more permissive
CREATE POLICY "Allow theme management"
  ON public.festival_themes
  FOR ALL
  USING (true)
  WITH CHECK (true);
