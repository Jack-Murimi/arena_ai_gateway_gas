-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0010
-- Stock initialization per branch, stock overview views & purchase orders
--
-- * 'opening' stock movement type (monthly stock init, audited)
-- * branch_stock_summary view  — per product per branch (qty, low flag)
-- * branch_type_totals view    — totals per branch per product type
-- * purchase_orders / purchase_order_items — place & receive orders
-- * RPCs: admin_init_stock, admin_place_order, admin_receive_order
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. 'opening' movement type
-- ---------------------------------------------------------------------------
alter type public.stock_movement_type add value if not exists 'opening';

-- ---------------------------------------------------------------------------
-- 2. Purchase orders
-- ---------------------------------------------------------------------------
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique,
  branch_id uuid not null references public.branches (id),
  supplier_id uuid references public.suppliers (id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'placed', 'received', 'cancelled')),
  notes text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  received_at timestamptz
);

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.purchase_orders (id) on delete cascade,
  product_id uuid not null references public.products (id),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0)
);

create sequence if not exists public.po_seq;

-- ---------------------------------------------------------------------------
-- 3. Views
-- ---------------------------------------------------------------------------
create or replace view public.branch_stock_summary as
select
  ps.branch_id,
  b.name as branch_name,
  ps.product_id,
  p.name as product_name,
  p.product_type::text as product_type,
  p.size_kg,
  p.brand,
  ps.quantity,
  p.low_stock_threshold,
  (ps.quantity <= p.low_stock_threshold) as is_low
from public.product_stock ps
join public.products p on p.id = ps.product_id
join public.branches b on b.id = ps.branch_id;

create or replace view public.branch_type_totals as
select
  ps.branch_id,
  b.name as branch_name,
  p.product_type::text as product_type,
  sum(ps.quantity) as total_quantity,
  count(distinct ps.product_id) as product_count
from public.product_stock ps
join public.products p on p.id = ps.product_id
join public.branches b on b.id = ps.branch_id
group by ps.branch_id, b.name, p.product_type::text;

create or replace view public.purchase_orders_view as
select
  po.id, po.order_no, po.branch_id, b.name as branch_name,
  po.supplier_id, s.name as supplier_name,
  po.status, po.notes, po.created_at, po.received_at,
  cp.full_name as created_by_name,
  (select count(*) from public.purchase_order_items i where i.order_id = po.id) as item_count,
  (select coalesce(sum(i.quantity), 0) from public.purchase_order_items i where i.order_id = po.id) as total_quantity,
  (select coalesce(sum(i.quantity * i.unit_cost), 0) from public.purchase_order_items i where i.order_id = po.id) as total_cost
from public.purchase_orders po
left join public.branches b on b.id = po.branch_id
left join public.suppliers s on s.id = po.supplier_id
left join public.profiles cp on cp.id = po.created_by;

grant select on public.branch_stock_summary to authenticated;
grant select on public.branch_type_totals to authenticated;
grant select on public.purchase_orders_view to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;

create policy "purchase_orders_select" on public.purchase_orders
  for select to authenticated using (true);
create policy "purchase_orders_admin_write" on public.purchase_orders
  for insert to authenticated with check (public.is_admin_or_director());
create policy "purchase_orders_admin_update" on public.purchase_orders
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "purchase_orders_admin_delete" on public.purchase_orders
  for delete to authenticated using (public.is_admin_or_director());
create policy "purchase_order_items_select" on public.purchase_order_items
  for select to authenticated using (true);
create policy "purchase_order_items_admin_write" on public.purchase_order_items
  for insert to authenticated with check (public.is_admin_or_director());
create policy "purchase_order_items_admin_update" on public.purchase_order_items
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "purchase_order_items_admin_delete" on public.purchase_order_items
  for delete to authenticated using (public.is_admin_or_director());

-- ---------------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------------

-- Set absolute stock quantities for a branch (monthly init). Logs 'opening'
-- movements so the audit trail shows the change from previous level.
create or replace function public.admin_init_stock(p_branch_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb; v_pid uuid; v_qty int; v_old int; v_delta int;
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
    v_old := coalesce(
      (select quantity from public.product_stock
        where branch_id = p_branch_id and product_id = v_pid), 0);
    v_delta := v_qty - v_old;
    if v_delta <> 0 then
      insert into public.stock_movements
        (branch_id, product_id, quantity_change, movement_type, note, created_by)
      values (p_branch_id, v_pid, v_delta, 'opening',
              'Stock init ' || to_char(now(), 'FMMonth YYYY'), auth.uid());
    end if;
  end loop;
end;
$$;

-- Place a purchase order (status 'placed').
create or replace function public.admin_place_order(
  p_branch_id uuid, p_supplier_id uuid, p_notes text, p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid; v_order_no text; v_item jsonb;
  v_pid uuid; v_qty int; v_cost numeric;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No items in order';
  end if;
  v_order_no := 'PO-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.po_seq')::text, 4, '0');
  insert into public.purchase_orders (order_no, branch_id, supplier_id, status, notes, created_by, created_at)
  values (v_order_no, p_branch_id, p_supplier_id, 'placed', p_notes, auth.uid(), now())
  returning id into v_order_id;
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_pid := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'quantity')::int;
    v_cost := coalesce((v_item ->> 'unit_cost')::numeric, 0);
    if v_qty <= 0 then raise exception 'Invalid quantity'; end if;
    insert into public.purchase_order_items (order_id, product_id, quantity, unit_cost)
    values (v_order_id, v_pid, v_qty, v_cost);
  end loop;
  return jsonb_build_object('order_id', v_order_id, 'order_no', v_order_no);
end;
$$;

-- Receive a placed order: stock-in ('purchase' movements) + update product
-- buying cost from the order cost.
create or replace function public.admin_receive_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch uuid; v_status text; v_item record;
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
    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
    values (v_branch, v_item.product_id, v_item.quantity, 'purchase', p_order_id,
            'PO receive', auth.uid());
    update public.products set cost_price = v_item.unit_cost where id = v_item.product_id;
  end loop;
  update public.purchase_orders set status = 'received', received_at = now()
   where id = p_order_id;
end;
$$;

grant execute on function public.admin_init_stock(uuid, jsonb) to authenticated;
grant execute on function public.admin_place_order(uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.admin_receive_order(uuid) to authenticated;
