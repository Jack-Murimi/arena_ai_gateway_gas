-- Rider profile editing and dated temporary branch assignments.

create table public.rider_branch_assignments (
	id uuid primary key default gen_random_uuid(),
	rider_id uuid not null references public.profiles(id) on delete cascade,
	branch_id uuid not null references public.branches(id) on delete cascade,
	starts_on date not null,
	ends_on date not null,
	note text,
	created_by uuid references public.profiles(id) on delete set null,
	created_at timestamptz not null default now(),
	check (ends_on >= starts_on)
);

create index rider_branch_assignments_lookup_idx
	on public.rider_branch_assignments(rider_id, starts_on, ends_on);

alter table public.rider_branch_assignments enable row level security;
create policy rider_branch_assignments_authenticated
	on public.rider_branch_assignments for all to authenticated
	using (true) with check (true);
grant select, insert, update, delete on public.rider_branch_assignments to authenticated;

create or replace function public.admin_update_rider(
	p_rider_id uuid, p_email text, p_full_name text, p_phone text, p_branch_id uuid
) returns void language plpgsql security definer set search_path = public as $$
begin
	if not (select public.is_admin_or_director()) then raise exception 'Not authorized'; end if;
	update auth.users set email = lower(trim(p_email)) where id = p_rider_id;
	update public.profiles
		 set full_name = trim(p_full_name), phone = nullif(trim(p_phone), ''), branch_id = p_branch_id
	 where id = p_rider_id and role = 'rider';
	if not found then raise exception 'Rider not found'; end if;
end;
$$;

create or replace function public.admin_assign_rider_branch(
	p_rider_id uuid, p_branch_id uuid, p_starts_on date, p_ends_on date, p_note text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
	if not (select public.is_admin_or_director()) then raise exception 'Not authorized'; end if;
	if p_ends_on < p_starts_on then raise exception 'End date must not be before start date'; end if;
	insert into public.rider_branch_assignments
		(rider_id, branch_id, starts_on, ends_on, note, created_by)
	values (p_rider_id, p_branch_id, p_starts_on, p_ends_on, nullif(trim(p_note), ''), auth.uid())
	returning id into v_id;
	return v_id;
end;
$$;

grant execute on function public.admin_update_rider(uuid, text, text, text, uuid) to authenticated;
grant execute on function public.admin_assign_rider_branch(uuid, uuid, date, date, text) to authenticated;

create or replace function public.admin_get_rider_email(p_rider_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_email text;
begin
	if not (select public.is_admin_or_director()) then raise exception 'Not authorized'; end if;
	select email into v_email from auth.users where id = p_rider_id;
	return v_email;
end;
$$;

grant execute on function public.admin_get_rider_email(uuid) to authenticated;
