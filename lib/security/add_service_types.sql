-- Create table for sub-services (Service Types)
create table if not exists public.service_types (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  service_id uuid references public.services(id) on delete cascade not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- RLS Policies
alter table public.service_types enable row level security;

create policy "Enable read access for all users"
on public.service_types for select
using (true);

create policy "Enable all access for admins"
on public.service_types for all
using (
  auth.uid() in (
    select id from public.users where email = 'adime' -- or role check
  )
);

-- Seed initial data (This requires knowing the IDs of existing services, which is hard in a script without knowing them. 
-- We will leave seeding to the Admin UI or a separate script if we can query first.
-- For now, the user can use the Admin UI to populate it.)
