-- Branch-aware report queries for the Reports screen and CSV export.

drop view if exists public.payment_methods_summary;

create view public.payment_methods_summary as
select
	s.sale_date,
	s.branch_id,
	p.method::text as method,
	count(*) as payment_count,
	coalesce(sum(p.amount), 0)::numeric(12,2) as amount
from public.payments p
join public.sales s on s.id = p.sale_id
where s.status = 'complete'
group by s.sale_date, s.branch_id, p.method::text;

drop function if exists public.report_best_sellers(date, date);

create function public.report_best_sellers(
	p_from date,
	p_to date,
	p_branch_id uuid default null
)
returns table (
	product_name text,
	product_type text,
	quantity_sold bigint,
	revenue numeric
)
language sql
security invoker
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
		and (p_branch_id is null or s.branch_id = p_branch_id)
	group by p.name, p.product_type::text
	order by sum(si.quantity) desc
	limit 50;
$$;

grant select on public.payment_methods_summary to authenticated;
grant execute on function public.report_best_sellers(date, date, uuid) to authenticated;
