-- RLS policies define which rows can be changed, but the authenticated role
-- also needs table-level privileges before those policies can take effect.

grant select, update on public.profiles to authenticated;
grant select, update on public.bookings to authenticated;
grant select, insert, update, delete on public.program_assignments to authenticated;

-- These admin/user tables should not be directly available to anonymous users.
revoke all on public.audit_log from anon;
revoke all on public.program_assignments from anon;
revoke all on public.profiles from anon;
revoke all on public.bookings from anon;
