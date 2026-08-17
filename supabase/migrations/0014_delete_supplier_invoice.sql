-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0014
-- Delete a supplier invoice (admin/director only)
--
-- Deleting an invoice also:
--   * reverses the stock that was posted to the branch (adjustment
--     movements, so the audit trail shows exactly what happened)
--   * keeps any payments recorded (they detach from the invoice but
--     remain in the supplier's payment history / balance)
--   * leaves product buying cost as-is (it was set when the invoice
--     was recorded; reverting could corrupt newer costs)
-- ============================================================================

create or replace function public.admin_delete_supplier_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch uuid;
  v_no text;
  v_item record;
begin
  if not (select public.is_admin_or_director()) then
    raise exception 'Not authorized';
  end if;

  select branch_id, invoice_no into v_branch, v_no
    from public.supplier_invoices where id = p_invoice_id;
  if v_no is null then
    raise exception 'Invoice not found';
  end if;

  -- reverse the stock posted from this invoice
  for v_item in
    select product_id, quantity
    from public.supplier_invoice_items
    where invoice_id = p_invoice_id
  loop
    insert into public.stock_movements
      (branch_id, product_id, quantity_change, movement_type,
       reference_id, note, created_by)
    values (v_branch, v_item.product_id, -v_item.quantity, 'adjustment',
            p_invoice_id, 'Invoice ' || v_no || ' deleted (reversal)',
            auth.uid());
  end loop;

  delete from public.supplier_invoice_items where invoice_id = p_invoice_id;
  delete from public.supplier_invoices where id = p_invoice_id;
end;
$$;

grant execute on function public.admin_delete_supplier_invoice(uuid) to authenticated;
