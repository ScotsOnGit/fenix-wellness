-- Fix profile RLS recursion seen when an admin promotes a registered member.
-- The previous update policy queried public.profiles from inside a profiles
-- policy, which can recurse while PostgREST checks the update.

create or replace function app_private.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
    select exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'admin'
    )
$$;

create or replace function app_private.current_user_is_active_member()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
    select exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and access_status = 'active'
          and induction_completed_at is not null
    )
$$;

drop policy if exists profiles_select_own_or_admin on public.profiles;
drop policy if exists profiles_update_own_or_admin on public.profiles;
drop policy if exists profiles_admin_insert on public.profiles;
drop policy if exists profiles_admin_delete on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;

create policy profiles_select_own_or_admin
on public.profiles
for select
to authenticated
using (
    id = (select auth.uid())
    or (select app_private.current_user_is_admin())
);

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy profiles_update_admin
on public.profiles
for update
to authenticated
using ((select app_private.current_user_is_admin()))
with check ((select app_private.current_user_is_admin()));

create policy profiles_admin_insert
on public.profiles
for insert
to authenticated
with check ((select app_private.current_user_is_admin()));

create policy profiles_admin_delete
on public.profiles
for delete
to authenticated
using ((select app_private.current_user_is_admin()));
