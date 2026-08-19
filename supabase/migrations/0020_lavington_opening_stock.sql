-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0020
-- Lavington opening stock support
--
--  * Create missing products (3kg refills, Jatel 6kg, Safe/Hass/Wanjiku/
--    Afrigas45/Progas/Lake/Jamii empties, water bottles)
--  * Fix '13kg Afrigas Cylinder' brand (was Shell) so fleet grouping is
--    correct
--  * admin_init_stock now takes a reconciliation date (used in the audit
--    note + movement created_at) for backdated reconciliations
-- ============================================================================

insert into public.products (name, product_type, size_kg, brand, sale_price, cost_price, low_stock_threshold)
select x.name, x.product_type::public.product_type, x.size_kg, x.brand, 0, 0, 5
from (values
  ('3kg Lake Gas refill',    'refill',    3,    'Lake Gas'),
  ('3kg Total refill',       'refill',    3,    'Total'),
  ('6kg Jatel refill',       'refill',    6,    'Jatel'),
  ('6kg Progas Cylinder',    'cylinder',  6,    'Progas'),
  ('35kg Safe Gas Cylinder', 'cylinder',  35,   'Safe Gas'),
  ('13kg Hass Cylinder',     'cylinder',  13,   'Hass'),
  ('13kg Wanjiku Cylinder',  'cylinder',  13,   'Wanjiku'),
  ('50kg Progas Cylinder',   'cylinder',  50,   'Progas'),
  ('50kg Lake Gas Cylinder', 'cylinder',  50,   'Lake Gas'),
  ('50kg Jamii Cylinder',    'cylinder',  50,   'Jamii'),
  ('Aquamist water',         'accessory', null, 'Aquamist'),
  ('Aquamist empty',         'accessory', null, 'Aquamist'),
  ('Keringet water',         'accessory', null, 'Keringet'),
  ('Keringet empty',         'accessory', null, 'Keringet')
) as x (name, product_type, size_kg, brand)
where not exists (select 1 from public.products p where p.name = x.name);

-- fix the Afrigas cylinder brand so fleet groups it with Afrigas
update public.products set brand = 'Afrigas'
 where name = '13kg Afrigas Cylinder' and coalesce(brand, '') = 'Shell';

-- ---------------------------------------------------------------------------
-- admin_init_stock with a reconciliation date
-- ---------------------------------------------------------------------------
create or replace function public.admin_init_stock(
  p_branch_id uuid, p_items jsonb, p_date date default current_date
) returns void
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
        (branch_id, product_id, quantity_change, movement_type, note, created_by, created_at)
      values (p_branch_id, v_pid, v_delta, 'opening',
              'Reconciliation ' || to_char(p_date, 'YYYY-MM-DD') ||
              ' (was ' || v_old || ', counted ' || v_qty || ')',
              auth.uid(), p_date::timestamptz);
    end if;
  end loop;
end;
$$;

grant execute on function public.admin_init_stock(uuid, jsonb, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Correction (2026-08-19): Safe cylinders are 13kg, not 35kg.
-- 35kg total at Lavington = 3 (K-Gas 1 + Hashi 2).
-- ---------------------------------------------------------------------------
update public.products set size_kg = 13 where name in ('35kg Safe Gas refill', '35kg Safe Gas Cylinder');
update public.products set name = '13kg Safe Gas refill'   where name = '35kg Safe Gas refill';
update public.products set name = '13kg Safe Gas Cylinder' where name = '35kg Safe Gas Cylinder';
