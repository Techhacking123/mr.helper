-- ========================================
-- FIX: START TIMERS FOR EXISTING VERIFIED ORDERS
-- ========================================
-- This fixes orders that were verified before the timer system was added

-- Check which verified orders don't have timers
SELECT 
  id,
  status,
  timer_started_at,
  timer_expires_at,
  created_at
FROM orders
WHERE status IN ('verified', 'working')
AND timer_expires_at IS NULL;

-- Start timers for existing verified/working orders
UPDATE orders
SET 
  timer_started_at = NOW(),
  timer_expires_at = NOW() + INTERVAL '24 hours',
  timer_reset_count = 0
WHERE status IN ('verified', 'working')
AND timer_expires_at IS NULL;

-- Verify the update
SELECT 
  id,
  status,
  timer_started_at,
  timer_expires_at,
  EXTRACT(EPOCH FROM (timer_expires_at - NOW())) / 3600 AS hours_remaining
FROM orders
WHERE status IN ('verified', 'working');
