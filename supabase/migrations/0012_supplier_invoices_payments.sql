-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0012
-- Supplier invoices, invoice items, payments & balances
--
-- A supplier's balance = sum(invoices) - sum(payments)  (what we owe).
-- Views expose names so the app can show them to all authenticated users.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Supplier invoices
-- ---------------------------------------------------------------------------
create table if not exists public.supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers (id) on delete cascade,
  invoice_no text not null,
  branch_id uuid references public.branches (id) on delete set null,
  invoice_date date not null default current_date,
  total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
  status text not null default 'unpaid' check (status in ('unpaid', 'partial', 'paid')),
  notes text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (supplier_id, invoice_no)
);
create index if not exists supplier_invoices_supplier_idx
  on public.supplier_invoices (supplier_id, invoice_date desc);

create table if not exists public.supplier_invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.supplier_invoices (id) on delete cascade,
  product_id uuid not null references public.products (id),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  line_total numeric(12,2) not null default 0 check (line_total >= 0)
);
create index if not exists supplier_invoice_items_invoice_idx
  on public.supplier_invoice_items (invoice_id);

-- ---------------------------------------------------------------------------
-- 2. Supplier payments
-- ---------------------------------------------------------------------------
create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers (id) on delete cascade,
  invoice_id uuid references public.supplier_invoices (id) on delete set null,
  amount numeric(12,2) not null check (amount > 0),
  payment_date date not null default current_date,
  method text not null default 'cash' check (method in ('cash', 'mpesa', 'bank', 'cheque')),
  reference text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists supplier_payments_supplier_idx
  on public.supplier_payments (supplier_id, payment_date desc);

-- ---------------------------------------------------------------------------
-- 3. Views (names visible to all authenticated users)
-- ---------------------------------------------------------------------------
create or replace view public.supplier_summary as
select
  s.id, s.name, s.phone, s.contact_person, s.is_active,
  (select coalesce(sum(i.total_amount), 0) from public.supplier_invoices i
    where i.supplier_id = s.id)::numeric(12,2) as invoiced_total,
  (select coalesce(sum(p.amount), 0) from public.supplier_payments p
    where p.supplier_id = s.id)::numeric(12,2) as paid_total,
  ((select coalesce(sum(i.total_amount), 0) from public.supplier_invoices i
      where i.supplier_id = s.id)
   - (select coalesce(sum(p.amount), 0) from public.supplier_payments p
      where p.supplier_id = s.id))::numeric(12,2) as balance
from public.suppliers s;

create or replace view public.supplier_invoices_view as
select
  si.id, si.invoice_no, si.supplier_id, s.name as supplier_name,
  si.branch_id, b.name as branch_name,
  si.invoice_date, si.total_amount, si.status, si.notes, si.created_at,
  (select count(*) from public.supplier_invoice_items it
    where it.invoice_id = si.id) as item_count,
  (select string_agg(p.name || ' x' || it.quantity, ', ' order by p.name)
    from public.supplier_invoice_items it
    join public.products p on p.id = it.product_id
    where it.invoice_id = si.id) as items_summary
from public.supplier_invoices si
left join public.suppliers s on s.id = si.supplier_id
left join public.branches b on b.id = si.branch_id;

create or replace view public.supplier_payments_view as
select
  sp.id, sp.supplier_id, s.name as supplier_name,
  sp.invoice_id, si.invoice_no,
  sp.amount, sp.payment_date, sp.method, sp.reference, sp.created_at
from public.supplier_payments sp
left join public.suppliers s on s.id = sp.supplier_id
left join public.supplier_invoices si on si.id = sp.invoice_id;

grant select on public.supplier_summary to authenticated;
grant select on public.supplier_invoices_view to authenticated;
grant select on public.supplier_payments_view to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS — read for all authenticated, write admin/director only
-- ---------------------------------------------------------------------------
alter table public.supplier_invoices enable row level security;
alter table public.supplier_invoice_items enable row level security;
alter table public.supplier_payments enable row level security;

create policy "supplier_invoices_select" on public.supplier_invoices
  for select to authenticated using (true);
create policy "supplier_invoices_admin_write" on public.supplier_invoices
  for insert to authenticated with check (public.is_admin_or_director());
create policy "supplier_invoices_admin_update" on public.supplier_invoices
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "supplier_invoices_admin_delete" on public.supplier_invoices
  for delete to authenticated using (public.is_admin_or_director());

create policy "supplier_invoice_items_select" on public.supplier_invoice_items
  for select to authenticated using (true);
create policy "supplier_invoice_items_admin_write" on public.supplier_invoice_items
  for insert to authenticated with check (public.is_admin_or_director());
create policy "supplier_invoice_items_admin_update" on public.supplier_invoice_items
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "supplier_invoice_items_admin_delete" on public.supplier_invoice_items
  for delete to authenticated using (public.is_admin_or_director());

create policy "supplier_payments_select" on public.supplier_payments
  for select to authenticated using (true);
create policy "supplier_payments_admin_write" on public.supplier_payments
  for insert to authenticated with check (public.is_admin_or_director());
create policy "supplier_payments_admin_update" on public.supplier_payments
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "supplier_payments_admin_delete" on public.supplier_payments
  for delete to authenticated using (public.is_admin_or_director());

-- ---------------------------------------------------------------------------
-- 5. RPCs (atomic, admin/director only)
-- ---------------------------------------------------------------------------

-- Create a supplier invoice with its line items in one transaction.
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
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  if p_invoice_no is null or trim(p_invoice_no) = '' then
    raise exception 'Invoice number is required';
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
    insert into public.supplier_invoice_items (invoice_id, product_id, quantity, unit_cost, line_total)
    values (v_invoice_id,
            (v_item ->> 'product_id')::uuid,
            (v_item ->> 'quantity')::int,
            coalesce((v_item ->> 'unit_cost')::numeric, 0),
            (v_item ->> 'quantity')::int * coalesce((v_item ->> 'unit_cost')::numeric, 0));
  end loop;

  return jsonb_build_object('invoice_id', v_invoice_id, 'total_amount', v_total);
end;
$$;

-- Record a supplier payment; updates the allocated invoice's status.
create or replace function public.admin_record_supplier_payment(
  p_supplier_id uuid, p_invoice_id uuid, p_amount numeric,
  p_payment_date date, p_method text, p_reference text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paid numeric; v_total numeric;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  if p_amount <= 0 then
    raise exception 'Amount must be positive';
  end if;

  insert into public.supplier_payments
    (supplier_id, invoice_id, amount, payment_date, method, reference, created_by, created_at)
  values (p_supplier_id, p_invoice_id, p_amount, p_payment_date, p_method, p_reference, auth.uid(), now());

  if p_invoice_id is not null then
    select coalesce(sum(amount), 0) into v_paid
      from public.supplier_payments where invoice_id = p_invoice_id;
    select total_amount into v_total
      from public.supplier_invoices where id = p_invoice_id;
    update public.supplier_invoices
      set status = case
            when v_paid >= v_total then 'paid'
            when v_paid > 0 then 'partial'
            else 'unpaid' end
      where id = p_invoice_id;
  end if;
end;
$$;

grant execute on function public.admin_save_supplier_invoice(uuid, text, uuid, date, text, jsonb) to authenticated;
grant execute on function public.admin_record_supplier_payment(uuid, uuid, numeric, date, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Seed suppliers from the product brands (only if table is empty)
-- ---------------------------------------------------------------------------
insert into public.suppliers (name)
select x.n
from (values
  ('Afrigas'), ('K-Gas'), ('Total Energies'), ('Ola Energy'), ('Progas'),
  ('Lake Gas'), ('Tosha'), ('Supa Gas'), ('Jatel'), ('Hashi'), ('Kabsons')
) as t(n)
cross join lateral (select t.n as n) x
where not exists (select 1 from public.suppliers);
