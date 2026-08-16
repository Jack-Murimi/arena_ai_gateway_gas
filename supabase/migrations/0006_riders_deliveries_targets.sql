-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0006
-- Riders, deliveries, targets & real branches
--
-- * Branches: Nextgen, Jamhuri, Lavington (replaces 'Main Branch')
-- * New role: rider (auth users who only see their deliveries)
-- * deliveries table (status lifecycle: pending -> assigned ->
--   picked_up -> delivered / cancelled)
-- * rider_targets (per rider per month: delivery count + amount)
-- * rider_delivery_stats view for performance screens
-- * Security-definer RPCs so admins can create riders & set targets
--   from the app (auth.users is not writable via the client key)
-- * Seeds the three riders (Romano Sifuna, Jackson Nyakundi,
--   Kelvin Omondi) with login accounts + sample deliveries/targets
-- ============================================================================

create extension if not exists pgcrypto with schema public;

-- Idempotency guards (the first attempt failed mid-seed; tracking table
-- means this file runs again exactly once, so reset its own objects safely)
drop view if exists public.rider_delivery_stats;
drop table if exists public.deliveries cascade;
drop table if exists public.rider_targets cascade;
drop type if exists public.delivery_status;

-- ---------------------------------------------------------------------------
-- 1. Real branches
-- ---------------------------------------------------------------------------
delete from public.branches;
insert into public.branches (name, location) values
  ('Nextgen',   'Nextgen Mall area'),
  ('Jamhuri',   'Jamhuri Estate'),
  ('Lavington', 'Lavington');

-- ---------------------------------------------------------------------------
-- 2. Rider role
-- ---------------------------------------------------------------------------
alter type public.user_role add value if not exists 'rider';

-- ---------------------------------------------------------------------------
-- 3. Deliveries
-- ---------------------------------------------------------------------------
create type public.delivery_status as enum
  ('pending', 'assigned', 'picked_up', 'delivered', 'cancelled');

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references public.branches (id) on delete set null,
  rider_id uuid references public.profiles (id) on delete set null,
  customer_name text not null,
  location text,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  status public.delivery_status not null default 'pending',
  note text,
  created_at timestamptz not null default now(),
  assigned_at timestamptz,
  delivered_at timestamptz
);

create index deliveries_rider_idx on public.deliveries (rider_id, status);
create index deliveries_branch_idx on public.deliveries (branch_id);
create index deliveries_created_idx on public.deliveries (created_at desc);

-- ---------------------------------------------------------------------------
-- 4. Rider targets (per rider per month)
-- ---------------------------------------------------------------------------
create table public.rider_targets (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.profiles (id) on delete cascade,
  month date not null, -- first day of month, e.g. 2026-08-01
  target_deliveries integer not null default 0 check (target_deliveries >= 0),
  target_amount numeric(12,2) not null default 0 check (target_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (rider_id, month)
);

create trigger trg_rider_targets_updated_at before update on public.rider_targets
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 5. Performance view
-- ---------------------------------------------------------------------------
create or replace view public.rider_delivery_stats as
select
  p.id as rider_id,
  p.full_name,
  p.phone,
  p.branch_id,
  b.name as branch_name,
  count(d.id) filter (where d.status = 'delivered') as delivered_count,
  coalesce(sum(d.amount) filter (where d.status = 'delivered'), 0) as delivered_amount,
  count(d.id) filter (where d.status in ('pending', 'assigned', 'picked_up')) as pending_count
from public.profiles p
left join public.branches b on b.id = p.branch_id
left join public.deliveries d on d.rider_id = p.id
where p.role = 'rider'
group by p.id, p.full_name, p.phone, p.branch_id, b.name;

grant select on public.rider_delivery_stats to authenticated;

-- ---------------------------------------------------------------------------
-- 6. RLS
-- ---------------------------------------------------------------------------
alter table public.deliveries   enable row level security;
alter table public.rider_targets enable row level security;

create policy "deliveries_all_authenticated"
  on public.deliveries for all to authenticated using (true) with check (true);
create policy "rider_targets_all_authenticated"
  on public.rider_targets for all to authenticated using (true) with check (true);

grant select, insert, update, delete on public.deliveries to authenticated;
grant select, insert, update, delete on public.rider_targets to authenticated;

-- ---------------------------------------------------------------------------
-- 7. RPCs (security definer; only admin/director may call)
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_rider(
  p_email text,
  p_password text,
  p_full_name text,
  p_phone text,
  p_branch_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;

  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;

  if v_uid is not null then
    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           email_confirmed_at = now()
     where id = v_uid;
    update public.profiles
       set full_name = p_full_name, phone = p_phone, branch_id = p_branch_id, role = 'rider'
     where id = v_uid;
    return v_uid;
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated', lower(p_email),
    crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    now(), now(), '', '', '', ''
  )
  returning id into v_uid;

  update public.profiles
     set full_name = p_full_name, phone = p_phone, branch_id = p_branch_id, role = 'rider'
   where id = v_uid;

  return v_uid;
end;
$$;

create or replace function public.admin_set_rider_target(
  p_rider_id uuid,
  p_month date,
  p_target_deliveries integer,
  p_target_amount numeric
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  insert into public.rider_targets (rider_id, month, target_deliveries, target_amount)
  values (p_rider_id, date_trunc('month', p_month)::date, p_target_deliveries, p_target_amount)
  on conflict (rider_id, month)
  do update set target_deliveries = excluded.target_deliveries,
                target_amount = excluded.target_amount;
end;
$$;

grant execute on function public.admin_create_rider(text, text, text, text, uuid) to authenticated;
grant execute on function public.admin_set_rider_target(uuid, date, integer, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Seed riders (login: email / Gateway@2026)
-- ---------------------------------------------------------------------------
do $$
declare
  v_romano uuid; v_jackson uuid; v_kelvin uuid;
  v_nextgen uuid; v_jamhuri uuid; v_lavington uuid;
begin
  select id into v_nextgen  from public.branches where name = 'Nextgen';
  select id into v_jamhuri  from public.branches where name = 'Jamhuri';
  select id into v_lavington from public.branches where name = 'Lavington';

  -- Romano Sifuna (Lavington)
  select id into v_romano from auth.users where email = 'romano@gatewaygas.co.ke';
  if v_romano is null then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      'romano@gatewaygas.co.ke', crypt('Gateway@2026', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{"full_name":"Romano Sifuna"}',
      now(), now(), '', '', '', '')
    returning id into v_romano;
  end if;
  update public.profiles set full_name = 'Romano Sifuna', phone = '0711 000 001',
    branch_id = v_lavington, role = 'rider' where id = v_romano;

  -- Jackson Nyakundi (Jamhuri)
  select id into v_jackson from auth.users where email = 'jackson@gatewaygas.co.ke';
  if v_jackson is null then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      'jackson@gatewaygas.co.ke', crypt('Gateway@2026', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{"full_name":"Jackson Nyakundi"}',
      now(), now(), '', '', '', '')
    returning id into v_jackson;
  end if;
  update public.profiles set full_name = 'Jackson Nyakundi', phone = '0711 000 002',
    branch_id = v_jamhuri, role = 'rider' where id = v_jackson;

  -- Kelvin Omondi (Nextgen)
  select id into v_kelvin from auth.users where email = 'kelvin@gatewaygas.co.ke';
  if v_kelvin is null then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      'kelvin@gatewaygas.co.ke', crypt('Gateway@2026', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{"full_name":"Kelvin Omondi"}',
      now(), now(), '', '', '', '')
    returning id into v_kelvin;
  end if;
  update public.profiles set full_name = 'Kelvin Omondi', phone = '0711 000 003',
    branch_id = v_nextgen, role = 'rider' where id = v_kelvin;

  -- Targets for current month (direct insert — RPC is for the app's admin UI)
  insert into public.rider_targets (rider_id, month, target_deliveries, target_amount) values
    (v_romano,  date_trunc('month', now())::date, 60, 240000),
    (v_jackson, date_trunc('month', now())::date, 50, 200000),
    (v_kelvin,  date_trunc('month', now())::date, 45, 180000)
  on conflict (rider_id, month) do nothing;

  -- Sample deliveries (mix of delivered & pending for testing)
  insert into public.deliveries
    (branch_id, rider_id, customer_name, location, amount, status, note, created_at, delivered_at)
  values
    (v_lavington, v_romano, 'Mama Njeri',   'House 12, Lavington Green', 1950, 'delivered', null,
     now() - interval '2 days', now() - interval '2 days' + interval '3 hours'),
    (v_nextgen,   v_romano, 'Kaka Centre',  'Shop 3, Nextgen Mall',      7300, 'delivered', '50kg refill',
     now() - interval '1 day', now() - interval '1 day' + interval '2 hours'),
    (v_lavington, v_romano, 'Riverside Apts','Block B, Riverside',       2000, 'pending',   null, now(), null),
    (v_jamhuri,   v_jackson,'Mama Wanjiku', 'Jamhuri Estate Stage',      1000, 'delivered', null,
     now() - interval '3 days', now() - interval '3 days' + interval '2 hours'),
    (v_jamhuri,   v_jackson,'Blue House',   'Jamhuri, near school',      3400, 'delivered', null,
     now() - interval '1 day', now() - interval '1 day' + interval '90 minutes'),
    (v_jamhuri,   v_jackson,'Total Station','Jamhuri High',              1950, 'pending',   null, now(), null),
    (v_nextgen,   v_kelvin, 'Karura Villas','Nextgen Road',              2000, 'delivered', null,
     now() - interval '2 days', now() - interval '2 days' + interval '2 hours'),
    (v_nextgen,   v_kelvin, 'Kasarani Shop','Kasarani Mwiki',            1000, 'pending',   null, now(), null),
    (v_lavington, v_kelvin, 'River House',  'Lavington, River Rd',       1950, 'pending',   null, now(), null);
end $$;
