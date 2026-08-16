-- ============================================================================
-- GATEWAY GAS ENTERPRISES — Migration 0007
-- Fix infinite recursion in the profiles RLS select policy (code 42p17)
--
-- The old policy checked `exists (select 1 from public.profiles ...)`
-- INSIDE a policy ON public.profiles, which re-triggered the same policy
-- forever -> "infinite recursion detected in policy for relation profiles".
--
-- Fix: use the security-definer helper is_admin_or_director() (created in
-- migration 0003). Security-definer functions run as the table owner
-- (postgres), so they bypass RLS and do NOT recurse.
-- ============================================================================

drop policy if exists "profiles_select_own_or_admin" on public.profiles;

create policy "profiles_select_own_or_admin"
  on public.profiles for select to authenticated
  using (auth.uid() = id or public.is_admin_or_director());
