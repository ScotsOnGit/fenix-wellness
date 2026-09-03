drop policy if exists wellness_acknowledgements_select on public.wellness_acknowledgements;
drop policy if exists wellness_acknowledgements_public_active_select on public.wellness_acknowledgements;
drop policy if exists wellness_acknowledgements_admin_select on public.wellness_acknowledgements;

create policy wellness_acknowledgements_public_active_select
on public.wellness_acknowledgements
for select
using (is_active);

create policy wellness_acknowledgements_admin_select
on public.wellness_acknowledgements
for select
to authenticated
using ((select app_private.current_user_is_admin()));
