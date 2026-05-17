-- Create festival_themes table
CREATE TABLE IF NOT EXISTS public.festival_themes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT FALSE,
  
  -- Theme colors
  primary_color TEXT NOT NULL,
  secondary_color TEXT NOT NULL,
  accent_color TEXT NOT NULL,
  background_color TEXT NOT NULL,
  text_color TEXT NOT NULL,
  card_color TEXT NOT NULL,
  
  -- Theme assets (stored as URLs or asset paths)
  banner_image_url TEXT,
  icon_pack TEXT, -- JSON object with icon mappings
  decorative_elements TEXT, -- JSON array of decorative element configs
  
  -- Priority (for display order in admin panel)
  priority INTEGER DEFAULT 0,
  
  -- Metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create index on is_active for quick active theme lookup
CREATE INDEX IF NOT EXISTS idx_festival_themes_active ON public.festival_themes(is_active);

-- Create index on priority for ordered display
CREATE INDEX IF NOT EXISTS idx_festival_themes_priority ON public.festival_themes(priority);

-- Add RLS policies
ALTER TABLE public.festival_themes ENABLE ROW LEVEL SECURITY;

-- Allow everyone to read themes
CREATE POLICY "Anyone can read festival themes"
  ON public.festival_themes
  FOR SELECT
  USING (true);

-- Only authenticated users can manage themes (admins will be checked in app)
CREATE POLICY "Authenticated users can manage festival themes"
  ON public.festival_themes
  FOR ALL
  USING (auth.uid() IS NOT NULL);

-- Create function to ensure only one theme is active at a time
CREATE OR REPLACE FUNCTION public.ensure_single_active_theme()
RETURNS TRIGGER AS $$
BEGIN
  -- If the new/updated theme is being set to active
  IF NEW.is_active = TRUE THEN
    -- Deactivate all other themes
    UPDATE public.festival_themes
    SET is_active = FALSE
    WHERE id != NEW.id AND is_active = TRUE;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to enforce single active theme
DROP TRIGGER IF EXISTS enforce_single_active_theme ON public.festival_themes;
CREATE TRIGGER enforce_single_active_theme
  BEFORE INSERT OR UPDATE ON public.festival_themes
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_single_active_theme();

-- Create function to get active theme
CREATE OR REPLACE FUNCTION public.get_active_theme()
RETURNS SETOF public.festival_themes AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.festival_themes
  WHERE is_active = TRUE
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Insert default themes
INSERT INTO public.festival_themes (
  name, display_name, description, is_active, priority,
  primary_color, secondary_color, accent_color, background_color, text_color, card_color,
  banner_image_url, icon_pack, decorative_elements
) VALUES
  -- Default Theme (Active by default)
  (
    'default',
    'Default',
    'Default app theme - clean and modern',
    true,
    0,
    '#1976D2', '#42A5F5', '#FF5722', '#F5F5F5', '#212121', '#FFFFFF',
    null,
    '{}',
    '[]'
  ),
  
  -- Sankranti Theme
  (
    'sankranti',
    'Sankranti',
    'Makar Sankranti - Harvest Festival',
    false,
    1,
    '#FF6F00', '#FFA726', '#FFEB3B', '#FFF8E1', '#4E342E', '#FFFFFF',
    'assets/themes/sankranti_banner.jpg',
    '{"kite": "assets/themes/sankranti_kite.png", "sun": "assets/themes/sankranti_sun.png"}',
    '[{"type": "kite", "position": "top-right"}, {"type": "sun", "position": "top-left"}]'
  ),
  
  -- Ugadi Theme
  (
    'ugadi',
    'Ugadi',
    'Ugadi - Telugu New Year',
    false,
    2,
    '#9C27B0', '#BA68C8', '#4CAF50', '#F3E5F5', '#1A237E', '#FFFFFF',
    'assets/themes/ugadi_banner.jpg',
    '{"mango": "assets/themes/ugadi_mango.png", "neem": "assets/themes/ugadi_neem.png"}',
    '[{"type": "mango", "position": "top-right"}, {"type": "neem", "position": "bottom-left"}]'
  ),
  
  -- Dussehra Theme
  (
    'dussehra',
    'Dussehra',
    'Dussehra - Victory of Good over Evil',
    false,
    3,
    '#D32F2F', '#F44336', '#FFD700', '#FFEBEE', '#212121', '#FFFFFF',
    'assets/themes/dussehra_banner.jpg',
    '{"bow": "assets/themes/dussehra_bow.png", "ravana": "assets/themes/dussehra_ravana.png"}',
    '[{"type": "bow", "position": "top-left"}, {"type": "ravana", "position": "bottom-right"}]'
  ),
  
  -- Diwali Theme
  (
    'diwali',
    'Diwali',
    'Diwali - Festival of Lights',
    false,
    4,
    '#FF6F00', '#FF9800', '#FFC107', '#2C1810', '#FFFFFF', '#3E2723',
    'assets/themes/diwali_banner.jpg',
    '{"diya": "assets/themes/diwali_diya.png", "rangoli": "assets/themes/diwali_rangoli.png", "firework": "assets/themes/diwali_firework.png"}',
    '[{"type": "diya", "position": "top-left"}, {"type": "diya", "position": "top-right"}, {"type": "rangoli", "position": "bottom-center"}, {"type": "firework", "position": "top-center"}]'
  ),
  
  -- Christmas Theme
  (
    'christmas',
    'Christmas',
    'Christmas - Season of Joy',
    false,
    5,
    '#C62828', '#EF5350', '#2E7D32', '#FFFFFF', '#1B5E20', '#FFFFFF',
    'assets/themes/christmas_banner.jpg',
    '{"tree": "assets/themes/christmas_tree.png", "bell": "assets/themes/christmas_bell.png", "star": "assets/themes/christmas_star.png", "gift": "assets/themes/christmas_gift.png"}',
    '[{"type": "tree", "position": "bottom-left"}, {"type": "bell", "position": "top-right"}, {"type": "star", "position": "top-center"}, {"type": "gift", "position": "bottom-right"}]'
  );

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION public.update_festival_themes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_festival_themes_timestamp ON public.festival_themes;
CREATE TRIGGER update_festival_themes_timestamp
  BEFORE UPDATE ON public.festival_themes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_festival_themes_updated_at();
