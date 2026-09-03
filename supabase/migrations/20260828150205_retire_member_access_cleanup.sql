-- Treat the Removed access state as staff offboarding from the wellbeing facility.
-- Past history remains for reporting, while future access, future bookings, and
-- personal program links are retired in one admin action.

create or replace function public.update_member_access(
    p_user_id uuid,
    p_access_status text,
    p_induction_complete boolean
)
returns public.profiles
language plpgsql
security invoker
set search_path = public, app_private
as $$
declare
    updated_profile public.profiles;
    previous_profile public.profiles;
    resolved_induction_complete boolean;
    cancelled_booking_count integer := 0;
    archived_program_count integer := 0;
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;

    if p_user_id = auth.uid() then
        raise exception 'You cannot change your own member access.';
    end if;

    if p_access_status not in ('pending', 'active', 'paused', 'suspended', 'removed') then
        raise exception 'Invalid access status.';
    end if;

    select * into previous_profile
    from public.profiles
    where id = p_user_id
      and role = 'member';

    if previous_profile.id is null then
        raise exception 'Member profile not found.';
    end if;

    resolved_induction_complete := p_induction_complete or p_access_status = 'active';

    if p_access_status = 'removed' then
        resolved_induction_complete := false;
    end if;

    update public.profiles
    set access_status = p_access_status,
        induction_completed_at = case
            when resolved_induction_complete then coalesce(induction_completed_at, now())
            else null
        end,
        induction_completed_by = case
            when resolved_induction_complete then coalesce(induction_completed_by, auth.uid())
            else null
        end
    where id = p_user_id
      and role = 'member'
    returning * into updated_profile;

    if p_access_status = 'removed' then
        update public.bookings
        set cancelled_at = coalesce(cancelled_at, now())
        where user_id = p_user_id
          and cancelled_at is null
          and start_time > now();
        get diagnostics cancelled_booking_count = row_count;

        update public.program_assignments
        set archived_at = coalesce(archived_at, now())
        where user_id = p_user_id
          and archived_at is null;
        get diagnostics archived_program_count = row_count;

        perform app_private.log_audit(
            'member_access_removed',
            'profile',
            p_user_id::text,
            to_jsonb(previous_profile),
            jsonb_build_object(
                'profile', to_jsonb(updated_profile),
                'future_bookings_cancelled', cancelled_booking_count,
                'program_assignments_archived', archived_program_count
            )
        );
    end if;

    return updated_profile;
end;
$$;

revoke execute on function public.update_member_access(uuid, text, boolean) from public;
revoke execute on function public.update_member_access(uuid, text, boolean) from anon;
grant execute on function public.update_member_access(uuid, text, boolean) to authenticated;
