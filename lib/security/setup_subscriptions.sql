-- Create Subscriptions Table
create table if not exists public.subscriptions (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.users(id) not null,
  razorpay_subscription_id text,
  razorpay_payment_id text,
  plan_id text,
  status text default 'created', -- created, authenticated, active, halted, cancelled, expired, failed
  start_date timestamptz,
  next_billing_date timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Enable RLS
alter table public.subscriptions enable row level security;

-- Policies
create policy "Users can view own subscriptions" 
  on public.subscriptions 
  for select 
  using (auth.uid() = user_id);

create policy "Users can update own subscriptions" 
  on public.subscriptions 
  for update 
  using (auth.uid() = user_id);

-- Add column to users for quick access (optional but requested to mark user as subscribed)
alter table public.users add column if not exists is_subscribed boolean default false;

-- Function to handle updated_at
create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language 'plpgsql';

create trigger update_subscriptions_updated_at
before update on public.subscriptions
for each row
execute procedure update_updated_at_column();
