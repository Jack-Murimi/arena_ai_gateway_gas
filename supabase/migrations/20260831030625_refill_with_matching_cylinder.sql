-- Create a refill and its matching empty cylinder as one operation.

create or replace function public.create_refill_with_cylinder(
	p_refill_name text,
	p_brand text,
	p_size_kg numeric,
	p_refill_sale_price numeric,
	p_refill_cost_price numeric,
	p_cylinder_name text,
	p_cylinder_sale_price numeric,
	p_cylinder_cost_price numeric,
	p_low_stock_threshold integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
	v_refill_id uuid;
	v_cylinder_id uuid;
begin
	if auth.uid() is null then raise exception 'Not authenticated'; end if;
	if p_size_kg is null or p_size_kg <= 0 then raise exception 'Invalid cylinder size'; end if;
	if p_refill_sale_price < 0 or p_refill_cost_price < 0 or
		 p_cylinder_sale_price < 0 or p_cylinder_cost_price < 0 then
		raise exception 'Prices cannot be negative';
	end if;
	insert into public.products
		(name, product_type, size_kg, brand, sale_price, cost_price, low_stock_threshold)
	values
		(trim(p_refill_name), 'refill', p_size_kg, nullif(trim(p_brand), ''),
		 p_refill_sale_price, p_refill_cost_price, p_low_stock_threshold)
	returning id into v_refill_id;
	insert into public.products
		(name, product_type, size_kg, brand, sale_price, cost_price, low_stock_threshold)
	values
		(trim(p_cylinder_name), 'cylinder', p_size_kg, nullif(trim(p_brand), ''),
		 p_cylinder_sale_price, p_cylinder_cost_price, p_low_stock_threshold)
	returning id into v_cylinder_id;
	return jsonb_build_object('refill_id', v_refill_id, 'cylinder_id', v_cylinder_id);
end;
$$;

grant execute on function public.create_refill_with_cylinder(text, text, numeric, numeric, numeric, text, numeric, numeric, integer) to authenticated;
