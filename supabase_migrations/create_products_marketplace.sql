-- ============================================
-- Products Marketplace Tables
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. Products table
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  price NUMERIC NOT NULL,
  image_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Product Orders table
CREATE TABLE IF NOT EXISTS product_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  buyer_id UUID NOT NULL REFERENCES users(id),
  provider_id UUID NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'negotiating' CHECK (status IN ('negotiating', 'accepted', 'cancelled')),
  original_price NUMERIC NOT NULL,
  final_price NUMERIC,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Negotiation Messages table
CREATE TABLE IF NOT EXISTS negotiation_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_order_id UUID NOT NULL REFERENCES product_orders(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id),
  sender_role TEXT NOT NULL CHECK (sender_role IN ('buyer', 'provider')),
  action TEXT NOT NULL CHECK (action IN ('offer', 'counter_offer', 'accept', 'cancel')),
  amount NUMERIC,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- Indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_products_provider_id ON products(provider_id);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_orders_buyer ON product_orders(buyer_id);
CREATE INDEX IF NOT EXISTS idx_product_orders_provider ON product_orders(provider_id);
CREATE INDEX IF NOT EXISTS idx_product_orders_status ON product_orders(status);
CREATE INDEX IF NOT EXISTS idx_product_orders_product ON product_orders(product_id);

CREATE INDEX IF NOT EXISTS idx_negotiation_messages_order ON negotiation_messages(product_order_id);
CREATE INDEX IF NOT EXISTS idx_negotiation_messages_created ON negotiation_messages(created_at);

-- ============================================
-- RLS Policies
-- ============================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE negotiation_messages ENABLE ROW LEVEL SECURITY;

-- Products: anon full access (app-level auth)
CREATE POLICY "Anon Full Policy Products" ON products FOR ALL USING (true) WITH CHECK (true);

-- Product Orders: anon full access
CREATE POLICY "Anon Full Policy Product Orders" ON product_orders FOR ALL USING (true) WITH CHECK (true);

-- Negotiation Messages: anon full access
CREATE POLICY "Anon Full Policy Negotiation Messages" ON negotiation_messages FOR ALL USING (true) WITH CHECK (true);

-- ============================================
-- Triggers: Auto-update updated_at
-- ============================================
CREATE TRIGGER update_product_orders_updated_at
  BEFORE UPDATE ON product_orders
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Storage Bucket
-- ============================================
-- Run this separately or create bucket 'product-images' in Supabase Dashboard > Storage
-- INSERT INTO storage.buckets (id, name, public) VALUES ('product-images', 'product-images', true);
