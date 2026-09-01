-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0024
-- FIFO Inventory Batching System
--
-- Implements First-In-First-Out (FIFO) cost accounting for gas cylinder stock.
-- Each purchase creates inventory batches with specific costs.
-- Sales consume from the oldest batch first, tracking actual cost of goods sold.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Inventory Batches Table
-- Tracks each purchase batch of products with its specific cost price.
-- ---------------------------------------------------------------------------
create table if not exists public.inventory_batches (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  quantity_received integer not null check (quantity_received > 0),
  quantity_remaining integer not null check (quantity_remaining >= 0),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  purchase_date date not null default current_date,
  reference_type text check (reference_type in ('purchase_order', 'opening', 'manual', 'transfer')),
  reference_id uuid,
  notes text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes for performance
create index if not exists inventory_batches_product_idx on public.inventory_batches (product_id);
create index if not exists inventory_batches_branch_product_idx on public.inventory_batches (branch_id, product_id);
create index if not exists inventory_batches_date_idx on public.inventory_batches (purchase_date, created_at);
create index if not exists inventory_batches_remaining_idx on public.inventory_batches (quantity_remaining) where quantity_remaining > 0;

-- Trigger to update updated_at
create or replace function public.update_inventory_batch_timestamp()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_inventory_batches_updated_at
  before update on public.inventory_batches
  for each row execute function public.update_inventory_batch_timestamp();

-- ---------------------------------------------------------------------------
-- 2. Sale FIFO Allocations Table
-- Tracks which inventory batches were consumed by each sale line item.
-- This ensures historical accuracy - past sales don't change when new purchases arrive.
-- ---------------------------------------------------------------------------
create table if not exists public.sale_fifo_allocations (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  sale_item_id uuid references public.sale_items (id) on delete cascade,
  batch_id uuid not null references public.inventory_batches (id) on delete set null,
  product_id uuid not null references public.products (id) on delete cascade,
  quantity integer not null check (quantity > 0),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  total_cost numeric(12,2) not null generated always as (quantity * unit_cost) stored,
  created_at timestamptz not null default now()
);

create index if not exists sale_fifo_allocations_sale_idx on public.sale_fifo_allocations (sale_id);
create index if not exists sale_fifo_allocations_sale_item_idx on public.sale_fifo_allocations (sale_item_id);
create index if not exists sale_fifo_allocations_batch_idx on public.sale_fifo_allocations (batch_id);

-- ---------------------------------------------------------------------------
-- 3. Views
-- ---------------------------------------------------------------------------

-- View: Current inventory batches with remaining quantities
create or replace view public.current_inventory_batches as
select
  ib.id, ib.branch_id, b.name as branch_name,
  ib.product_id, p.name as product_name, p.product_type::text as product_type,
  p.brand, p.size_kg,
  ib.quantity_received, ib.quantity_remaining,
  ib.unit_cost, ib.purchase_date, ib.reference_type, ib.reference_id,
  ib.notes, ib.created_at, ib.updated_at
from public.inventory_batches ib
join public.products p on p.id = ib.product_id
join public.branches b on b.id = ib.branch_id
where ib.quantity_remaining > 0
order by ib.purchase_date, ib.created_at;

-- View: Sale with FIFO cost breakdown
create or replace view public.sales_fifo_view as
select
  s.id, s.invoice_no, s.sale_date, s.branch_id, b.name as branch_name,
  s.customer_id, c.name as customer_name,
  s.customer_location_id, cl.name as location_name,
  s.cashier_id, cp.full_name as cashier_name,
  s.subtotal, s.discount, s.tax, s.total, s.status, s.payment_status,
  s.note, s.created_at,
  -- Total cost of goods sold (from FIFO allocations)
  coalesce((
    select sum(total_cost)
    from public.sale_fifo_allocations sfa
    where sfa.sale_id = s.id
  ), 0) as total_cost,
  -- Total profit (revenue - COGS)
  s.total - coalesce((
    select sum(total_cost)
    from public.sale_fifo_allocations sfa
    where sfa.sale_id = s.id
  ), 0) as total_profit,
  -- Items summary (existing)
  (select string_agg(p.name || ' x' || si.quantity, ', ' order by p.name)
   from public.sale_items si join public.products p on p.id = si.product_id
   where si.sale_id = s.id) as items_summary,
  -- Riders summary (existing)
  (select string_agg(rp.full_name, ', ' order by rp.full_name)
   from public.sale_riders sr join public.profiles rp on rp.id = sr.rider_id
   where sr.sale_id = s.id) as riders_summary
from public.sales s
left join public.customers c on c.id = s.customer_id
left join public.branches b on b.id = s.branch_id
left join public.customer_locations cl on cl.id = s.customer_location_id
left join public.profiles cp on cp.id = s.cashier_id;

grant select on public.current_inventory_batches to authenticated;
grant select on public.sales_fifo_view to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS Policies
-- ---------------------------------------------------------------------------

alter table public.inventory_batches enable row level security;
alter table public.sale_fifo_allocations enable row level security;

create policy "inventory_batches_select" on public.inventory_batches
  for select to authenticated using (true);
create policy "inventory_batches_insert" on public.inventory_batches
  for insert to authenticated with check (true);
create policy "inventory_batches_update" on public.inventory_batches
  for update to authenticated using (true) with check (true);
create policy "inventory_batches_delete" on public.inventory_batches
  for delete to authenticated using (public.is_admin_or_director());

create policy "sale_fifo_allocations_select" on public.sale_fifo_allocations
  for select to authenticated using (true);
create policy "sale_fifo_allocations_insert" on public.sale_fifo_allocations
  for insert to authenticated with check (true);
create policy "sale_fifo_allocations_delete" on public.sale_fifo_allocations
  for delete to authenticated using (public.is_admin_or_director());

-- ---------------------------------------------------------------------------
-- 5. Helper Functions
-- ---------------------------------------------------------------------------

-- Get oldest available batch for a product at a branch (FIFO)
create or replace function public.get_oldest_inventory_batch(
  p_branch_id uuid,
  p_product_id uuid
) returns public.inventory_batches
language sql
security definer
as $$
  select * from public.inventory_batches
  where branch_id = p_branch_id
    and product_id = p_product_id
    and quantity_remaining > 0
  order by purchase_date, created_at
  limit 1;
$$;

-- Consume quantity from inventory batches (FIFO order)
-- Returns array of {batch_id, quantity_consumed, unit_cost} for allocations
create or replace function public.consume_inventory_fifo(
  p_branch_id uuid,
  p_product_id uuid,
  p_quantity integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remaining integer := p_quantity;
  v_batch record;
  v_result jsonb := '[]'::jsonb;
  v_consumed integer;
begin
  if v_remaining <= 0 then
    return v_result;
  end if;

  for v_batch in
    select * from public.inventory_batches
    where branch_id = p_branch_id
      and product_id = p_product_id
      and quantity_remaining > 0
    order by purchase_date, created_at
  loop
    if v_remaining <= 0 then
      exit;
    end if;

    -- How much to consume from this batch
    v_consumed := least(v_remaining, v_batch.quantity_remaining);

    -- Add to result
    v_result := v_result || jsonb_build_object(
      'batch_id', v_batch.id,
      'quantity', v_consumed,
      'unit_cost', v_batch.unit_cost
    );

    -- Update remaining quantity
    update public.inventory_batches
       set quantity_remaining = quantity_remaining - v_consumed,
           updated_at = now()
     where id = v_batch.id;

    -- Reduce remaining
    v_remaining := v_remaining - v_consumed;
  end loop;

  if v_remaining > 0 then
    raise exception 'Insufficient stock: tried to consume % but only % available',
      p_quantity, (p_quantity - v_remaining);
  end if;

  return v_result;
end;
$$;

-- Get current selling price for a product
create or replace function public.get_product_selling_price(p_product_id uuid)
returns numeric
language sql
security definer
as $$
  select sale_price from public.products where id = p_product_id;
$$;

-- ---------------------------------------------------------------------------
-- 6. Modified RPCs
-- ---------------------------------------------------------------------------

-- MODIFIED: admin_receive_order now creates inventory batches instead of updating product cost_price
create or replace function public.admin_receive_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch uuid; v_status text; v_item record;
  v_batch_id uuid;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  select branch_id, status into v_branch, v_status
    from public.purchase_orders where id = p_order_id;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_status <> 'placed' then
    raise exception 'Order is not in placed state';
  end if;
  
  for v_item in select product_id, quantity, unit_cost
                from public.purchase_order_items where order_id = p_order_id
  loop
    -- Create inventory batch instead of updating product cost_price
    insert into public.inventory_batches (
      branch_id, product_id, quantity_received, quantity_remaining,
      unit_cost, purchase_date, reference_type, reference_id, created_by
    ) values (
      v_branch, v_item.product_id, v_item.quantity, v_item.quantity,
      v_item.unit_cost, current_date, 'purchase_order', p_order_id, auth.uid()
    ) returning id into v_batch_id;

    -- Still create stock movement for quantity tracking
    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
    values (v_branch, v_item.product_id, v_item.quantity, 'purchase', p_order_id,
            'PO receive', auth.uid());
  end loop;
  
  update public.purchase_orders set status = 'received', received_at = now()
   where id = p_order_id;
end;
$$;

-- MODIFIED: admin_init_stock now creates inventory batches
create or replace function public.admin_init_stock(p_branch_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb; v_pid uuid; v_qty int; v_old int; v_delta int;
  v_existing_qty integer;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  if not exists (select 1 from public.branches where id = p_branch_id) then
    raise exception 'Branch not found';
  end if;
  
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_pid := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'quantity')::int;
    if v_qty < 0 then raise exception 'Quantity cannot be negative'; end if;
    
    -- Get existing quantity for delta
    v_old := coalesce(
      (select quantity from public.product_stock
        where branch_id = p_branch_id and product_id = v_pid), 0);
    v_delta := v_qty - v_old;
    
    -- Create inventory batch for opening stock
    -- Use current product cost_price as the unit_cost for opening stock
    insert into public.inventory_batches (
      branch_id, product_id, quantity_received, quantity_remaining,
      unit_cost, purchase_date, reference_type, note, created_by
    ) values (
      p_branch_id, v_pid, v_qty, v_qty,
      coalesce((select cost_price from public.products where id = v_pid), 0),
      current_date, 'opening',
      'Stock init on ' || to_char(now(), 'YYYY-MM-DD'),
      auth.uid()
    );
    
    -- Still update product_stock via movement (for backwards compatibility)
    if v_delta <> 0 then
      insert into public.stock_movements
        (branch_id, product_id, quantity_change, movement_type, note, created_by)
      values (p_branch_id, v_pid, v_delta, 'opening',
              'Reconciliation ' || to_char(now(), 'YYYY-MM-DD') ||
              ' (was ' || v_old || ', counted ' || v_qty || ')',
              auth.uid());
    end if;
  end loop;
end;
$$;

-- MODIFIED: record_sale now uses FIFO inventory consumption
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
  v_batch_allocation jsonb;
  v_allocation record;
  v_total_cost numeric := 0;
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

  -- items, stock, cylinder returns, price-change flags, and FIFO allocations
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item ->> 'quantity')::int;
    v_price := (v_item ->> 'unit_price')::numeric;
    v_prod := (v_item ->> 'product_id')::uuid;

    insert into public.sale_items (sale_id, product_id, quantity, unit_price, line_total)
    values (v_sale_id, v_prod, v_qty, v_price, v_qty * v_price)
    returning id into v_sale_item_id;

    -- FIFO: Consume inventory and record allocations
    v_batch_allocation := public.consume_inventory_fifo(p_branch_id, v_prod, v_qty);
    
    -- Record allocations for this sale item
    for v_allocation in select * from jsonb_array_elements(v_batch_allocation)
    loop
      insert into public.sale_fifo_allocations (
        sale_id, sale_item_id, batch_id, product_id, quantity, unit_cost
      ) values (
        v_sale_id, v_sale_item_id,
        (v_allocation ->> 'batch_id')::uuid,
        v_prod,
        (v_allocation ->> 'quantity')::integer,
        (v_allocation ->> 'unit_cost')::numeric
      );
      
      -- Accumulate total cost for this sale
      v_total_cost := v_total_cost + 
        ((v_allocation ->> 'quantity')::integer * (v_allocation ->> 'unit_cost')::numeric);
    end loop;

    -- Still create stock movement for quantity tracking (backwards compatibility)
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
    'payment_status', v_payment_status,
    'total_cost', v_total_cost,
    'profit', v_total - v_total_cost
  );
end;
$$;

-- Re-grant execute permissions
grant execute on function public.admin_init_stock(uuid, jsonb) to authenticated;
grant execute on function public.admin_receive_order(uuid) to authenticated;
grant execute on function public.record_sale(date, uuid, uuid, uuid, jsonb, jsonb, text, numeric, text, text) to authenticated;
grant execute on function public.get_oldest_inventory_batch(uuid, uuid) to authenticated;
grant execute on function public.consume_inventory_fifo(uuid, uuid, integer) to authenticated;
grant execute on function public.get_product_selling_price(uuid) to authenticated;
