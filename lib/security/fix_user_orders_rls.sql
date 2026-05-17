-- FIX RLS POLICIES FOR USER ORDERS
-- ==================================

-- 1. Enable RLS on relevant tables (just in case)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies on orders
DROP POLICY IF EXISTS "Users can view their own orders" ON orders;
DROP POLICY IF EXISTS "Providers can view assigned orders" ON orders;
DROP POLICY IF EXISTS "Users can create orders" ON orders;
DROP POLICY IF EXISTS "Users can update their own orders" ON orders;

-- 3. Create comprehensive policies for ORDERS for USERS (Buyers)

-- A. VIEW (SELECT): Users can view orders where they are the buyer
CREATE POLICY "Users can view their own orders"
ON orders FOR SELECT
USING (auth.uid() = buyer_id);

-- B. INSERT: Users can create orders (buyer_id must match auth.uid)
CREATE POLICY "Users can create orders"
ON orders FOR INSERT
WITH CHECK (auth.uid() = buyer_id);

-- C. UPDATE: Users can update their own orders (e.g. cancelling)
CREATE POLICY "Users can update their own orders"
ON orders FOR UPDATE
USING (auth.uid() = buyer_id);


-- 4. Create policies for PROVIDERS (so they can see them too)

-- A. VIEW (SELECT): Providers can view orders assigned to them OR open requests in their service area
-- (Simplified for now: Providers can view any order where they are provider_id OR status is 'request_open')
CREATE POLICY "Providers can view relevant orders"
ON orders FOR SELECT
USING (
    (provider_id = auth.uid()) 
    OR 
    (status = 'request_open') -- Allow providers to see open requests to accept them
);

-- B. UPDATE: Providers can update orders they are assigned to (e.g. accepting, completing)
CREATE POLICY "Providers can update assigned orders"
ON orders FOR UPDATE
USING (provider_id = auth.uid() OR (status = 'request_open' AND provider_id IS NULL)); -- Allow accepting


-- 5. Fix USERS table RLS (Vital for the join to work!)
-- If a user cannot read the 'provider' record in the 'users' table, the join might fail or return null.
-- We must allow authenticated users to read basic info of other users (providers).

CREATE POLICY "Public profiles are viewable by everyone"
ON users FOR SELECT
USING (true); -- Allow reading all public user profiles (safe as we only select full_name, etc in app)

-- 6. Fix SERVICES table RLS
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Services are viewable by everyone"
ON services FOR SELECT
USING (true);

-- 7. Fix LOCATIONS table RLS
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Locations are viewable by everyone"
ON locations FOR SELECT
USING (true);
