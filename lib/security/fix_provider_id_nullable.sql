-- Make provider_id nullable to support 'request_open' orders (Open Job Market)
ALTER TABLE orders ALTER COLUMN provider_id DROP NOT NULL;

-- Make sure RLS policies allow inserting/updating independent of provider_id
-- (Existing policies often check provider_id = auth.uid(), we need to ensure they handle nulls for new requests)
-- Checks:
-- 'request_open' orders have NO provider.
-- user (buyer) inserts order where provider_id is NULL.

-- Verify if we need to adjust constraints or policies (usually DROP NOT NULL is enough for the constraint error).
