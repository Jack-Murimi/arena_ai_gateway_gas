-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0023
-- Atomic customer save RPC: save customer + contacts + locations in a single
-- transaction to prevent partial updates.
-- ============================================================================

-- Type for contact input
create type public.customer_contact_input as (
  name text,
  phone text,
  is_primary boolean
);

-- Type for location input
create type public.customer_location_input as (
  name text,
  address text,
  is_primary boolean,
  default_product_id uuid
);

-- Type for complete customer save input
create type public.save_customer_input as (
  customer_id uuid,
  name text,
  email text,
  credit_limit numeric,
  contacts public.customer_contact_input[],
  locations public.customer_location_input[]
);

-- Type for save customer output
create type public.save_customer_output as (
  customer_id uuid,
  success boolean,
  message text
);

-- ---------------------------------------------------------------------------
-- RPC: save_customer_atomic
-- Saves a customer with all contacts and locations atomically.
-- If customer_id is null, creates a new customer.
-- Otherwise, updates the existing customer and replaces all contacts/locations.
-- ---------------------------------------------------------------------------
create or replace function public.save_customer_atomic(
  p_input public.save_customer_input
) returns public.save_customer_output
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_contact_id uuid;
  v_location_id uuid;
begin
  -- Create or update customer
  if p_input.customer_id is null then
    -- Insert new customer
    insert into public.customers (name, email, credit_limit)
    values (p_input.name, p_input.email, p_input.credit_limit)
    returning id into v_customer_id;
  else
    -- Update existing customer
    update public.customers
       set name = p_input.name,
           email = p_input.email,
           credit_limit = p_input.credit_limit
     where id = p_input.customer_id
     returning id into v_customer_id;
  end if;

  -- Delete existing contacts and locations for this customer
  if v_customer_id is not null then
    delete from public.customer_contacts where customer_id = v_customer_id;
    delete from public.customer_locations where customer_id = v_customer_id;
  end if;

  -- Insert new contacts
  if p_input.contacts is not null and array_length(p_input.contacts, 1) > 0 then
    for i in 1..array_length(p_input.contacts, 1)
    loop
      insert into public.customer_contacts (customer_id, name, phone, is_primary)
      values (v_customer_id, p_input.contacts[i].name, p_input.contacts[i].phone, p_input.contacts[i].is_primary);
    end loop;
  end if;

  -- Insert new locations
  if p_input.locations is not null and array_length(p_input.locations, 1) > 0 then
    for i in 1..array_length(p_input.locations, 1)
    loop
      insert into public.customer_locations (customer_id, name, address, is_primary, default_product_id)
      values (v_customer_id, p_input.locations[i].name, p_input.locations[i].address, 
              p_input.locations[i].is_primary, p_input.locations[i].default_product_id);
    end loop;
  end if;

  return row_to_json((v_customer_id, true, 'Customer saved successfully')::public.save_customer_output);

exception when others then
  return row_to_json((p_input.customer_id, false, sqlerrm)::public.save_customer_output);
end;
$$;

-- Grant execute permission
grant execute on function public.save_customer_atomic(public.save_customer_input) to authenticated;
