-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0011
-- Stock totals by product size (for the stock overview screen)
--
-- Per branch, per product type, per size (kg): total units on hand.
-- Refills & cylinders are then shown broken down by size (3kg, 6kg,
-- 13kg, 22.5kg, 35kg, 45kg, 50kg) so ordering decisions are easy.
-- ============================================================================

create or replace view public.branch_size_totals as
select
  ps.branch_id,
  b.name as branch_name,
  p.product_type::text as product_type,
  p.size_kg,
  sum(ps.quantity) as total_quantity,
  count(distinct ps.product_id) as product_count
from public.product_stock ps
join public.products p on p.id = ps.product_id
join public.branches b on b.id = ps.branch_id
group by ps.branch_id, b.name, p.product_type::text, p.size_kg;

grant select on public.branch_size_totals to authenticated;
