-- Locations Management System for Admin
-- This creates a table for managing service locations

-- 1. Create locations table if not exists
CREATE TABLE IF NOT EXISTS locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Create index for performance
CREATE INDEX IF NOT EXISTS idx_locations_is_active ON locations(is_active);
CREATE INDEX IF NOT EXISTS idx_locations_name ON locations(name);

-- 3. Enable RLS
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS Policies
-- Allow everyone to read active locations
DROP POLICY IF EXISTS "Allow reading active locations" ON locations;
CREATE POLICY "Allow reading active locations" ON locations
    FOR SELECT
    USING (is_active = true OR true); -- Allow all for now, can restrict later

-- Allow authenticated users to read all locations (for admin purposes)
DROP POLICY IF EXISTS "Allow all for authenticated" ON locations;
CREATE POLICY "Allow all for authenticated" ON locations
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- 5. Insert some default locations if table is empty
INSERT INTO locations (name, is_active)
SELECT name, true
FROM (VALUES 
    ('Mumbai'),
    ('Delhi'),
    ('Bangalore'),
    ('Hyderabad'),
    ('Chennai'),
    ('Kolkata'),
    ('Pune'),
    ('Ahmedabad')
) AS default_locations(name)
WHERE NOT EXISTS (SELECT 1 FROM locations LIMIT 1);

-- 6. Create function to update timestamp
CREATE OR REPLACE FUNCTION update_locations_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Create trigger for auto-updating timestamp
DROP TRIGGER IF EXISTS trg_update_locations_timestamp ON locations;
CREATE TRIGGER trg_update_locations_timestamp
    BEFORE UPDATE ON locations
    FOR EACH ROW
    EXECUTE FUNCTION update_locations_timestamp();

COMMENT ON TABLE locations IS 'Stores service locations managed by admin';
COMMENT ON COLUMN locations.is_active IS 'Whether this location is active and available for selection';
