-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0019
-- Cylinder fleet view + movement history + edge-case fixes
--
--  * cylinder_fleet_view: per branch, per brand+size:
--      full_qty (refills in stock) + empty_qty (cylinders in stock)
--      + out_qty (with customers) = total physical cylinders
--  * cylinder_movement_log: every stock movement touching refill/cylinder
--    products, so changes are fully traceable
--  * cylinder_tracking gets branch_id; collecting a cylinder now returns
--    it to branch stock (audited)
--  * record_sale: flags refill sales WITHOUT a returned cylinder (fleet
--    reduction needs follow-up) + records the branch on left cylinders
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. branch_id on cylinder_tracking
-- ---------------------------------------------------------------------------
alter table public.cylinder_tracking
  add column if not exists branch_id uuid references public.branches (id) on delete set null;

-- ---------------------------------------------------------------------------
-- 2. Fleet view
-- ---------------------------------------------------------------------------
drop view if exists public.cylinder_fleet_view;
create view public.cylinder_fleet_view as
with combos as (
  select p.brand, p.size_kg
  from public.products p
  where p.product_type in ('refill', 'cylinder') and p.brand is not null
  group by p.brand, p.size_kg
),
branches_ as (
  select id, name from public.branches where is_active
),
stock_by as (
  select ps.branch_id, p.brand, p.size_kg,
    coalesce(sum(ps.quantity) filter (where p.product_type = 'refill'), 0) as full_qty,
    coalesce(sum(ps.quantity) filter (where p.product_type = 'cylinder'), 0) as empty_qty
  from public.product_stock ps
  join public.products p on p.id = ps.product_id
  where p.product_type in ('refill', 'cylinder')
  group by ps.branch_id, p.brand, p.size_kg
),
out_by as (
  select ct.branch_id, p.brand, p.size_kg,
    coalesce(sum(ct.quantity), 0) as out_qty
  from public.cylinder_tracking ct
  join public.products p on p.id = ct.product_id
  where ct.status = 'out' and ct.branch_id is not null
  group by ct.branch_id, p.brand, p.size_kg
)
select
  b.id as branch_id, b.name as branch_name,
  c.brand, c.size_kg,
  coalesce(s.full_qty, 0) as full_qty,
  coalesce(s.empty_qty, 0) as empty_qty,
  coalesce(o.out_qty, 0) as out_qty,
  (coalesce(s.full_qty, 0) + coalesce(s.empty_qty, 0) + coalesce(o.out_qty, 0)) as total_qty
from combos c
cross join branches_ b
left join stock_by s on s.branch_id = b.id and s.brand = c.brand and s.size_kg = c.size_kg
left join out_by o on o.branch_id = b.id and o.brand = c.brand and o.size_kg = c.size_kg;

grant select on public.cylinder_fleet_view to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Movement history log
-- ---------------------------------------------------------------------------
drop view if exists public.cylinder_movement_log;
create view public.cylinder_movement_log as
select
  sm.id, sm.branch_id, b.name as branch_name,
  sm.product_id, p.name as product_name,
  p.brand, p.size_kg, p.product_type::text as product_type,
  sm.quantity_change, sm.movement_type::text as movement_type,
  sm.note, sm.created_at
from public.stock_movements sm
join public.products p on p.id = sm.product_id
join public.branches b on b.id = sm.branch_id
where p.product_type in ('refill', 'cylinder')
order by sm.created_at desc;

grant select on public.cylinder_movement_log to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Collecting a cylinder returns it to branch stock
-- ---------------------------------------------------------------------------
create or replace function public.mark_cylinder_returned(p_tracking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch uuid;
  v_pid uuid;
  v_qty int;
begin
  select branch_id, product_id, quantity into v_branch, v_pid, v_qty
    from public.cylinder_tracking where id = p_tracking_id;
  if v_pid is null then
    raise exception 'Tracking record not found';
  end if;

  if v_branch is not null then
    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, note, created_by)
    values (v_branch, v_pid, v_qty, 'return',
            'Cylinder collected from customer (tracking)', auth.uid());
  end if;

  update public.cylinder_tracking
     set status = 'returned', returned_at = now()
   where id = p_tracking_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. record_sale: no-return refill alerts + branch on left cylinders
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
      v_stock := coalesce(
        (select quantity from public.product_stock
          where branch_id = p_branch_id and product_id = v_prod), 0);
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
    elsif v_ptype = 'refill'::public.product_type then
      -- refill sold WITHOUT a returned cylinder: fleet reduced, follow up
      insert into public.cylinder_exchange_alerts
        (sale_id, branch_id, customer_id, sold_product_id, received_product_id,
         note, created_at)
      values (v_sale_id, p_branch_id, p_customer_id, v_prod, v_prod,
              'No cylinder returned for ' || v_invoice_no || ' — ' ||
              v_qty || 'x ' || v_prod_name ||
              ' left the branch without an empty coming back',
              now());
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

    if jsonb_typeof(p_cylinders_left) = 'array' then
      for v_item in select * from jsonb_array_elements(p_cylinders_left)
      loop
        insert into public.cylinder_tracking
          (customer_id, customer_location_id, product_id, quantity, sale_id,
           branch_id, left_by, left_at, follow_up_date, note, status)
        values (p_customer_id, p_customer_location_id,
                (v_item ->> 'product_id')::uuid,
                (v_item ->> 'quantity')::int,
                v_sale_id, p_branch_id, v_cashier_id, now(),
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
