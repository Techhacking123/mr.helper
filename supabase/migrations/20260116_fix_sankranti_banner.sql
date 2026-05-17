-- Fix Sankranti banner image extension from .jpeg to .jpg
UPDATE public.festival_themes
SET banner_image_url = 'assets/themes/sankranti_banner.jpg'
WHERE name = 'sankranti' AND banner_image_url = 'assets/themes/sankranti_banner.jpeg';
