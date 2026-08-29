create or replace function app_private.max_occupied_during_session(
    p_start_time timestamptz,
    p_end_time timestamptz,
    p_interval_minutes integer
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    with checkpoints as (
        select generate_series(
            p_start_time,
            p_end_time - make_interval(mins => p_interval_minutes),
            make_interval(mins => p_interval_minutes)
        ) as checkpoint
    ),
    occupancy as (
        select count(b.id)::integer as occupied_count
        from checkpoints c
        left join public.bookings b
          on b.cancelled_at is null
         and b.start_time <= c.checkpoint
         and b.end_time > c.checkpoint
        group by c.checkpoint
    )
    select coalesce(max(occupied_count), 0) from occupancy
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
        return 'Your wellness centre access is pending admin induction approval.';
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
        return 'This session is outside wellness centre opening hours.';
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

    occupied := app_private.max_occupied_during_session(
        p_start_time,
        p_end_time,
        rules.booking_interval_minutes
    );

    if occupied >= rules.capacity then
        return 'This session is full.';
    end if;

    return null;
end;
$$;

create or replace function app_private.get_availability_for_date(p_date date, p_duration_minutes integer)
returns table (
    start_time timestamptz,
    end_time timestamptz,
    occupied_count integer,
    remaining_capacity integer,
    status text,
    failure_reason text
)
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
    rules public.facility_rules%rowtype;
    oh public.opening_hours%rowtype;
    local_start timestamp;
    local_end timestamp;
    candidate_start timestamptz;
    candidate_end timestamptz;
    occupied integer;
    reason text;
begin
    select * into rules from public.facility_rules where id = true;
    if not found then
        return;
    end if;

    if not p_duration_minutes = any(rules.allowed_durations_minutes) then
        return;
    end if;

    select * into oh
    from public.opening_hours
    where weekday = extract(dow from p_date)::integer;

    if not found or oh.is_closed then
        return;
    end if;

    if p_date < (now() at time zone rules.timezone_identifier)::date then
        return;
    end if;

    local_start := p_date::timestamp + oh.opens_at;
    local_end := p_date::timestamp + oh.closes_at;

    while local_start + make_interval(mins => p_duration_minutes) <= local_end loop
        candidate_start := local_start at time zone rules.timezone_identifier;
        candidate_end := (local_start + make_interval(mins => p_duration_minutes)) at time zone rules.timezone_identifier;

        if candidate_start >= now() then
            occupied := app_private.max_occupied_during_session(
                candidate_start,
                candidate_end,
                rules.booking_interval_minutes
            );

            reason := case
                when occupied >= rules.capacity then 'This session is full.'
                when exists (
                    select 1
                    from public.blackout_periods bp
                    where tstzrange(bp.starts_at, bp.ends_at, '[)') && tstzrange(candidate_start, candidate_end, '[)')
                ) then 'This session overlaps a blackout period.'
                else null
            end;

            start_time := candidate_start;
            end_time := candidate_end;
            occupied_count := occupied;
            remaining_capacity := greatest(rules.capacity - occupied, 0);
            status := case
                when reason is not null or occupied >= rules.capacity then 'full'
                when occupied >= greatest(rules.capacity - 5, 1) then 'nearly_full'
                else 'available'
            end;
            failure_reason := reason;
            return next;
        end if;

        local_start := local_start + make_interval(mins => rules.booking_interval_minutes);
    end loop;
end;
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
    if not app_private.current_user_is_active_member() then
        raise exception 'Active wellness centre access is required to check in.';
    end if;

    select * into rules from public.facility_rules where id = true;

    if rules.check_in_code is null or trim(p_code) <> rules.check_in_code then
        raise exception 'This QR code is not valid for the wellness centre.';
    end if;

    select * into target_booking
    from public.bookings b
    where b.user_id = auth.uid()
      and b.cancelled_at is null
      and b.checked_out_at is null
      and b.no_show_marked_at is null
      and b.start_time <= now() + make_interval(mins => rules.check_in_window_before_minutes)
      and b.start_time >= now() - make_interval(mins => rules.check_in_grace_minutes)
    order by b.start_time asc
    limit 1;

    if target_booking.id is null then
        raise exception 'Check-in is available from 10 minutes before your session until the check-in grace period ends.';
    end if;

    update public.bookings
    set checked_in_at = coalesce(checked_in_at, now())
    where id = target_booking.id
    returning * into target_booking;

    perform app_private.log_audit('booking_checked_in', 'booking', target_booking.id::text, null, to_jsonb(target_booking));
    return target_booking;
end;
$$;

revoke execute on function public.admin_bookings_export(date, date) from public, anon;
revoke execute on function public.admin_report_summary(date, date) from public, anon;
revoke execute on function public.check_in_booking(text) from public, anon;
revoke execute on function public.mark_due_no_shows() from public, anon;
revoke execute on function public.get_availability_for_date(date, integer) from public, anon;

grant execute on function public.admin_bookings_export(date, date) to authenticated;
grant execute on function public.admin_report_summary(date, date) to authenticated;
grant execute on function public.check_in_booking(text) to authenticated;
grant execute on function public.mark_due_no_shows() to authenticated;
grant execute on function public.get_availability_for_date(date, integer) to authenticated;
