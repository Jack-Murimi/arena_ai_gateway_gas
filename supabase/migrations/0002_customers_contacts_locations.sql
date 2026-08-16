-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0002
-- Customer contacts & locations
--
-- IMPORTANT: run AFTER 0001_initial_schema.sql.
--
-- A "customer" is a household or business. Real-world ordering means:
--   * many PEOPLE order gas for one customer (house keeper, security,
--     children...)  -> customer_contacts (name + phone each)
--   * a customer has MULTIPLE delivery locations
--     -> customer_locations (each may have a default cylinder / product)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- CONTACTS — the people who order gas for a customer
-- ---------------------------------------------------------------------------
create table public.customer_contacts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  name text not null,
  phone text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);

create index customer_contacts_customer_idx
  on public.customer_contacts (customer_id);
-- only ONE main contact per customer
create unique index customer_contacts_one_primary
  on public.customer_contacts (customer_id) where (is_primary);

-- ---------------------------------------------------------------------------
-- LOCATIONS — delivery points; each may carry a default cylinder (product)
-- ---------------------------------------------------------------------------
create table public.customer_locations (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  name text not null,
  address text,
  is_primary boolean not null default false,
  default_product_id uuid references public.products (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index customer_locations_customer_idx
  on public.customer_locations (customer_id);
-- only ONE main location per customer
create unique index customer_locations_one_primary
  on public.customer_locations (customer_id) where (is_primary);

create trigger trg_customer_locations_updated_at
  before update on public.customer_locations
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY (same pattern as 0001)
-- ---------------------------------------------------------------------------
alter table public.customer_contacts  enable row level security;
alter table public.customer_locations enable row level security;

create policy "customer_contacts_all_authenticated"
  on public.customer_contacts for all to authenticated using (true) with check (true);
create policy "customer_locations_all_authenticated"
  on public.customer_locations for all to authenticated using (true) with check (true);

-- ============================================================================
-- NOTE: the "default cylinder" per location references the products table,
-- which is seeded by migration 0001. Products management UI (add brands,
-- sizes, prices) comes with the Inventory module.
-- ============================================================================
