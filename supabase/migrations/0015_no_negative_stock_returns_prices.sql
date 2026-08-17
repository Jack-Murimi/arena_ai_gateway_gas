-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0015
--   * record_sale refuses to sell below available stock
--   * supplier_product_prices: track each supplier's latest unit cost per
--     product (updated when invoices are recorded)
--   * supplier_returns: return damaged goods to a supplier (stock-out +
--     credit against supplier balance)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Supplier product prices (cheapest-supplier tracking)
-- ---------------------------------------------------------------------------
create table if not exists public.supplier_product_prices (
  supplier_id uuid not null references public.suppliers (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  unit_cost numeric(12,2) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (supplier_id, product_id)
);

create or replace view public.supplier_product_prices_view as
select
  spp.supplier_id, s.name as supplier_name,
  spp.product_id, p.name as product_name,
  spp.unit_cost, spp.updated_at
from public.supplier_product_prices spp
join public.suppliers s on s.id = spp.supplier_id
join public.products p on p.id = spp.product_id;

grant select on public.supplier_product_prices_view to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Supplier returns (damages)
-- ---------------------------------------------------------------------------
create table if not exists public.supplier_returns (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers (id) on delete cascade,
  branch_id uuid not null references public.branches (id),
  return_no text not null unique,
  return_date date not null default current_date,
  reason text not null default 'damaged',
  total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
  notes text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists supplier_returns_supplier_idx
  on public.supplier_returns (supplier_id, return_date desc);

create table if not exists public.supplier_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.supplier_returns (id) on delete cascade,
  product_id uuid not null references public.products (id),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  line_total numeric(12,2) not null default 0 check (line_total >= 0)
);
create index if not exists supplier_return_items_return_idx
  on public.supplier_return_items (return_id);

create sequence if not exists public.supplier_return_seq;

-- ---------------------------------------------------------------------------
-- 3. Supplier summary includes returns (balance = invoiced - paid - returns)
-- ---------------------------------------------------------------------------
drop view if exists public.supplier_summary;
create view public.supplier_summary as
select
  s.id, s.name, s.phone, s.contact_person, s.is_active,
  (select coalesce(sum(i.total_amount), 0) from public.supplier_invoices i
    where i.supplier_id = s.id)::numeric(12,2) as invoiced_total,
  (select coalesce(sum(p.amount), 0) from public.supplier_payments p
    where p.supplier_id = s.id)::numeric(12,2) as paid_total,
  (select coalesce(sum(r.total_amount), 0) from public.supplier_returns r
    where r.supplier_id = s.id)::numeric(12,2) as returns_total,
  ((select coalesce(sum(i.total_amount), 0) from public.supplier_invoices i
      where i.supplier_id = s.id)
   - (select coalesce(sum(p.amount), 0) from public.supplier_payments p
      where p.supplier_id = s.id)
   - (select coalesce(sum(r.total_amount), 0) from public.supplier_returns r
      where r.supplier_id = s.id))::numeric(12,2) as balance
from public.suppliers s;

create or replace view public.supplier_returns_view as
select
  sr.id, sr.return_no, sr.supplier_id, s.name as supplier_name,
  sr.branch_id, b.name as branch_name,
  sr.return_date, sr.reason, sr.total_amount, sr.notes, sr.created_at,
  (select count(*) from public.supplier_return_items it
    where it.return_id = sr.id) as item_count,
  (select string_agg(p.name || ' x' || it.quantity, ', ' order by p.name)
    from public.supplier_return_items it
    join public.products p on p.id = it.product_id
    where it.return_id = sr.id) as items_summary
from public.supplier_returns sr
left join public.suppliers s on s.id = sr.supplier_id
left join public.branches b on b.id = sr.branch_id;

grant select on public.supplier_returns_view to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------
alter table public.supplier_product_prices enable row level security;
alter table public.supplier_returns enable row level security;
alter table public.supplier_return_items enable row level security;

create policy "supplier_product_prices_select" on public.supplier_product_prices
  for select to authenticated using (true);
create policy "supplier_returns_select" on public.supplier_returns
  for select to authenticated using (true);
create policy "supplier_returns_admin_write" on public.supplier_returns
  for insert to authenticated with check (public.is_admin_or_director());
create policy "supplier_returns_admin_update" on public.supplier_returns
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "supplier_returns_admin_delete" on public.supplier_returns
  for delete to authenticated using (public.is_admin_or_director());
create policy "supplier_return_items_select" on public.supplier_return_items
  for select to authenticated using (true);
create policy "supplier_return_items_admin_write" on public.supplier_return_items
  for insert to authenticated with check (public.is_admin_or_director());
create policy "supplier_return_items_admin_update" on public.supplier_return_items
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "supplier_return_items_admin_delete" on public.supplier_return_items
  for delete to authenticated using (public.is_admin_or_director());

-- ---------------------------------------------------------------------------
-- 5. admin_save_supplier_invoice: also track supplier product prices
-- ---------------------------------------------------------------------------
create or replace function public.admin_save_supplier_invoice(
  p_supplier_id uuid, p_invoice_no text, p_branch_id uuid,
  p_invoice_date date, p_notes text, p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
  v_total numeric := 0;
  v_item jsonb;
  v_pid uuid;
  v_qty int;
  v_cost numeric;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  if p_invoice_no is null or trim(p_invoice_no) = '' then
    raise exception 'Invoice number is required';
  end if;
  if p_branch_id is null then
    raise exception 'Branch is required so stock can be posted';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No items in invoice';
  end if;
  if not exists (select 1 from public.suppliers where id = p_supplier_id) then
    raise exception 'Supplier not found';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_total := v_total
      + (coalesce((v_item ->> 'quantity')::int, 0)
         * coalesce((v_item ->> 'unit_cost')::numeric, 0));
  end loop;

  insert into public.supplier_invoices
    (supplier_id, invoice_no, branch_id, invoice_date, total_amount, status, notes, created_by, created_at)
  values (p_supplier_id, trim(p_invoice_no), p_branch_id, p_invoice_date, v_total, 'unpaid', p_notes, auth.uid(), now())
  returning id into v_invoice_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_pid := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'quantity')::int;
    v_cost := coalesce((v_item ->> 'unit_cost')::numeric, 0);

    insert into public.supplier_invoice_items (invoice_id, product_id, quantity, unit_cost, line_total)
    values (v_invoice_id, v_pid, v_qty, v_cost, v_qty * v_cost);

    if v_cost > 0 then
      update public.products set cost_price = v_cost where id = v_pid;
    end if;

    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
    values (p_branch_id, v_pid, v_qty, 'purchase', v_invoice_id,
            'Supplier invoice ' || trim(p_invoice_no), auth.uid());

    -- cheapest-supplier tracking
    insert into public.supplier_product_prices (supplier_id, product_id, unit_cost, updated_at)
    values (p_supplier_id, v_pid, v_cost, now())
    on conflict (supplier_id, product_id)
    do update set unit_cost = excluded.unit_cost, updated_at = now();
  end loop;

  return jsonb_build_object('invoice_id', v_invoice_id, 'total_amount', v_total);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. admin_save_supplier_return: damaged goods back to supplier
-- ---------------------------------------------------------------------------
create or replace function public.admin_save_supplier_return(
  p_supplier_id uuid, p_branch_id uuid, p_return_date date,
  p_reason text, p_notes text, p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_return_id uuid;
  v_no text;
  v_total numeric := 0;
  v_item jsonb;
  v_pid uuid;
  v_qty int;
  v_cost numeric;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  if p_branch_id is null then
    raise exception 'Branch is required';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No items in return';
  end if;
  if not exists (select 1 from public.suppliers where id = p_supplier_id) then
    raise exception 'Supplier not found';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_total := v_total
      + (coalesce((v_item ->> 'quantity')::int, 0)
         * coalesce((v_item ->> 'unit_cost')::numeric, 0));
  end loop;

  v_no := 'SR-' || to_char(now(), 'YYYY') || '-' ||
          lpad(nextval('public.supplier_return_seq')::text, 4, '0');

  insert into public.supplier_returns
    (supplier_id, branch_id, return_no, return_date, reason, total_amount, notes, created_by, created_at)
  values (p_supplier_id, p_branch_id, v_no, p_return_date,
          coalesce(nullif(trim(p_reason), ''), 'damaged'),
          v_total, p_notes, auth.uid(), now())
  returning id into v_return_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_pid := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'quantity')::int;
    v_cost := coalesce((v_item ->> 'unit_cost')::numeric, 0);

    insert into public.supplier_return_items (return_id, product_id, quantity, unit_cost, line_total)
    values (v_return_id, v_pid, v_qty, v_cost, v_qty * v_cost);

    -- stock-out (audited)
    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
    values (p_branch_id, v_pid, -v_qty, 'adjustment', v_return_id,
            'Supplier return ' || v_no || ' (' || coalesce(nullif(trim(p_reason), ''), 'damaged') || ')',
            auth.uid());
  end loop;

  return jsonb_build_object('return_id', v_return_id, 'return_no', v_no, 'total_amount', v_total);
end;
$$;

grant execute on function public.admin_save_supplier_return(uuid, uuid, date, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. record_sale: refuse sales below available stock
-- ---------------------------------------------------------------------------
create or replace function public.record_sale(
  p_sale_date date,
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_location_id uuid,
  p_items jsonb,
  p_riders jsonb,
  p_payment_method text,
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
  v_ptype public.product_type;
  v_stock int;
  v_prod_name text;
begin
  if v_cashier_id is null then
    raise exception 'Not authenticated';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No items in sale';
  end if;

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

  v_invoice_no := 'INV-' || to_char(p_sale_date, 'YYYY') || '-' ||
                  lpad(nextval('public.invoice_seq')::text, 4, '0');

  if p_amount_paid is null then p_amount_paid := 0; end if;
  if p_amount_paid >= v_total then
    v_payment_status := 'paid';
  elsif p_amount_paid > 0 then
    v_payment_status := 'partial';
  else
    v_payment_status := 'unpaid';
  end if;
  v_balance_due := v_total - p_amount_paid;

  insert into public.sales (
    invoice_no, branch_id, cashier_id, customer_id, customer_location_id,
    sale_date, subtotal, discount, tax, total, status, payment_status,
    note, created_at
  ) values (
    v_invoice_no, p_branch_id, v_cashier_id, p_customer_id,
    p_customer_location_id, p_sale_date, v_subtotal, 0, 0, v_total,
    'complete', v_payment_status, p_note, now()
  ) returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item ->> 'quantity')::int;
    v_price := (v_item ->> 'unit_price')::numeric;
    v_prod := (v_item ->> 'product_id')::uuid;

    -- stock availability check (services are exempt — no physical stock)
    select product_type, name into v_ptype, v_prod_name
      from public.products where id = v_prod;
    if v_ptype is distinct from 'service'::public.product_type then
      select coalesce(quantity, 0) into v_stock
        from public.product_stock
        where branch_id = p_branch_id and product_id = v_prod;
      if v_stock < v_qty then
        raise exception 'Insufficient stock for % (available %, requested %)',
          v_prod_name, v_stock, v_qty;
      end if;
    end if;

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

  if p_amount_paid > 0 then
    insert into public.payments
      (sale_id, customer_id, amount, method, mpesa_code, received_by, created_at)
    values (v_sale_id, p_customer_id, p_amount_paid,
            p_payment_method::public.payment_method, p_mpesa_code, v_cashier_id, now());
  end if;

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
