-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0016
-- Report views: daily sales, payment methods, debtors, stock valuation,
-- and a best-sellers RPC (date range).
-- ============================================================================

-- Daily sales per branch
create or replace view public.daily_sales_summary as
select
  s.sale_date,
  b.id as branch_id,
  b.name as branch_name,
  count(*) as sales_count,
  coalesce(sum(s.total), 0)::numeric(12,2) as total_sales,
  coalesce(sum(s.total) filter (where s.payment_status = 'paid'), 0)::numeric(12,2) as paid_total,
  coalesce(sum(s.total) filter (where s.payment_status = 'unpaid'), 0)::numeric(12,2) as unpaid_total,
  coalesce(sum(s.total) filter (where s.payment_status = 'partial'), 0)::numeric(12,2) as partial_total
from public.sales s
join public.branches b on b.id = s.branch_id
where s.status = 'complete'
group by s.sale_date, b.id, b.name;

-- Payments by method per day
create or replace view public.payment_methods_summary as
select
  s.sale_date,
  p.method::text as method,
  count(*) as payment_count,
  coalesce(sum(p.amount), 0)::numeric(12,2) as amount
from public.payments p
join public.sales s on s.id = p.sale_id
where s.status = 'complete'
group by s.sale_date, p.method::text;

-- Debtors (customers with an outstanding balance)
create or replace view public.debtors_view as
select
  c.id, c.name, c.phone,
  c.balance, c.credit_limit, c.created_at
from public.customers c
where c.balance > 0.001 and c.is_active;

-- Stock valuation per branch
create or replace view public.stock_valuation_view as
select
  ps.branch_id,
  b.name as branch_name,
  count(distinct ps.product_id) as product_count,
  coalesce(sum(ps.quantity * p.cost_price), 0)::numeric(12,2) as cost_value,
  coalesce(sum(ps.quantity * p.sale_price), 0)::numeric(12,2) as retail_value
from public.product_stock ps
join public.products p on p.id = ps.product_id
join public.branches b on b.id = ps.branch_id
group by ps.branch_id, b.name;

-- Best sellers within a date range
create or replace function public.report_best_sellers(p_from date, p_to date)
returns table (
  product_name text,
  product_type text,
  quantity_sold bigint,
  revenue numeric
)
language sql
security definer
set search_path = public
as $$
  select
    p.name as product_name,
    p.product_type::text as product_type,
    sum(si.quantity) as quantity_sold,
    sum(si.line_total) as revenue
  from public.sale_items si
  join public.products p on p.id = si.product_id
  join public.sales s on s.id = si.sale_id
  where s.status = 'complete'
    and s.sale_date between p_from and p_to
  group by p.name, p.product_type::text
  order by sum(si.quantity) desc
  limit 50;
$$;

grant select on public.daily_sales_summary to authenticated;
grant select on public.payment_methods_summary to authenticated;
grant select on public.debtors_view to authenticated;
grant select on public.stock_valuation_view to authenticated;
grant execute on function public.report_best_sellers(date, date) to authenticated;
