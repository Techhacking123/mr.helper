-- 1. Ensure the 'services' (Business Types) exist first. 
-- We verify/insert them to be safe.
INSERT INTO public.services (name)
VALUES 
  ('Cleaning'),
  ('Plumbing'), 
  ('Electrical'), 
  ('Painting'), 
  ('Carpentry'), 
  ('AC Repair')
ON CONFLICT (name) DO NOTHING; -- Assuming 'name' is unique or just ignoring duplicates if no constraint

-- 2. Insert the 'service_types' (Sub Services) mapping to the parent Service ID.

-- Cleaning
INSERT INTO public.service_types (name, service_id)
SELECT 'Kitchen Cleaning', id FROM public.services WHERE name = 'Cleaning'
UNION ALL
SELECT 'Bathroom Cleaning', id FROM public.services WHERE name = 'Cleaning'
UNION ALL
SELECT 'Full Home Cleaning', id FROM public.services WHERE name = 'Cleaning'
UNION ALL
SELECT 'Sofa Cleaning', id FROM public.services WHERE name = 'Cleaning'
UNION ALL
SELECT 'Carpet Cleaning', id FROM public.services WHERE name = 'Cleaning';

-- Plumbing
INSERT INTO public.service_types (name, service_id)
SELECT 'Leakage Repair', id FROM public.services WHERE name = 'Plumbing'
UNION ALL
SELECT 'Pipe Installation', id FROM public.services WHERE name = 'Plumbing'
UNION ALL
SELECT 'Tap Repair', id FROM public.services WHERE name = 'Plumbing'
UNION ALL
SELECT 'Blockage Removal', id FROM public.services WHERE name = 'Plumbing'
UNION ALL
SELECT 'Water Tank Cleaning', id FROM public.services WHERE name = 'Plumbing';

-- Electrical
INSERT INTO public.service_types (name, service_id)
SELECT 'Wiring', id FROM public.services WHERE name = 'Electrical'
UNION ALL
SELECT 'Switch & Socket', id FROM public.services WHERE name = 'Electrical'
UNION ALL
SELECT 'Fan Installation', id FROM public.services WHERE name = 'Electrical'
UNION ALL
SELECT 'Light Installation', id FROM public.services WHERE name = 'Electrical'
UNION ALL
SELECT 'Inverter Support', id FROM public.services WHERE name = 'Electrical';

-- Painting
INSERT INTO public.service_types (name, service_id)
SELECT 'Interior Painting', id FROM public.services WHERE name = 'Painting'
UNION ALL
SELECT 'Exterior Painting', id FROM public.services WHERE name = 'Painting'
UNION ALL
SELECT 'Wall Texture', id FROM public.services WHERE name = 'Painting'
UNION ALL
SELECT 'Waterproofing', id FROM public.services WHERE name = 'Painting';

-- Carpentry
INSERT INTO public.service_types (name, service_id)
SELECT 'Furniture Repair', id FROM public.services WHERE name = 'Carpentry'
UNION ALL
SELECT 'Door/Window Repair', id FROM public.services WHERE name = 'Carpentry'
UNION ALL
SELECT 'Furniture Assembly', id FROM public.services WHERE name = 'Carpentry'
UNION ALL
SELECT 'Custom Furniture', id FROM public.services WHERE name = 'Carpentry';

-- AC Repair
INSERT INTO public.service_types (name, service_id)
SELECT 'AC Service', id FROM public.services WHERE name = 'AC Repair'
UNION ALL
SELECT 'Gas Filling', id FROM public.services WHERE name = 'AC Repair'
UNION ALL
SELECT 'AC Installation', id FROM public.services WHERE name = 'AC Repair'
UNION ALL
SELECT 'AC Uninstallation', id FROM public.services WHERE name = 'AC Repair';
