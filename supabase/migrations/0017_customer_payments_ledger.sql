-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0017
-- Customer payments (recorded against their account) + ledger view
-- ============================================================================

-- Record a payment against a customer's account: inserts a payment row and
-- a ledger credit entry, and reduces the customer balance.
create or replace function public.record_customer_payment(
  p_customer_id uuid,
  p_amount numeric,
  p_method text,
  p_mpesa_code text,
  p_payment_date date,
  p_note text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment_id uuid;
  v_balance numeric;
  v_method public.payment_method;
begin
  if not exists (select 1 from public.customers where id = p_customer_id) then
    raise exception 'Customer not found';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be positive';
  end if;
  v_method := coalesce(nullif(trim(p_method), '')::public.payment_method, 'cash');

  insert into public.payments
    (customer_id, amount, method, mpesa_code, received_by, created_at)
  values (p_customer_id, p_amount, v_method, nullif(trim(coalesce(p_mpesa_code, '')), ''),
          auth.uid(), now())
  returning id into v_payment_id;

  select coalesce(balance, 0) into v_balance from public.customers where id = p_customer_id;

  insert into public.customer_account_entries
    (customer_id, payment_id, entry_type, debit, credit, balance_after, created_by, created_at)
  values (p_customer_id, v_payment_id, 'payment', 0, p_amount,
          v_balance - p_amount, auth.uid(), now());

  update public.customers set balance = balance - p_amount where id = p_customer_id;

  return jsonb_build_object('payment_id', v_payment_id, 'balance_after', v_balance - p_amount);
end;
$$;

grant execute on function public.record_customer_payment(uuid, numeric, text, text, date, text) to authenticated;

-- Ledger: every entry with its context (invoice no / payment method)
create or replace view public.customer_ledger_view as
select
  e.id, e.customer_id, e.entry_type, e.debit, e.credit, e.balance_after,
  e.created_at, s.invoice_no, p.method::text as payment_method, p.mpesa_code
from public.customer_account_entries e
left join public.sales s on s.id = e.sale_id
left join public.payments p on p.id = e.payment_id;

grant select on public.customer_ledger_view to authenticated;
