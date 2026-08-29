-- ============================================================================
-- 0022 · Comprehensive branch stock summary across all products and branches
--
-- Ensures every active product is represented for every active branch with its
-- current on-hand stock quantity (defaulting to 0 when no stock movement has
-- occurred yet). This allows the stock overview, multi-branch matrix view, and
-- point-of-sale to show accurate stock levels and branch comparisons even for
-- newly created branches or products.
-- ============================================================================

create or replace view public.branch_stock_summary as
select
  b.id as branch_id,
  b.name as branch_name,
  p.id as product_id,
  p.name as product_name,
  p.product_type::text as product_type,
  p.size_kg,
  p.brand,
  coalesce(ps.quantity, 0) as quantity,
  p.low_stock_threshold,
  (coalesce(ps.quantity, 0) <= p.low_stock_threshold) as is_low
from public.branches b
cross join public.products p
left join public.product_stock ps on ps.branch_id = b.id and ps.product_id = p.id
where b.is_active and p.is_active;

grant select on public.branch_stock_summary to authenticated;
