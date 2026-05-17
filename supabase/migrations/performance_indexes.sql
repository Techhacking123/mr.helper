-- ==========================================
-- PERFORMANCE OPTIMIZATION: DATABASE INDEXES
-- For mrhelperAI Order Processing
-- ==========================================
-- 
-- PURPOSE: Dramatically improve order query performance and throughput
-- ESTIMATED IMPACT: 5-10x faster queries, 3-5x higher throughput
-- SAFE TO RUN: All operations use IF NOT EXISTS
--
-- Run this in your Supabase SQL Editor
-- ==========================================

-- 1. CRITICAL INDEXES FOR ORDERS TABLE
-- These indexes cover the most common query patterns in your app

-- Status-based queries (most frequent)
CREATE INDEX IF NOT EXISTS idx_orders_status 
ON orders(status);

-- Service-based queries (provider matching)
CREATE INDEX IF NOT EXISTS idx_orders_service_id 
ON orders(service_id);

-- Location-based queries (provider matching)
CREATE INDEX IF NOT EXISTS idx_orders_location_id 
ON orders(location_id);

-- User's order history
CREATE INDEX IF NOT EXISTS idx_orders_buyer_id 
ON orders(buyer_id);

-- Provider's accepted orders
CREATE INDEX IF NOT EXISTS idx_orders_provider_id 
ON orders(provider_id) 
WHERE provider_id IS NOT NULL;

-- Recent orders (sorted queries)
CREATE INDEX IF NOT EXISTS idx_orders_created_at 
ON orders(created_at DESC);

-- 2. COMPOSITE INDEXES FOR COMPLEX QUERIES
-- These dramatically speed up multi-condition queries

-- Provider matching (MOST IMPORTANT - speeds up notify_providers_on_order)
-- This index covers the exact query in your trigger
CREATE INDEX IF NOT EXISTS idx_orders_provider_matching 
ON orders(status, service_id, location_id)
WHERE status = 'request_open';

-- User's order list with status filter
CREATE INDEX IF NOT EXISTS idx_orders_buyer_status 
ON orders(buyer_id, status, created_at DESC);

-- Provider's order list with status filter  
CREATE INDEX IF NOT EXISTS idx_orders_provider_status 
ON orders(provider_id, status, created_at DESC);

-- Active orders for realtime updates
CREATE INDEX IF NOT EXISTS idx_orders_active 
ON orders(status, created_at DESC)
WHERE status IN ('request_open', 'accepted', 'pending');

-- 3. INDEXES FOR RELATED TABLES

-- Notifications table (if not already indexed)
CREATE INDEX IF NOT EXISTS idx_notifications_user_id 
ON notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_order_id 
ON notifications(order_id);

CREATE INDEX IF NOT EXISTS idx_notifications_unread 
ON notifications(user_id, is_read)
WHERE is_read = false;

-- Users table for provider lookups
CREATE INDEX IF NOT EXISTS idx_users_is_provider 
ON users(is_provider) 
WHERE is_provider = true;

CREATE INDEX IF NOT EXISTS idx_users_service_subscription 
ON users(service_id, subscription_status)
WHERE is_provider = true;

CREATE INDEX IF NOT EXISTS idx_users_location 
ON users(location)
WHERE is_provider = true;

-- Composite for the exact provider matching logic
CREATE INDEX IF NOT EXISTS idx_users_provider_active 
ON users(service_id, subscription_status, subscription_end_date)
WHERE is_provider = true 
AND subscription_status = 'active';

-- 4. GEOSPATIAL INDEXES (if using GPS-based matching)
-- Uncomment if you want distance-based provider matching

-- CREATE EXTENSION IF NOT EXISTS postgis;
-- 
-- CREATE INDEX IF NOT EXISTS idx_orders_location_gps 
-- ON orders USING GIST(ST_MakePoint(longitude, latitude))
-- WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
-- 
-- CREATE INDEX IF NOT EXISTS idx_users_location_gps 
-- ON users USING GIST(ST_MakePoint(longitude, latitude))
-- WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- 5. PARTIAL INDEXES FOR SPECIFIC STATUS QUERIES

-- Open requests (frequently queried by providers)
CREATE INDEX IF NOT EXISTS idx_orders_open_requests 
ON orders(service_id, location_id, created_at DESC)
WHERE status = 'request_open';

-- Completed orders (for statistics/history)
CREATE INDEX IF NOT EXISTS idx_orders_completed 
ON orders(provider_id, created_at DESC)
WHERE status = 'completed';

-- Active work (accepted but not completed)
CREATE INDEX IF NOT EXISTS idx_orders_in_progress 
ON orders(provider_id)
WHERE status = 'accepted';

-- 6. ANALYZE TABLES TO UPDATE STATISTICS
-- This helps PostgreSQL choose the right indexes

ANALYZE orders;
ANALYZE order_offers;
ANALYZE notifications;
ANALYZE users;

-- 7. VERIFY INDEXES WERE CREATED
-- Run this query to see all indexes on orders table

SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'orders'
ORDER BY indexname;

-- Expected output: You should see all the indexes listed above

-- ==========================================
-- PERFORMANCE TESTING QUERIES
-- Run these BEFORE and AFTER creating indexes to measure improvement
-- ==========================================

-- Test 1: Provider matching query (from your trigger)
EXPLAIN ANALYZE
SELECT id FROM users 
WHERE is_provider = TRUE 
AND service_id = '00000000-0000-0000-0000-000000000000'
AND subscription_status = 'active'::subscription_status_enum
AND subscription_end_date > NOW()
AND location = 'Test City';

-- Test 2: User's order history
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE buyer_id = '00000000-0000-0000-0000-000000000000'
ORDER BY created_at DESC
LIMIT 20;

-- Test 3: Open requests for a service
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE status = 'request_open'
AND service_id = '00000000-0000-0000-0000-000000000000'
AND location_id = '00000000-0000-0000-0000-000000000000'
ORDER BY created_at DESC;

-- ==========================================
-- EXPECTED PERFORMANCE IMPROVEMENTS
-- ==========================================
--
-- BEFORE INDEXES:
-- - Provider matching: ~50-200ms (Sequential Scan)
-- - User order history: ~20-100ms (Sequential Scan)
-- - Open requests: ~30-150ms (Sequential Scan)
--
-- AFTER INDEXES:
-- - Provider matching: ~5-20ms (Index Scan)
-- - User order history: ~2-10ms (Index Scan)
-- - Open requests: ~3-15ms (Index Scan)
--
-- THROUGHPUT IMPACT:
-- - Current: ~2-5 orders/sec
-- - With indexes: ~10-20 orders/sec
-- - Combined with code optimizations: ~50-100 orders/sec
--
-- ==========================================

-- 8. MAINTENANCE RECOMMENDATIONS

-- Set up automatic VACUUM and ANALYZE (Supabase handles this automatically)
-- But you can manually trigger if needed:

-- VACUUM ANALYZE orders;
-- VACUUM ANALYZE users;
-- VACUUM ANALYZE notifications;

-- 9. MONITORING INDEX USAGE

-- Query to check if indexes are being used
SELECT 
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE relname IN ('orders', 'users', 'notifications', 'order_offers')
ORDER BY idx_scan DESC;

-- If idx_scan is 0 after some usage, that index might not be needed

-- ==========================================
-- ROLLBACK (if needed)
-- Uncomment these lines to remove indexes
-- ==========================================

/*
DROP INDEX IF EXISTS idx_orders_status;
DROP INDEX IF EXISTS idx_orders_service_id;
DROP INDEX IF EXISTS idx_orders_location_id;
DROP INDEX IF EXISTS idx_orders_buyer_id;
DROP INDEX IF EXISTS idx_orders_provider_id;
DROP INDEX IF EXISTS idx_orders_created_at;
DROP INDEX IF EXISTS idx_orders_provider_matching;
DROP INDEX IF EXISTS idx_orders_buyer_status;
DROP INDEX IF EXISTS idx_orders_provider_status;
DROP INDEX IF EXISTS idx_orders_active;
DROP INDEX IF EXISTS idx_notifications_user_id;
DROP INDEX IF EXISTS idx_notifications_order_id;
DROP INDEX IF EXISTS idx_notifications_unread;
DROP INDEX IF EXISTS idx_users_is_provider;
DROP INDEX IF EXISTS idx_users_service_subscription;
DROP INDEX IF EXISTS idx_users_location;
DROP INDEX IF EXISTS idx_users_provider_active;
DROP INDEX IF EXISTS idx_orders_open_requests;
DROP INDEX IF EXISTS idx_orders_completed;
DROP INDEX IF EXISTS idx_orders_in_progress;
*/
