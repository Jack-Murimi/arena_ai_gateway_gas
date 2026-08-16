-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0003
-- Product types (refill / cylinder / accessory / service), full refill size
-- catalogue, director role, and price-change approval workflow.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Product type
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.product_type as enum ('refill', 'cylinder', 'accessory', 'service');
exception when duplicate_object then null; end $$;

alter table public.products
  add column if not exists product_type public.product_type not null default 'refill';

-- ---------------------------------------------------------------------------
-- 2. Director role (can confirm price changes, like admin)
-- ---------------------------------------------------------------------------
alter type public.user_role add value if not exists 'director';

-- ---------------------------------------------------------------------------
-- 3. Complete refill catalogue (3, 6, 13, 22.5, 35, 45, 50 kg)
--    plus starter cylinder / accessory / service products
-- ---------------------------------------------------------------------------
insert into public.products (name, size_kg, brand, sale_price, cost_price, low_stock_threshold, product_type)
select seed.name, seed.size_kg, seed.brand, seed.sale_price, seed.cost_price,
       seed.low_stock_threshold, seed.product_type::public.product_type
from (values
  ('Refill 3kg',    3,    'Gateway', 550,  450, 10, 'refill'),
  ('Refill 22.5kg', 22.5, 'Gateway', 3350, 2900, 10, 'refill'),
  ('Refill 35kg',   35,   'Gateway', 5200, 4600, 5, 'refill'),
  ('Refill 45kg',   45,   'Gateway', 6700, 5900, 5, 'refill'),
  ('Empty Cylinder 13kg', 13, 'Gateway', 2800, 2300, 5, 'cylinder'),
  ('Regulator',     null, null, 450,  380, 10, 'accessory'),
  ('Hose 1m',       null, null, 350,  250, 10, 'accessory'),
  ('Installation',  null, null, 500,  0, 0, 'service')
) as seed (name, size_kg, brand, sale_price, cost_price, low_stock_threshold, product_type)
where not exists (select 1 from public.products p where p.name = seed.name);

update public.products set product_type = 'refill' where product_type is null;

-- ---------------------------------------------------------------------------
-- 4. Price change requests (flagged at POS; confirmed by admin/director)
-- ---------------------------------------------------------------------------
create table public.price_change_requests (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  sale_id uuid references public.sales (id) on delete set null,
  old_price numeric(12,2) not null check (old_price >= 0),
  new_price numeric(12,2) not null check (new_price >= 0),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  changed_by uuid references public.profiles (id) on delete set null,
  confirmed_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,
  note text,
  created_at timestamptz not null default now()
);

create index price_change_requests_status_idx on public.price_change_requests (status);
create index price_change_requests_product_idx on public.price_change_requests (product_id);

-- ---------------------------------------------------------------------------
-- 5. RLS — price changes: anyone logged in can flag, only admin/director
--    can confirm/reject. Product price edits: admin/director only.
-- ---------------------------------------------------------------------------
alter table public.price_change_requests enable row level security;

create or replace function public.is_admin_or_director()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'director')
  );
$$;

create policy "price_changes_select"
  on public.price_change_requests for select to authenticated using (true);
create policy "price_changes_insert"
  on public.price_change_requests for insert to authenticated with check (true);
create policy "price_changes_review"
  on public.price_change_requests for update to authenticated
  using (public.is_admin_or_director())
  with check (public.is_admin_or_director());
create policy "price_changes_delete"
  on public.price_change_requests for delete to authenticated
  using (public.is_admin_or_director());

-- Products: keep select/insert open to all authenticated, but updates
-- (including selling prices) and deletes are admin/director only.
drop policy if exists "products_all_authenticated" on public.products;
create policy "products_select"
  on public.products for select to authenticated using (true);
create policy "products_insert"
  on public.products for insert to authenticated with check (true);
create policy "products_update_admin"
  on public.products for update to authenticated
  using (public.is_admin_or_director())
  with check (public.is_admin_or_director());
create policy "products_delete_admin"
  on public.products for delete to authenticated
  using (public.is_admin_or_director());
