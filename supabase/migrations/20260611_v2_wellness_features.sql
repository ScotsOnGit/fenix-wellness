-- Fenix Wellbeing Facility v2 feature layer.
-- Adds access approval, attendance/check-in, resources/programs, reporting, and audit logging.

alter table public.profiles
    add column if not exists access_status text not null default 'pending',
    add column if not exists induction_completed_at timestamptz,
    add column if not exists induction_completed_by uuid references public.profiles(id),
    add column if not exists last_seen_at timestamptz;

alter table public.profiles
    drop constraint if exists profiles_access_status_check,
    add constraint profiles_access_status_check
        check (access_status in ('pending', 'active', 'paused', 'suspended', 'removed'));

update public.profiles
set access_status = 'active',
    induction_completed_at = coalesce(induction_completed_at, created_at)
where access_status = 'pending';

alter table public.bookings
    add column if not exists checked_in_at timestamptz,
    add column if not exists checked_out_at timestamptz,
    add column if not exists no_show_marked_at timestamptz;

alter table public.facility_rules
    add column if not exists check_in_grace_minutes integer not null default 15,
    add column if not exists check_in_window_before_minutes integer not null default 10,
    add column if not exists check_in_code text not null default 'FENIX-WELLNESS-CENTRE';

update public.facility_rules
set allowed_durations_minutes = array[15, 30, 45],
    capacity = 20,
    booking_horizon_days = 7,
    max_active_bookings_per_day = 1
where id = true;

create table if not exists public.wellness_resources (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    description text,
    category text not null default 'General',
    resource_type text not null default 'link',
    url text,
    storage_path text,
    is_published boolean not null default false,
    created_by uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint wellness_resources_type_check check (resource_type in ('link', 'pdf')),
    constraint wellness_resources_source_check check (
        (resource_type = 'link' and nullif(trim(coalesce(url, '')), '') is not null)
        or (resource_type = 'pdf' and nullif(trim(coalesce(storage_path, '')), '') is not null)
    )
);

alter table public.wellness_resources
    alter column created_by set default auth.uid();

create table if not exists public.program_assignments (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    title text not null,
    description text,
    resource_type text not null default 'link',
    url text,
    storage_path text,
    assigned_by uuid references public.profiles(id),
    assigned_at timestamptz not null default now(),
    archived_at timestamptz,
    constraint program_assignments_type_check check (resource_type in ('link', 'pdf')),
    constraint program_assignments_source_check check (
        (resource_type = 'link' and nullif(trim(coalesce(url, '')), '') is not null)
        or (resource_type = 'pdf' and nullif(trim(coalesce(storage_path, '')), '') is not null)
    )
);

alter table public.program_assignments
    alter column assigned_by set default auth.uid();

create table if not exists public.audit_log (
    id bigint generated always as identity primary key,
    actor_id uuid references public.profiles(id),
    action text not null,
    target_type text not null,
    target_id text,
    before_data jsonb,
    after_data jsonb,
    created_at timestamptz not null default now()
);

alter table public.wellness_resources enable row level security;
alter table public.program_assignments enable row level security;
alter table public.audit_log enable row level security;

insert into storage.buckets (id, name, public)
values ('wellness-resources', 'wellness-resources', false)
on conflict (id) do nothing;

create or replace function app_private.current_user_is_active_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and access_status = 'active'
          and induction_completed_at is not null
    )
$$;

create or replace function app_private.log_audit(
    p_action text,
    p_target_type text,
    p_target_id text,
    p_before_data jsonb default null,
    p_after_data jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.audit_log (actor_id, action, target_type, target_id, before_data, after_data)
    values (auth.uid(), p_action, p_target_type, p_target_id, p_before_data, p_after_data);
end;
$$;

create or replace function app_private.audit_profile_update()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
    if old.role is distinct from new.role
        or old.access_status is distinct from new.access_status
        or old.induction_completed_at is distinct from new.induction_completed_at then
        perform app_private.log_audit(
            'profile_access_changed',
            'profile',
            new.id::text,
            jsonb_build_object(
                'role', old.role,
                'access_status', old.access_status,
                'induction_completed_at', old.induction_completed_at
            ),
            jsonb_build_object(
                'role', new.role,
                'access_status', new.access_status,
                'induction_completed_at', new.induction_completed_at
            )
        );
    end if;
    return new;
end;
$$;

drop trigger if exists audit_profile_update on public.profiles;
create trigger audit_profile_update
after update on public.profiles
for each row execute function app_private.audit_profile_update();

create or replace function app_private.prevent_member_profile_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
    if app_private.current_user_is_admin() then
        return new;
    end if;

    if old.role is distinct from new.role
        or old.access_status is distinct from new.access_status
        or old.induction_completed_at is distinct from new.induction_completed_at
        or old.induction_completed_by is distinct from new.induction_completed_by then
        raise exception 'Admin access is required to change wellbeing facility access.';
    end if;

    return new;
end;
$$;

drop trigger if exists prevent_member_profile_escalation on public.profiles;
create trigger prevent_member_profile_escalation
before update on public.profiles
for each row execute function app_private.prevent_member_profile_escalation();

create or replace function app_private.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
    insert into public.profiles (id, full_name, email, phone, role, access_status)
    values (
        new.id,
        coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(new.email, '@', 1)),
        lower(new.email),
        nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), ''),
        'member',
        'pending'
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

create or replace function app_private.booking_failure_reason(
    p_user_id uuid,
    p_start_time timestamptz,
    p_end_time timestamptz
)
returns text
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
    rules public.facility_rules%rowtype;
    profile public.profiles%rowtype;
    duration_minutes integer;
    local_start timestamp;
    local_end timestamp;
    local_date date;
    local_weekday integer;
    local_start_time time;
    local_end_time time;
    occupied integer;
begin
    select * into rules from public.facility_rules where id = true;
    if not found then
        return 'Cannot confirm current facility rules.';
    end if;

    if p_user_id is null or p_user_id <> auth.uid() then
        return 'Please sign in again to continue.';
    end if;

    select * into profile from public.profiles where id = p_user_id;
    if not found then
        return 'Your staff profile could not be found.';
    end if;
    if profile.access_status <> 'active' or profile.induction_completed_at is null then
        return 'Your wellbeing facility access is pending admin induction approval.';
    end if;

    if p_end_time <= p_start_time then
        return 'Booking end time must be after the start time.';
    end if;

    if extract(second from p_start_time) <> 0
        or (extract(minute from p_start_time)::integer % rules.booking_interval_minutes) <> 0 then
        return 'Bookings must start on a 15-minute boundary.';
    end if;

    duration_minutes := (extract(epoch from (p_end_time - p_start_time)) / 60)::integer;
    if not duration_minutes = any(rules.allowed_durations_minutes) then
        return 'Choose a 15, 30, or 45 minute session.';
    end if;

    if p_start_time < now() then
        return 'Bookings cannot start in the past.';
    end if;

    if p_start_time > now() + make_interval(days => rules.booking_horizon_days) then
        return 'Bookings can only be made up to 7 days in advance.';
    end if;

    local_start := p_start_time at time zone rules.timezone_identifier;
    local_end := p_end_time at time zone rules.timezone_identifier;
    local_date := local_start::date;
    local_weekday := extract(dow from local_start)::integer;
    local_start_time := local_start::time;
    local_end_time := local_end::time;

    if exists (
        select 1
        from public.opening_hours oh
        where oh.weekday = local_weekday
          and (oh.is_closed or local_start_time < oh.opens_at or local_end_time > oh.closes_at or local_end::date <> local_date)
    ) then
        return 'This session is outside wellbeing facility opening hours.';
    end if;

    if exists (
        select 1
        from public.blackout_periods bp
        where tstzrange(bp.starts_at, bp.ends_at, '[)') && tstzrange(p_start_time, p_end_time, '[)')
    ) then
        return 'This session overlaps a blackout period.';
    end if;

    if (
        select count(*)
        from public.bookings b
        where b.user_id = p_user_id
          and b.cancelled_at is null
          and b.start_time > now()
    ) >= rules.max_future_bookings then
        return 'You already have five upcoming bookings.';
    end if;

    if (
        select count(*)
        from public.bookings b
        where b.user_id = p_user_id
          and b.cancelled_at is null
          and (b.start_time at time zone rules.timezone_identifier)::date = local_date
    ) >= rules.max_active_bookings_per_day then
        return 'You already have a booking on this day.';
    end if;

    select count(*) into occupied
    from public.bookings b
    where b.cancelled_at is null
      and b.start_time <= p_start_time
      and b.end_time > p_start_time;

    if occupied >= rules.capacity then
        return 'This start time is full.';
    end if;

    return null;
end;
$$;

create or replace function public.get_availability_for_date(p_date date, p_duration_minutes integer)
returns table (
    start_time timestamptz,
    end_time timestamptz,
    occupied_count integer,
    remaining_capacity integer,
    status text,
    failure_reason text
)
language sql
stable
set search_path = public, app_private
as $$
    select *
    from app_private.get_availability_for_date(p_date, p_duration_minutes)
$$;

create or replace function public.check_in_booking(p_code text)
returns public.bookings
language plpgsql
set search_path = public, app_private
as $$
declare
    rules public.facility_rules%rowtype;
    target_booking public.bookings;
begin
    select * into rules from public.facility_rules where id = true;

    if rules.check_in_code is null or trim(p_code) <> rules.check_in_code then
        raise exception 'This QR code is not valid for the wellbeing facility.';
    end if;

    select * into target_booking
    from public.bookings b
    where b.user_id = auth.uid()
      and b.cancelled_at is null
      and b.start_time <= now() + make_interval(mins => rules.check_in_window_before_minutes)
      and b.end_time >= now()
    order by b.start_time asc
    limit 1;

    if target_booking.id is null then
        raise exception 'No active booking is available for check-in right now.';
    end if;

    update public.bookings
    set checked_in_at = coalesce(checked_in_at, now()),
        no_show_marked_at = null
    where id = target_booking.id
    returning * into target_booking;

    perform app_private.log_audit('booking_checked_in', 'booking', target_booking.id::text, null, to_jsonb(target_booking));
    return target_booking;
end;
$$;

create or replace function public.check_out_booking(p_booking_id uuid)
returns public.bookings
language plpgsql
set search_path = public, app_private
as $$
declare
    target_booking public.bookings;
begin
    update public.bookings
    set checked_out_at = coalesce(checked_out_at, now())
    where id = p_booking_id
      and user_id = auth.uid()
      and checked_in_at is not null
      and checked_out_at is null
    returning * into target_booking;

    if target_booking.id is null then
        raise exception 'This booking cannot be checked out.';
    end if;

    perform app_private.log_audit('booking_checked_out', 'booking', target_booking.id::text, null, to_jsonb(target_booking));
    return target_booking;
end;
$$;

create or replace function public.mark_due_no_shows()
returns integer
language plpgsql
set search_path = public, app_private
as $$
declare
    rules public.facility_rules%rowtype;
    updated_count integer;
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;

    select * into rules from public.facility_rules where id = true;

    update public.bookings
    set no_show_marked_at = now()
    where cancelled_at is null
      and checked_in_at is null
      and no_show_marked_at is null
      and start_time < now() - make_interval(mins => rules.check_in_grace_minutes);

    get diagnostics updated_count = row_count;
    perform app_private.log_audit('no_shows_marked', 'booking', null, null, jsonb_build_object('count', updated_count));
    return updated_count;
end;
$$;

create or replace function public.update_member_access(
    p_user_id uuid,
    p_access_status text,
    p_induction_complete boolean
)
returns public.profiles
language plpgsql
set search_path = public, app_private
as $$
declare
    updated_profile public.profiles;
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;
    if p_access_status not in ('pending', 'active', 'paused', 'suspended', 'removed') then
        raise exception 'Invalid access status.';
    end if;

    update public.profiles
    set access_status = p_access_status,
        induction_completed_at = case
            when p_induction_complete then coalesce(induction_completed_at, now())
            else null
        end,
        induction_completed_by = case
            when p_induction_complete then coalesce(induction_completed_by, auth.uid())
            else null
        end
    where id = p_user_id
    returning * into updated_profile;

    if updated_profile.id is null then
        raise exception 'Member profile not found.';
    end if;

    return updated_profile;
end;
$$;

create or replace function public.admin_report_summary(p_start_date date, p_end_date date)
returns table (
    total_bookings integer,
    active_members integer,
    attended_count integer,
    no_show_count integer,
    cancelled_count integer,
    peak_hour integer
)
language plpgsql
stable
set search_path = public, app_private
as $$
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;

    return query
    with filtered as (
        select *
        from public.bookings b
        where (b.start_time at time zone 'Australia/Perth')::date between p_start_date and p_end_date
    ),
    by_hour as (
        select extract(hour from start_time at time zone 'Australia/Perth')::integer as hour_value, count(*) as booking_count
        from filtered
        group by 1
        order by booking_count desc, hour_value asc
        limit 1
    )
    select
        (select count(*)::integer from filtered),
        (select count(*)::integer from public.profiles where access_status = 'active'),
        (select count(*)::integer from filtered where checked_in_at is not null),
        (select count(*)::integer from filtered where no_show_marked_at is not null),
        (select count(*)::integer from filtered where cancelled_at is not null),
        coalesce((select hour_value from by_hour), 0);
end;
$$;

create or replace function public.admin_bookings_export(p_start_date date, p_end_date date)
returns table (
    booking_id uuid,
    member_name text,
    email text,
    start_time timestamptz,
    end_time timestamptz,
    cancelled_at timestamptz,
    checked_in_at timestamptz,
    checked_out_at timestamptz,
    no_show_marked_at timestamptz
)
language plpgsql
stable
set search_path = public, app_private
as $$
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;

    return query
    select
        b.id,
        p.full_name,
        p.email,
        b.start_time,
        b.end_time,
        b.cancelled_at,
        b.checked_in_at,
        b.checked_out_at,
        b.no_show_marked_at
    from public.bookings b
    join public.profiles p on p.id = b.user_id
    where (b.start_time at time zone 'Australia/Perth')::date between p_start_date and p_end_date
    order by b.start_time asc;
end;
$$;

drop policy if exists wellness_resources_select on public.wellness_resources;
create policy wellness_resources_select on public.wellness_resources
for select to authenticated
using ((is_published and app_private.current_user_is_active_member()) or app_private.current_user_is_admin());

drop policy if exists wellness_resources_admin_write on public.wellness_resources;
create policy wellness_resources_admin_write on public.wellness_resources
for all to authenticated
using (app_private.current_user_is_admin())
with check (app_private.current_user_is_admin());

drop policy if exists program_assignments_select on public.program_assignments;
create policy program_assignments_select on public.program_assignments
for select to authenticated
using ((user_id = auth.uid() and app_private.current_user_is_active_member()) or app_private.current_user_is_admin());

drop policy if exists program_assignments_admin_write on public.program_assignments;
create policy program_assignments_admin_write on public.program_assignments
for all to authenticated
using (app_private.current_user_is_admin())
with check (app_private.current_user_is_admin());

drop policy if exists audit_log_admin_select on public.audit_log;
create policy audit_log_admin_select on public.audit_log
for select to authenticated
using (app_private.current_user_is_admin());

drop policy if exists audit_log_no_client_write on public.audit_log;
create policy audit_log_no_client_write on public.audit_log
for all to authenticated
using (false)
with check (false);

drop policy if exists storage_wellness_select on storage.objects;
create policy storage_wellness_select on storage.objects
for select to authenticated
using (
    bucket_id = 'wellness-resources'
    and (
        app_private.current_user_is_admin()
        or exists (
            select 1
            from public.wellness_resources wr
            where wr.storage_path = name
              and wr.is_published
              and app_private.current_user_is_active_member()
        )
        or exists (
            select 1
            from public.program_assignments pa
            where pa.storage_path = name
              and pa.user_id = auth.uid()
              and pa.archived_at is null
              and app_private.current_user_is_active_member()
        )
    )
);

drop policy if exists storage_wellness_admin_write on storage.objects;
create policy storage_wellness_admin_write on storage.objects
for all to authenticated
using (bucket_id = 'wellness-resources' and app_private.current_user_is_admin())
with check (bucket_id = 'wellness-resources' and app_private.current_user_is_admin());

grant select, insert, update, delete on public.wellness_resources to authenticated;
grant select, insert, update, delete on public.program_assignments to authenticated;
grant select on public.audit_log to authenticated;
grant execute on function public.check_in_booking(text) to authenticated;
grant execute on function public.check_out_booking(uuid) to authenticated;
grant execute on function public.mark_due_no_shows() to authenticated;
grant execute on function public.update_member_access(uuid, text, boolean) to authenticated;
grant execute on function public.admin_report_summary(date, date) to authenticated;
grant execute on function public.admin_bookings_export(date, date) to authenticated;

create index if not exists idx_audit_log_actor_id on public.audit_log(actor_id);
create index if not exists idx_profiles_induction_completed_by on public.profiles(induction_completed_by);
create index if not exists idx_program_assignments_assigned_by on public.program_assignments(assigned_by);
create index if not exists idx_program_assignments_user_id on public.program_assignments(user_id);
create index if not exists idx_wellness_resources_created_by on public.wellness_resources(created_by);

drop policy if exists wellness_resources_select on public.wellness_resources;
drop policy if exists wellness_resources_admin_write on public.wellness_resources;
create policy wellness_resources_select on public.wellness_resources
for select to authenticated
using ((is_published and (select app_private.current_user_is_active_member())) or (select app_private.current_user_is_admin()));
create policy wellness_resources_admin_insert on public.wellness_resources
for insert to authenticated
with check ((select app_private.current_user_is_admin()));
create policy wellness_resources_admin_update on public.wellness_resources
for update to authenticated
using ((select app_private.current_user_is_admin()))
with check ((select app_private.current_user_is_admin()));
create policy wellness_resources_admin_delete on public.wellness_resources
for delete to authenticated
using ((select app_private.current_user_is_admin()));

drop policy if exists program_assignments_select on public.program_assignments;
drop policy if exists program_assignments_admin_write on public.program_assignments;
create policy program_assignments_select on public.program_assignments
for select to authenticated
using ((user_id = (select auth.uid()) and (select app_private.current_user_is_active_member())) or (select app_private.current_user_is_admin()));
create policy program_assignments_admin_insert on public.program_assignments
for insert to authenticated
with check ((select app_private.current_user_is_admin()));
create policy program_assignments_admin_update on public.program_assignments
for update to authenticated
using ((select app_private.current_user_is_admin()))
with check ((select app_private.current_user_is_admin()));
create policy program_assignments_admin_delete on public.program_assignments
for delete to authenticated
using ((select app_private.current_user_is_admin()));

drop policy if exists audit_log_admin_select on public.audit_log;
drop policy if exists audit_log_no_client_write on public.audit_log;
create policy audit_log_admin_select on public.audit_log
for select to authenticated
using ((select app_private.current_user_is_admin()));

drop policy if exists storage_wellness_select on storage.objects;
drop policy if exists storage_wellness_admin_write on storage.objects;
create policy storage_wellness_select on storage.objects
for select to authenticated
using (
    bucket_id = 'wellness-resources'
    and (
        (select app_private.current_user_is_admin())
        or exists (
            select 1
            from public.wellness_resources wr
            where wr.storage_path = name
              and wr.is_published
              and (select app_private.current_user_is_active_member())
        )
        or exists (
            select 1
            from public.program_assignments pa
            where pa.storage_path = name
              and pa.user_id = (select auth.uid())
              and pa.archived_at is null
              and (select app_private.current_user_is_active_member())
        )
    )
);
create policy storage_wellness_admin_insert on storage.objects
for insert to authenticated
with check (bucket_id = 'wellness-resources' and (select app_private.current_user_is_admin()));
create policy storage_wellness_admin_update on storage.objects
for update to authenticated
using (bucket_id = 'wellness-resources' and (select app_private.current_user_is_admin()))
with check (bucket_id = 'wellness-resources' and (select app_private.current_user_is_admin()));
create policy storage_wellness_admin_delete on storage.objects
for delete to authenticated
using (bucket_id = 'wellness-resources' and (select app_private.current_user_is_admin()));
