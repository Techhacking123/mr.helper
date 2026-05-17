-- Enable RLS on service_types (good practice)
ALTER TABLE service_types ENABLE ROW LEVEL SECURITY;

-- Allow public read access to service_types
-- This ensures users and providers can search for services
DROP POLICY IF EXISTS "Public Read Service Types" ON service_types;
CREATE POLICY "Public Read Service Types"
ON service_types FOR SELECT
USING (true);

-- Ensure services table is also readable
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read Services" ON services;
CREATE POLICY "Public Read Services"
ON services FOR SELECT
USING (true);
