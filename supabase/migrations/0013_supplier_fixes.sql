-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0013
-- Supplier fixes:
--   * Recording a supplier invoice now ALSO updates the product's buying
--     cost (cost_price = unit cost) and adds the quantities to the branch
--     stock (purchase movements) — one atomic operation.
--   * Suppliers: soft-delete (archive) via is_active instead of hard
--     delete, so invoices/payments history stay intact. List hides
--     archived suppliers; write actions admin/director only.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Rewrite admin_save_supplier_invoice (cost + stock)
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

    -- update the product's buying cost from the invoice
    if v_cost > 0 then
      update public.products set cost_price = v_cost where id = v_pid;
    end if;

    -- stock-in for the branch (audited as a purchase movement)
    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
    values (p_branch_id, v_pid, v_qty, 'purchase', v_invoice_id,
            'Supplier invoice ' || trim(p_invoice_no), auth.uid());
  end loop;

  return jsonb_build_object('invoice_id', v_invoice_id, 'total_amount', v_total);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Supplier soft-delete (archive) helper
-- ---------------------------------------------------------------------------
create or replace function public.admin_archive_supplier(p_supplier_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;
  update public.suppliers set is_active = false where id = p_supplier_id;
end;
$$;

grant execute on function public.admin_archive_supplier(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Tighter supplier RLS: select for all, write admin/director only
-- ---------------------------------------------------------------------------
drop policy if exists "suppliers_all_authenticated" on public.suppliers;
create policy "suppliers_select" on public.suppliers
  for select to authenticated using (true);
create policy "suppliers_admin_insert" on public.suppliers
  for insert to authenticated with check (public.is_admin_or_director());
create policy "suppliers_admin_update" on public.suppliers
  for update to authenticated using (public.is_admin_or_director()) with check (public.is_admin_or_director());
create policy "suppliers_admin_delete" on public.suppliers
  for delete to authenticated using (public.is_admin_or_director());
