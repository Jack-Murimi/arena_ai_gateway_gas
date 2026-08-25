-- ============================================================================
-- 0021 · Inter-branch stock transfers with returnable refill cylinders
--
-- A refill is a full physical cylinder. Dispatch moves the full refill from
-- source stock immediately; receipt posts it to the destination. For each
-- refill, the matching EMPTY cylinder remains due back to the source until
-- staff record its return. This preserves the branch cylinder fleet totals.
-- ============================================================================

create sequence if not exists public.stock_transfer_number_seq;

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  transfer_no text not null unique,
  source_branch_id uuid not null references public.branches(id),
  destination_branch_id uuid not null references public.branches(id),
  status text not null default 'draft'
    check (status in ('draft', 'dispatched', 'received', 'returned', 'cancelled')),
  notes text,
  created_by uuid references public.profiles(id),
  dispatched_at timestamptz,
  received_at timestamptz,
  returned_at timestamptz,
  created_at timestamptz not null default now(),
  check (source_branch_id <> destination_branch_id)
);

create table if not exists public.stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  -- Only refill lines have physical cylinders due back. Non-refill lines stay 0.
  cylinders_returned integer not null default 0 check (cylinders_returned >= 0 and cylinders_returned <= quantity),
  created_at timestamptz not null default now(),
  unique (transfer_id, product_id)
);

create index if not exists stock_transfers_source_idx on public.stock_transfers(source_branch_id, status, created_at desc);
create index if not exists stock_transfers_destination_idx on public.stock_transfers(destination_branch_id, status, created_at desc);
create index if not exists stock_transfer_items_transfer_idx on public.stock_transfer_items(transfer_id);

create or replace function public.set_stock_transfer_number()
returns trigger language plpgsql as $$
begin
  if new.transfer_no is null or trim(new.transfer_no) = '' then
    new.transfer_no := 'TRF-' || lpad(nextval('public.stock_transfer_number_seq')::text, 6, '0');
  end if;
  if new.created_by is null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;
drop trigger if exists trg_stock_transfer_number on public.stock_transfers;
create trigger trg_stock_transfer_number before insert on public.stock_transfers
for each row execute function public.set_stock_transfer_number();

-- The transfer item list becomes immutable after dispatch, keeping the stock
-- audit trail and the cylinder-return obligation consistent.
create or replace function public.lock_dispatched_transfer_items()
returns trigger language plpgsql as $$
declare v_status text;
begin
  select status into v_status from public.stock_transfers
  where id = coalesce(new.transfer_id, old.transfer_id);
  if v_status <> 'draft' then raise exception 'Transfer items cannot be edited after dispatch'; end if;
  return coalesce(new, old);
end;
$$;
drop trigger if exists trg_lock_dispatched_transfer_items on public.stock_transfer_items;
create trigger trg_lock_dispatched_transfer_items
before insert or update or delete on public.stock_transfer_items
for each row execute function public.lock_dispatched_transfer_items();

alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_items enable row level security;
create policy "stock_transfers_authenticated" on public.stock_transfers for all to authenticated using (true) with check (true);
create policy "stock_transfer_items_authenticated" on public.stock_transfer_items for all to authenticated using (true) with check (true);

-- Dispatch: source loses stock now. A row lock and quantity condition stop
-- concurrent transfers from taking stock below zero.
create or replace function public.dispatch_stock_transfer(p_transfer_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_source uuid; v_available integer;
begin
  select source_branch_id into v_source from public.stock_transfers
   where id = p_transfer_id and status = 'draft' for update;
  if v_source is null then raise exception 'Only draft transfers can be dispatched'; end if;
  if not exists (select 1 from public.stock_transfer_items where transfer_id = p_transfer_id) then
    raise exception 'Add at least one item before dispatching';
  end if;

  for r in select i.product_id, i.quantity, p.name from public.stock_transfer_items i join public.products p on p.id=i.product_id where i.transfer_id=p_transfer_id loop
    select quantity into v_available from public.product_stock
      where branch_id=v_source and product_id=r.product_id for update;
    if coalesce(v_available, 0) < r.quantity then
      raise exception 'Insufficient source stock for %', r.name;
    end if;
    -- The stock-movement trigger is the only writer of the stock balance.
    insert into public.stock_movements(branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
      values(v_source, r.product_id, -r.quantity, 'transfer', p_transfer_id, 'Transfer dispatched', auth.uid());
  end loop;
  update public.stock_transfers set status='dispatched', dispatched_at=now() where id=p_transfer_id;
end;
$$;

-- Receipt: destination gets the same product, including full refills.
create or replace function public.receive_stock_transfer(p_transfer_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_destination uuid;
begin
  select destination_branch_id into v_destination from public.stock_transfers
   where id=p_transfer_id and status='dispatched' for update;
  if v_destination is null then raise exception 'Only dispatched transfers can be received'; end if;
  for r in select product_id, quantity from public.stock_transfer_items where transfer_id=p_transfer_id loop
    insert into public.stock_movements(branch_id, product_id, quantity_change, movement_type, reference_id, note, created_by)
      values(v_destination, r.product_id, r.quantity, 'transfer', p_transfer_id, 'Transfer received', auth.uid());
  end loop;
  update public.stock_transfers set status='received', received_at=now() where id=p_transfer_id;
end;
$$;

-- Return empty cylinders for one refill line. The matching cylinder product is
-- found by brand + size, so e.g. Afrigas 13kg refill returns Afrigas 13kg empty.
create or replace function public.return_transfer_cylinders(p_transfer_item_id uuid, p_quantity integer)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_cylinder_product uuid;
begin
  if p_quantity is null or p_quantity <= 0 then raise exception 'Return quantity must be positive'; end if;
  select t.id transfer_id,t.source_branch_id,t.destination_branch_id,t.status,i.quantity,i.cylinders_returned,p.product_type,p.brand,p.size_kg
    into r from public.stock_transfer_items i join public.stock_transfers t on t.id=i.transfer_id join public.products p on p.id=i.product_id
    where i.id=p_transfer_item_id for update;
  if r.transfer_id is null or r.status not in ('received','returned') then raise exception 'Cylinders can be returned only after receipt'; end if;
  if r.product_type <> 'refill'::public.product_type then raise exception 'Only refill items have returnable cylinders'; end if;
  if r.cylinders_returned + p_quantity > r.quantity then raise exception 'Cannot return more cylinders than transferred'; end if;
  select id into v_cylinder_product from public.products
    where product_type='cylinder'::public.product_type and brand is not distinct from r.brand and size_kg is not distinct from r.size_kg and is_active
    limit 1;
  if v_cylinder_product is null then raise exception 'No matching empty-cylinder product exists for this refill'; end if;
  -- Verify before insert: the stock-movement trigger enforces the actual update.
  if coalesce((select quantity from public.product_stock where branch_id=r.destination_branch_id and product_id=v_cylinder_product),0) < p_quantity then
    raise exception 'Destination does not have enough matching empty cylinders to return';
  end if;
  insert into public.stock_movements(branch_id,product_id,quantity_change,movement_type,reference_id,note,created_by)
    values(r.destination_branch_id,v_cylinder_product,-p_quantity,'transfer',r.transfer_id,'Empty cylinder returned to source',auth.uid()),
          (r.source_branch_id,v_cylinder_product,p_quantity,'transfer',r.transfer_id,'Empty cylinder returned from destination',auth.uid());
  update public.stock_transfer_items set cylinders_returned=cylinders_returned+p_quantity where id=p_transfer_item_id;
  update public.stock_transfers set status='returned',returned_at=now() where id=r.transfer_id
    and not exists (select 1 from public.stock_transfer_items i join public.products p on p.id=i.product_id where i.transfer_id=r.transfer_id and p.product_type='refill'::public.product_type and i.cylinders_returned<i.quantity);
end;
$$;

grant execute on function public.dispatch_stock_transfer(uuid), public.receive_stock_transfer(uuid), public.return_transfer_cylinders(uuid, integer) to authenticated;
