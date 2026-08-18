-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0018
-- Cylinder exchange tracking (no deposits)
--
--  * cylinder_tracking: cylinders left with a customer — who has it, who
--    left it, when to go back for it (follow-up date)
--  * cylinder_exchange_alerts: brand/size mismatches on exchanges (customer
--    gave e.g. 13kg Afrigas, took 13kg Total) flagged for admin/director
--  * record_sale: accepts p_cylinders_left + auto-flags mismatches
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Cylinders left with customers
-- ---------------------------------------------------------------------------
create table if not exists public.cylinder_tracking (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  customer_location_id uuid references public.customer_locations (id) on delete set null,
  product_id uuid not null references public.products (id),
  quantity integer not null default 1 check (quantity > 0),
  sale_id uuid references public.sales (id) on delete set null,
  left_by uuid references public.profiles (id) on delete set null,
  left_at timestamptz not null default now(),
  follow_up_date date,
  note text,
  status text not null default 'out' check (status in ('out', 'returned')),
  returned_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists cylinder_tracking_status_idx
  on public.cylinder_tracking (status);
create index if not exists cylinder_tracking_followup_idx
  on public.cylinder_tracking (follow_up_date);

-- ---------------------------------------------------------------------------
-- 2. Exchange alerts (brand/size mismatch)
-- ---------------------------------------------------------------------------
create table if not exists public.cylinder_exchange_alerts (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid references public.sales (id) on delete cascade,
  branch_id uuid references public.branches (id) on delete set null,
  customer_id uuid references public.customers (id) on delete set null,
  sold_product_id uuid not null references public.products (id),
  received_product_id uuid not null references public.products (id),
  status text not null default 'pending' check (status in ('pending', 'resolved')),
  resolved_by uuid references public.profiles (id) on delete set null,
  resolved_at timestamptz,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists cylinder_exchange_alerts_status_idx
  on public.cylinder_exchange_alerts (status);

-- ---------------------------------------------------------------------------
-- 3. Views
-- ---------------------------------------------------------------------------
create or replace view public.cylinder_tracking_view as
select
  ct.id, ct.customer_id, c.name as customer_name,
  ct.customer_location_id, cl.name as location_name,
  ct.product_id, p.name as product_name,
  ct.quantity, ct.sale_id, s.invoice_no,
  ct.left_by, lp.full_name as left_by_name,
  ct.left_at, ct.follow_up_date, ct.note,
  ct.status, ct.returned_at, ct.created_at
from public.cylinder_tracking ct
left join public.customers c on c.id = ct.customer_id
left join public.customer_locations cl on cl.id = ct.customer_location_id
left join public.products p on p.id = ct.product_id
left join public.sales s on s.id = ct.sale_id
left join public.profiles lp on lp.id = ct.left_by;

create or replace view public.cylinder_exchange_alerts_view as
select
  cea.id, cea.sale_id, s.invoice_no,
  cea.branch_id, b.name as branch_name,
  cea.customer_id, c.name as customer_name,
  cea.sold_product_id, sp.name as sold_product_name,
  cea.received_product_id, rp.name as received_product_name,
  cea.status, cea.resolved_by, rb.full_name as resolved_by_name,
  cea.resolved_at, cea.note, cea.created_at
from public.cylinder_exchange_alerts cea
left join public.sales s on s.id = cea.sale_id
left join public.branches b on b.id = cea.branch_id
left join public.customers c on c.id = cea.customer_id
left join public.products sp on sp.id = cea.sold_product_id
left join public.products rp on rp.id = cea.received_product_id
left join public.profiles rb on rb.id = cea.resolved_by;

grant select on public.cylinder_tracking_view to authenticated;
grant select on public.cylinder_exchange_alerts_view to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------
alter table public.cylinder_tracking enable row level security;
alter table public.cylinder_exchange_alerts enable row level security;

create policy "cylinder_tracking_select" on public.cylinder_tracking
  for select to authenticated using (true);
create policy "cylinder_tracking_insert" on public.cylinder_tracking
  for insert to authenticated with check (true);
create policy "cylinder_tracking_update" on public.cylinder_tracking
  for update to authenticated using (true) with check (true);
create policy "cylinder_tracking_delete" on public.cylinder_tracking
  for delete to authenticated using (public.is_admin_or_director());

create policy "exchange_alerts_select" on public.cylinder_exchange_alerts
  for select to authenticated using (true);
create policy "exchange_alerts_resolve" on public.cylinder_exchange_alerts
  for update to authenticated
  using (public.is_admin_or_director()) with check (public.is_admin_or_director());

-- ---------------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------------
create or replace function public.mark_cylinder_returned(p_tracking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.cylinder_tracking
     set status = 'returned', returned_at = now()
   where id = p_tracking_id;
end;
$$;

create or replace function public.log_cylinder_left(
  p_customer_id uuid, p_location_id uuid, p_product_id uuid,
  p_quantity integer, p_follow_up_date date, p_note text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.cylinder_tracking
    (customer_id, customer_location_id, product_id, quantity,
     left_by, left_at, follow_up_date, note, status)
  values (p_customer_id, p_location_id, p_product_id, p_quantity,
          auth.uid(), now(), p_follow_up_date, p_note, 'out')
  returning id into v_id;
  return jsonb_build_object('tracking_id', v_id);
end;
$$;

create or replace function public.resolve_exchange_alert(p_alert_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  update public.cylinder_exchange_alerts
     set status = 'resolved', resolved_by = auth.uid(), resolved_at = now()
   where id = p_alert_id;
end;
$$;

grant execute on function public.mark_cylinder_returned(uuid) to authenticated;
grant execute on function public.log_cylinder_left(uuid, uuid, uuid, integer, date, text) to authenticated;
grant execute on function public.resolve_exchange_alert(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. record_sale: p_cylinders_left param + auto exchange alerts
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
  p_note text,
  p_cylinders_left jsonb
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
  v_sold_brand text;
  v_sold_size numeric;
  v_ret_brand text;
  v_ret_size numeric;
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

      -- exchange alert: received cylinder differs from sold refill
      select brand, size_kg into v_sold_brand, v_sold_size
        from public.products where id = v_prod;
      select brand, size_kg into v_ret_brand, v_ret_size
        from public.products where id = v_return_prod;
      if (v_sold_brand is distinct from v_ret_brand)
         or (v_sold_size is distinct from v_ret_size) then
        insert into public.cylinder_exchange_alerts
          (sale_id, branch_id, customer_id, sold_product_id, received_product_id,
           note, created_at)
        values (v_sale_id, p_branch_id, p_customer_id, v_prod, v_return_prod,
                'Exchange mismatch on ' || v_invoice_no ||
                ': sold ' || coalesce(v_sold_brand, '?') || ' ' ||
                coalesce(v_sold_size::text, '?') || 'kg, received ' ||
                coalesce(v_ret_brand, '?') || ' ' ||
                coalesce(v_ret_size::text, '?') || 'kg',
                now());
      end if;
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

    -- cylinders left with the customer during this sale
    if jsonb_typeof(p_cylinders_left) = 'array' then
      for v_item in select * from jsonb_array_elements(p_cylinders_left)
      loop
        insert into public.cylinder_tracking
          (customer_id, customer_location_id, product_id, quantity, sale_id,
           left_by, left_at, follow_up_date, note, status)
        values (p_customer_id, p_customer_location_id,
                (v_item ->> 'product_id')::uuid,
                (v_item ->> 'quantity')::int,
                v_sale_id, v_cashier_id, now(),
                nullif((v_item ->> 'follow_up_date'), '')::date,
                'Left during sale ' || v_invoice_no, 'out');
      end loop;
    end if;
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

grant execute on function public.record_sale(date, uuid, uuid, uuid, jsonb, jsonb, text, numeric, text, text, jsonb) to authenticated;
