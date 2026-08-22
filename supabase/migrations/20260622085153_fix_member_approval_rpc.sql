create or replace function public.update_member_access(
    p_user_id uuid,
    p_access_status text,
    p_induction_complete boolean
)
returns public.profiles
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
    updated_profile public.profiles;
    resolved_induction_complete boolean;
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;

    if p_access_status not in ('pending', 'active', 'paused', 'suspended', 'removed') then
        raise exception 'Invalid access status.';
    end if;

    resolved_induction_complete := p_induction_complete or p_access_status = 'active';

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

    if updated_profile.id is null then
        raise exception 'Member profile not found.';
    end if;

    return updated_profile;
end;
$$;

grant execute on function public.update_member_access(uuid, text, boolean) to authenticated;
