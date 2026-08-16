-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0008
-- Price-change requests WITH names view
--
-- The price_change_requests table joins profiles (changed_by), but RLS on
-- profiles only lets you read your own row (or admin). So non-admin viewers
-- saw blank names. This security-definer-style view (owner-rights, like
-- rider_delivery_stats) exposes the joined names to all authenticated users.
-- ============================================================================

create or replace view public.price_change_requests_view as
select
  pcr.id,
  pcr.product_id,
  p.name as product_name,
  pcr.sale_id,
  pcr.old_price,
  pcr.new_price,
  pcr.status,
  pcr.changed_by,
  cb.full_name as changed_by_name,
  cb.role as changed_by_role,
  pcr.confirmed_by,
  cf.full_name as confirmed_by_name,
  cf.role as confirmed_by_role,
  pcr.confirmed_at,
  pcr.note,
  pcr.created_at
from public.price_change_requests pcr
left join public.profiles cb on cb.id = pcr.changed_by
left join public.profiles cf on cf.id = pcr.confirmed_by
left join public.products p on p.id = pcr.product_id;

grant select on public.price_change_requests_view to authenticated;
