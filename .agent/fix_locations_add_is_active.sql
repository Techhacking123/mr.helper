-- Fix: Add is_active column to existing locations table
-- If the locations table already exists without is_active column

-- 1. Add is_active column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'locations' 
        AND column_name = 'is_active'
    ) THEN
        ALTER TABLE locations ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;
END $$;

-- 2. Add updated_at column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'locations' 
        AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE locations ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- 3. Set all existing locations to active
UPDATE locations SET is_active = true WHERE is_active IS NULL;

-- 4. Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_locations_is_active ON locations(is_active);
CREATE INDEX IF NOT EXISTS idx_locations_name ON locations(name);

-- 5. Create function to update timestamp
CREATE OR REPLACE FUNCTION update_locations_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Create trigger for auto-updating timestamp
DROP TRIGGER IF EXISTS trg_update_locations_timestamp ON locations;
CREATE TRIGGER trg_update_locations_timestamp
    BEFORE UPDATE ON locations
    FOR EACH ROW
    EXECUTE FUNCTION update_locations_timestamp();

-- 7. Update RLS policies
-- Drop old policies if they exist
DROP POLICY IF EXISTS "Allow reading active locations" ON locations;
DROP POLICY IF EXISTS "Allow all for authenticaROW LEVEL SECURITY;

-- Create new policies
CREATE POLICY "Allow reading active locations" ON locations
    FOR SELECT
    USING (is_active = true OR true); -- Allow all for now

CREATE POLICY "Allow all for authenticated" ON locations
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- 8. Verify the changes
SELECT 
    column_name, 
    data_type, 
    column_default,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'locations'
ORDER BY ordinal_position;
ted" ON locations;

-- Enable RLS if not already enabled
ALTER TABLE locations ENABLE 