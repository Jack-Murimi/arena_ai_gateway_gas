-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Initial database schema
-- Version 1 (2026-08-16)
--
-- How to apply:
--   Option A (recommended for now): open your Supabase project →
--   SQL Editor → paste this entire file → Run.
--   Option B (CLI): `supabase db push` with the CLI linked to your project.
--
-- Covers: branches, profiles (roles), products, stock per branch,
-- customers (credit), suppliers, sales & sale items, payments,
-- cylinder deposits, stock movements, RLS policies, seed data.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('admin', 'cashier', 'stock_manager');
create type public.payment_method as enum ('cash', 'mpesa', 'credit');
create type public.stock_movement_type as enum (
  'purchase', 'sale', 'adjustment', 'return', 'transfer'
);

-- ---------------------------------------------------------------------------
-- BRANCHES
-- ---------------------------------------------------------------------------
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- PROFILES (one row per auth user)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  role public.user_role not null default 'cashier',
  branch_id uuid references public.branches (id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- PRODUCTS (gas cylinders / refills)
-- ---------------------------------------------------------------------------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  size_kg numeric(6,2),
  brand text,
  sale_price numeric(12,2) not null default 0 check (sale_price >= 0),
  cost_price numeric(12,2) not null default 0 check (cost_price >= 0),
  low_stock_threshold integer not null default 5,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index products_active_idx on public.products (is_active);

-- Stock balance per branch (denormalized; maintained by stock_movements trigger)
create table public.product_stock (
  branch_id uuid not null references public.branches (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (branch_id, product_id)
);

-- ---------------------------------------------------------------------------
-- CUSTOMERS (incl. credit accounts)
-- ---------------------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  credit_limit numeric(12,2) not null default 0 check (credit_limit >= 0),
  balance numeric(12,2) not null default 0 check (balance >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index customers_name_idx on public.customers (lower(name));

-- ---------------------------------------------------------------------------
-- SUPPLIERS
-- ---------------------------------------------------------------------------
create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  contact_person text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- SALES & SALE ITEMS
-- ---------------------------------------------------------------------------
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  invoice_no text not null unique,
  branch_id uuid not null references public.branches (id),
  cashier_id uuid not null references public.profiles (id),
  customer_id uuid references public.customers (id) on delete set null,
  subtotal numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  status text not null default 'complete' check (status in ('complete', 'void')),
  note text,
  created_at timestamptz not null default now()
);

create index sales_created_at_idx on public.sales (created_at desc);
create index sales_customer_idx on public.sales (customer_id);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  product_id uuid not null references public.products (id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0)
);

create index sale_items_sale_idx on public.sale_items (sale_id);

-- ---------------------------------------------------------------------------
-- PAYMENTS (cash / M-Pesa / credit)
-- ---------------------------------------------------------------------------
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid references public.sales (id) on delete set null,
  customer_id uuid references public.customers (id) on delete set null,
  amount numeric(12,2) not null check (amount > 0),
  method public.payment_method not null default 'cash',
  mpesa_code text,
  received_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create index payments_created_at_idx on public.payments (created_at desc);

-- ---------------------------------------------------------------------------
-- CYLINDER DEPOSITS (customer pays deposit; returned on swap/refund)
-- ---------------------------------------------------------------------------
create table public.cylinder_deposits (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  quantity integer not null default 1 check (quantity > 0),
  deposit_amount numeric(12,2) not null default 0 check (deposit_amount >= 0),
  status text not null default 'held' check (status in ('held', 'returned')),
  acquired_at timestamptz not null default now(),
  returned_at timestamptz
);

create index cylinder_deposits_customer_idx
  on public.cylinder_deposits (customer_id) where (status = 'held');

-- ---------------------------------------------------------------------------
-- STOCK MOVEMENTS (audit log; updates product_stock via trigger)
-- ---------------------------------------------------------------------------
create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id),
  product_id uuid not null references public.products (id),
  quantity_change integer not null, -- positive = in, negative = out
  movement_type public.stock_movement_type not null,
  reference_id uuid, -- e.g. the sale/purchase id
  note text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create index stock_movements_created_at_idx
  on public.stock_movements (created_at desc);

-- ---------------------------------------------------------------------------
-- TRIGGERS
-- ---------------------------------------------------------------------------

-- Keep updated_at fresh on core tables
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_branches_updated_at before update on public.branches
  for each row execute function public.set_updated_at();
create trigger trg_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.set_updated_at();
create trigger trg_customers_updated_at before update on public.customers
  for each row execute function public.set_updated_at();
create trigger trg_suppliers_updated_at before update on public.suppliers
  for each row execute function public.set_updated_at();
create trigger trg_product_stock_updated_at before update on public.product_stock
  for each row execute function public.set_updated_at();

-- Every stock movement updates the branch product balance
create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
as $$
begin
  insert into public.product_stock (branch_id, product_id, quantity)
  values (new.branch_id, new.product_id, new.quantity_change)
  on conflict (branch_id, product_id)
  do update set quantity = public.product_stock.quantity + excluded.quantity;
  return new;
end;
$$;

create trigger trg_apply_stock_movement after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

-- New auth user → create a profile row automatically
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
-- Every table is locked down to authenticated users only.
-- NOTE: for stricter per-role rules (e.g. only admins edit prices), add
-- `exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')`
-- clauses in a follow-up migration once roles are settled.

alter table public.branches          enable row level security;
alter table public.profiles          enable row level security;
alter table public.products          enable row level security;
alter table public.product_stock     enable row level security;
alter table public.customers         enable row level security;
alter table public.suppliers         enable row level security;
alter table public.sales             enable row level security;
alter table public.sale_items        enable row level security;
alter table public.payments          enable row level security;
alter table public.cylinder_deposits enable row level security;
alter table public.stock_movements   enable row level security;

-- Helper policies: any authenticated user can read; profile rows are special.
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (
    auth.uid() = id
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id);

create policy "branches_all_authenticated"
  on public.branches for all to authenticated using (true) with check (true);
create policy "products_all_authenticated"
  on public.products for all to authenticated using (true) with check (true);
create policy "product_stock_all_authenticated"
  on public.product_stock for all to authenticated using (true) with check (true);
create policy "customers_all_authenticated"
  on public.customers for all to authenticated using (true) with check (true);
create policy "suppliers_all_authenticated"
  on public.suppliers for all to authenticated using (true) with check (true);
create policy "sales_all_authenticated"
  on public.sales for all to authenticated using (true) with check (true);
create policy "sale_items_all_authenticated"
  on public.sale_items for all to authenticated using (true) with check (true);
create policy "payments_all_authenticated"
  on public.payments for all to authenticated using (true) with check (true);
create policy "cylinder_deposits_all_authenticated"
  on public.cylinder_deposits for all to authenticated using (true) with check (true);
create policy "stock_movements_all_authenticated"
  on public.stock_movements for all to authenticated using (true) with check (true);

-- ---------------------------------------------------------------------------
-- SEED DATA (safe to re-run; only inserts when tables are empty)
-- ---------------------------------------------------------------------------
insert into public.branches (name, location, phone)
select 'Main Branch', 'Nairobi', '07XX XXX XXX'
where not exists (select 1 from public.branches);

insert into public.products (name, size_kg, brand, sale_price, cost_price, low_stock_threshold)
select * from (values
  ('Refill 6kg',  6,  'Gateway', 950,  800, 10),
  ('Refill 13kg', 13, 'Gateway', 1950, 1700, 10),
  ('Refill 50kg', 50, 'Gateway', 7250, 6400, 5)
) as seed (name, size_kg, brand, sale_price, cost_price, low_stock_threshold)
where not exists (select 1 from public.products);

-- ---------------------------------------------------------------------------
-- NOTES
--  * VAT: Kenya standard rate 16%. The sales table stores tax separately —
--    the app will compute it (0% on exempt LPG if applicable to your setup;
--    adjust in the POS settings when we build pricing rules).
--  * Invoice numbers are generated by the app (e.g. INV-2026-0001).
-- ============================================================================
