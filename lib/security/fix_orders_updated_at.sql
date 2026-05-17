-- Fix missing updated_at column in orders table which causes errors in extend_order_deadline

-- 1. Add the column if it doesn't exist
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now());

-- 2. Create the update timestamp function if it doesn't exist
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 3. Create the trigger to automatically update the updated_at column
DROP TRIGGER IF EXISTS on_order_updated ON public.orders;

CREATE TRIGGER on_order_updated
    BEFORE UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE PROCEDURE public.handle_updated_at();

-- 4. Verify extend_order_deadline function also handles existing logic correctly
-- (Re-defining it potentially to ensure it's correct, but the column addition is the main fix)
