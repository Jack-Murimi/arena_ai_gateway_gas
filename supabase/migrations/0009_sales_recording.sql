-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0009
-- Full sales recording (POS): date/branch/customer/location, line items,
-- cylinder returns (swap), multiple riders, payments (M-Pesa/Cash/PDQ/
-- Cheque), invoice (unpaid) flow, customer ledger & audit trail.
--
-- The app records sales EXCLUSIVELY through the security-definer function
-- public.record_sale(...) which does everything atomically in one
-- transaction (no partial sales, clean audit trail).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Enums & sales columns
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.payment_status as enum ('paid', 'unpaid', 'partial');
exception when duplicate_object then null; end $$;

alter type public.payment_method add value if not exists 'pdq';
alter type public.payment_method add value if not exists 'cheque';

alter table public.sales
  add column if not exists sale_date date not null default current_date;
alter table public.sales
  add column if not exists payment_status public.payment_status not null default 'paid';
alter table public.sales
  add column if not exists customer_location_id uuid
    references public.customer_locations (id) on delete set null;

-- Customer balance may go negative (overpayment / advance).
alter table public.customers drop constraint if exists customers_balance_check;

-- Stock may show negative until the purchases module seeds stock-in.
alter table public.product_stock drop constraint if exists product_stock_quantity_check;

-- ---------------------------------------------------------------------------
-- 2. Sale riders (a sale can have several delivery riders)
-- ---------------------------------------------------------------------------
create table if not exists public.sale_riders (
  sale_id uuid not null references public.sales (id) on delete cascade,
  rider_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (sale_id, rider_id)
);

-- ---------------------------------------------------------------------------
-- 3. Cylinder returns (swap) — refills come with an empty cylinder back
-- ---------------------------------------------------------------------------
create table if not exists public.sale_cylinder_returns (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  sale_item_id uuid references public.sale_items (id) on delete set null,
  product_id uuid not null references public.products (id),
  quantity integer not null default 1 check (quantity > 0),
  created_at timestamptz not null default now()
);
create index if not exists sale_returns_sale_idx on public.sale_cylinder_returns (sale_id);

-- ---------------------------------------------------------------------------
-- 4. Customer account ledger (audit trail: every debit/credit + balance)
-- ---------------------------------------------------------------------------
create table if not exists public.customer_account_entries (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  sale_id uuid references public.sales (id) on delete set null,
  payment_id uuid references public.payments (id) on delete set null,
  entry_type text not null check (entry_type in ('sale', 'payment', 'adjustment', 'refund', 'opening')),
  debit numeric(12,2) not null default 0 check (debit >= 0),
  credit numeric(12,2) not null default 0 check (credit >= 0),
  balance_after numeric(12,2) not null default 0,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists account_entries_customer_idx
  on public.customer_account_entries (customer_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 5. Invoice number sequence + delivery-sale link
-- ---------------------------------------------------------------------------
create sequence if not exists public.invoice_seq;

alter table public.deliveries add column if not exists sale_id uuid
  references public.sales (id) on delete set null;

-- ---------------------------------------------------------------------------
-- 6. Sales view (history lists with names)
-- ---------------------------------------------------------------------------
create or replace view public.sales_view as
select
  s.id, s.invoice_no, s.sale_date, s.branch_id, b.name as branch_name,
  s.customer_id, c.name as customer_name,
  s.customer_location_id, cl.name as location_name,
  s.cashier_id, cp.full_name as cashier_name,
  s.subtotal, s.discount, s.tax, s.total, s.status, s.payment_status,
  s.note, s.created_at,
  (select string_agg(p.name || ' x' || si.quantity, ', ' order by p.name)
   from public.sale_items si join public.products p on p.id = si.product_id
   where si.sale_id = s.id) as items_summary,
  (select string_agg(rp.full_name, ', ' order by rp.full_name)
   from public.sale_riders sr join public.profiles rp on rp.id = sr.rider_id
   where sr.sale_id = s.id) as riders_summary
from public.sales s
left join public.customers c on c.id = s.customer_id
left join public.branches b on b.id = s.branch_id
left join public.customer_locations cl on cl.id = s.customer_location_id
left join public.profiles cp on cp.id = s.cashier_id;

-- ---------------------------------------------------------------------------
-- 7. RLS — new tables are read-only via client (writes only through the
--    security-definer function). sales/sale_items/payments likewise.
-- ---------------------------------------------------------------------------
alter table public.sale_riders enable row level security;
alter table public.sale_cylinder_returns enable row level security;
alter table public.customer_account_entries enable row level security;

create policy "sale_riders_select" on public.sale_riders
  for select to authenticated using (true);
create policy "sale_cylinder_returns_select" on public.sale_cylinder_returns
  for select to authenticated using (true);
create policy "account_entries_select" on public.customer_account_entries
  for select to authenticated using (true);

drop policy if exists "sales_all_authenticated" on public.sales;
drop policy if exists "sale_items_all_authenticated" on public.sale_items;
drop policy if exists "payments_all_authenticated" on public.payments;
create policy "sales_select" on public.sales for select to authenticated using (true);
create policy "sale_items_select" on public.sale_items for select to authenticated using (true);
create policy "payments_select" on public.payments for select to authenticated using (true);

grant select on public.sales_view to authenticated;

-- ---------------------------------------------------------------------------
-- 8. record_sale — one atomic transaction for everything
-- ---------------------------------------------------------------------------
create or replace function public.record_sale(
  p_sale_date date,
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_location_id uuid,
  p_items jsonb,          -- [{product_id, quantity, unit_price, cylinder_return_product_id}]
  p_riders jsonb,         -- [{"rider_id": ...}]
  p_payment_method text,  -- mpesa | cash | pdq | cheque | credit
  p_amount_paid numeric,
  p_mpesa_code text,
  p_note text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cashier_id uuid := auth.uid();
  v_total numeric := 0;
  v_subtotal numeric := 0;
  v_sale_id uuid;
  v_sale_item_id uuid;
  v_invoice_no text;
  v_balance_due numeric;
  v_payment_status public.payment_status;
  v_customer_name text;
  v_location text;
  v_item jsonb;
  v_qty int;
  v_price numeric;
  v_prod uuid;
  v_return_prod uuid;
  v_first_rider uuid;
  v_old_price numeric;
begin
  if v_cashier_id is null then
    raise exception 'Not authenticated';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No items in sale';
  end if;

  -- totals
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := coalesce((v_item ->> 'quantity')::int, 0);
    v_price := coalesce((v_item ->> 'unit_price')::numeric, 0);
    if v_qty <= 0 or v_price < 0 then
      raise exception 'Invalid line item';
    end if;
    v_total := v_total + (v_qty * v_price);
  end loop;
  v_subtotal := v_total;

  -- invoice number
  v_invoice_no := 'INV-' || to_char(p_sale_date, 'YYYY') || '-' ||
                  lpad(nextval('public.invoice_seq')::text, 4, '0');

  -- payment status
  if p_amount_paid is null then p_amount_paid := 0; end if;
  if p_amount_paid >= v_total then
    v_payment_status := 'paid';
  elsif p_amount_paid > 0 then
    v_payment_status := 'partial';
  else
    v_payment_status := 'unpaid';
  end if;
  v_balance_due := v_total - p_amount_paid;

  -- sale
  insert into public.sales (
    invoice_no, branch_id, cashier_id, customer_id, customer_location_id,
    sale_date, subtotal, discount, tax, total, status, payment_status,
    note, created_at
  ) values (
    v_invoice_no, p_branch_id, v_cashier_id, p_customer_id,
    p_customer_location_id, p_sale_date, v_subtotal, 0, 0, v_total,
    'complete', v_payment_status, p_note, now()
  ) returning id into v_sale_id;

  -- items, stock, cylinder returns, price-change flags
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item ->> 'quantity')::int;
    v_price := (v_item ->> 'unit_price')::numeric;
    v_prod := (v_item ->> 'product_id')::uuid;

    insert into public.sale_items (sale_id, product_id, quantity, unit_price, line_total)
    values (v_sale_id, v_prod, v_qty, v_price, v_qty * v_price)
    returning id into v_sale_item_id;

    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
    values (p_branch_id, v_prod, -v_qty, 'sale', v_sale_id, v_invoice_no, v_cashier_id);

    v_return_prod := nullif((v_item ->> 'cylinder_return_product_id')::uuid, null);
    if v_return_prod is not null then
      insert into public.sale_cylinder_returns (sale_id, sale_item_id, product_id, quantity, created_at)
      values (v_sale_id, v_sale_item_id, v_return_prod, v_qty, now());
      insert into public.stock_movements
        (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
      values (p_branch_id, v_return_prod, v_qty, 'return', v_sale_id,
              v_invoice_no || ' (cylinder return)', v_cashier_id);
    end if;

    select sale_price into v_old_price from public.products where id = v_prod;
    if v_old_price is distinct from v_price then
      insert into public.price_change_requests
        (product_id, sale_id, old_price, new_price, status, changed_by, note, created_at)
      values (v_prod, v_sale_id, v_old_price, v_price, 'pending', v_cashier_id,
              'POS price override on ' || v_invoice_no, now());
    end if;
  end loop;

  -- riders (primary = first)
  v_first_rider := null;
  if jsonb_typeof(p_riders) = 'array' then
    for v_item in select * from jsonb_array_elements(p_riders)
    loop
      insert into public.sale_riders (sale_id, rider_id)
      values (v_sale_id, (v_item ->> 'rider_id')::uuid)
      on conflict do nothing;
      if v_first_rider is null then
        v_first_rider := (v_item ->> 'rider_id')::uuid;
      end if;
    end loop;
  end if;

  -- payment
  if p_amount_paid > 0 then
    insert into public.payments
      (sale_id, customer_id, amount, method, mpesa_code, received_by, created_at)
    values (v_sale_id, p_customer_id, p_amount_paid,
            p_payment_method::public.payment_method, p_mpesa_code, v_cashier_id, now());
  end if;

  -- customer ledger + balance (debit sale, credit payment)
  if p_customer_id is not null then
    select name into v_customer_name from public.customers where id = p_customer_id;
    insert into public.customer_account_entries
      (customer_id, sale_id, entry_type, debit, credit, balance_after, created_by, created_at)
    values (p_customer_id, v_sale_id, 'sale', v_total, 0,
            (select coalesce(balance, 0) from public.customers where id = p_customer_id) + v_total,
            v_cashier_id, now());
    if p_amount_paid > 0 then
      insert into public.customer_account_entries
        (customer_id, payment_id, entry_type, debit, credit, balance_after, created_by, created_at)
      values (p_customer_id,
              (select id from public.payments where sale_id = v_sale_id order by created_at desc limit 1),
              'payment', 0, p_amount_paid,
              (select coalesce(balance, 0) from public.customers where id = p_customer_id) + v_total - p_amount_paid,
              v_cashier_id, now());
    end if;
    update public.customers
      set balance = balance + v_total - p_amount_paid
      where id = p_customer_id;
  end if;

  -- delivery record (primary rider gets credit)
  if v_first_rider is not null and p_customer_id is not null then
    select coalesce(cl.address, cl.name, '') into v_location
      from public.customer_locations cl where cl.id = p_customer_location_id;
    insert into public.deliveries
      (branch_id, rider_id, customer_name, location, amount, status, note,
       created_at, delivered_at, sale_id)
    values (p_branch_id, v_first_rider, v_customer_name, nullif(v_location, ''),
            v_total, 'delivered', 'Sale ' || v_invoice_no, now(), now(), v_sale_id);
  end if;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'invoice_no', v_invoice_no,
    'total', v_total,
    'amount_paid', p_amount_paid,
    'balance_due', v_balance_due,
    'payment_status', v_payment_status
  );
end;
$$;

grant execute on function public.record_sale(date, uuid, uuid, uuid, jsonb, jsonb, text, numeric, text, text) to authenticated;
