--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
-- SET transaction_timeout = 0; -- Not available on all Postgres/Supabase versions.
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app_private; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA IF NOT EXISTS "app_private";


ALTER SCHEMA "app_private" OWNER TO "postgres";

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";

--
-- Name: SCHEMA "public"; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA "public" IS 'standard public schema';


--
-- Name: audit_profile_update(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."audit_profile_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "app_private"."audit_profile_update"() OWNER TO "postgres";

--
-- Name: audit_wellbeing_challenge_change(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."audit_wellbeing_challenge_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
begin
    if tg_op = 'INSERT' then
        perform app_private.log_audit('challenge_created', 'wellbeing_challenge', new.id::text, null, to_jsonb(new));
        return new;
    elsif tg_op = 'UPDATE' then
        perform app_private.log_audit('challenge_updated', 'wellbeing_challenge', new.id::text, to_jsonb(old), to_jsonb(new));
        return new;
    elsif tg_op = 'DELETE' then
        perform app_private.log_audit('challenge_deleted', 'wellbeing_challenge', old.id::text, to_jsonb(old), null);
        return old;
    end if;
    return null;
end;
$$;


ALTER FUNCTION "app_private"."audit_wellbeing_challenge_change"() OWNER TO "postgres";

--
-- Name: booking_failure_reason("uuid", timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."booking_failure_reason"("p_user_id" "uuid", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "app_private"."booking_failure_reason"("p_user_id" "uuid", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) OWNER TO "postgres";

--
-- Name: current_user_is_active_member(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."current_user_is_active_member"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
    select exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and access_status = 'active'
          and induction_completed_at is not null
    )
$$;


ALTER FUNCTION "app_private"."current_user_is_active_member"() OWNER TO "postgres";

--
-- Name: current_user_is_admin(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."current_user_is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
    select exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'admin'
    )
$$;


ALTER FUNCTION "app_private"."current_user_is_admin"() OWNER TO "postgres";

--
-- Name: get_availability_for_date("date", integer); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) RETURNS TABLE("start_time" timestamp with time zone, "end_time" timestamp with time zone, "occupied_count" integer, "remaining_capacity" integer, "status" "text", "failure_reason" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "app_private"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) OWNER TO "postgres";

--
-- Name: handle_new_user_profile(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."handle_new_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "app_private"."handle_new_user_profile"() OWNER TO "postgres";

--
-- Name: is_approved_staff_email("text"); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."is_approved_staff_email"("email" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
    select lower(coalesce(email, '')) like '%@fenix.com.au'
$$;


ALTER FUNCTION "app_private"."is_approved_staff_email"("email" "text") OWNER TO "postgres";

--
-- Name: log_audit("text", "text", "text", "jsonb", "jsonb"); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."log_audit"("p_action" "text", "p_target_type" "text", "p_target_id" "text", "p_before_data" "jsonb" DEFAULT NULL::"jsonb", "p_after_data" "jsonb" DEFAULT NULL::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    insert into public.audit_log (actor_id, action, target_type, target_id, before_data, after_data)
    values (auth.uid(), p_action, p_target_type, p_target_id, p_before_data, p_after_data);
end;
$$;


ALTER FUNCTION "app_private"."log_audit"("p_action" "text", "p_target_type" "text", "p_target_id" "text", "p_before_data" "jsonb", "p_after_data" "jsonb") OWNER TO "postgres";

--
-- Name: max_occupied_during_session(timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."max_occupied_during_session"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_interval_minutes" integer) RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "app_private"."max_occupied_during_session"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_interval_minutes" integer) OWNER TO "postgres";

--
-- Name: prevent_member_profile_escalation(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."prevent_member_profile_escalation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
begin
    if app_private.current_user_is_admin() then
        return new;
    end if;

    if old.role is distinct from new.role
        or old.access_status is distinct from new.access_status
        or old.induction_completed_at is distinct from new.induction_completed_at
        or old.induction_completed_by is distinct from new.induction_completed_by then
        raise exception 'Admin access is required to change wellness centre access.';
    end if;

    return new;
end;
$$;


ALTER FUNCTION "app_private"."prevent_member_profile_escalation"() OWNER TO "postgres";

--
-- Name: touch_updated_at(); Type: FUNCTION; Schema: app_private; Owner: postgres
--

CREATE FUNCTION "app_private"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    new.updated_at = now();
    return new;
end;
$$;


ALTER FUNCTION "app_private"."touch_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

--
-- Name: wellbeing_challenge_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."wellbeing_challenge_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "challenge_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "value" numeric NOT NULL,
    "note" "text",
    "entry_date" "date" DEFAULT (("now"() AT TIME ZONE 'Australia/Perth'::"text"))::"date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wellbeing_challenge_entries_value_check" CHECK (("value" > (0)::numeric))
);


ALTER TABLE "public"."wellbeing_challenge_entries" OWNER TO "postgres";

--
-- Name: add_wellbeing_challenge_entry("uuid", numeric, "text", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."add_wellbeing_challenge_entry"("p_challenge_id" "uuid", "p_value" numeric, "p_note" "text", "p_entry_date" "date") RETURNS "public"."wellbeing_challenge_entries"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
    challenge public.wellbeing_challenges;
    entry public.wellbeing_challenge_entries;
begin
    if not app_private.current_user_is_active_member() then
        raise exception 'Active wellness centre access is required to log challenge progress.';
    end if;

    if p_value <= 0 then
        raise exception 'Progress value must be greater than zero.';
    end if;

    select * into challenge
    from public.wellbeing_challenges
    where id = p_challenge_id
      and is_published;

    if challenge.id is null then
        raise exception 'Challenge not found.';
    end if;

    if p_entry_date < challenge.starts_on or p_entry_date > challenge.ends_on then
        raise exception 'Progress date must be within the challenge dates.';
    end if;

    perform public.join_wellbeing_challenge(p_challenge_id);

    insert into public.wellbeing_challenge_entries (challenge_id, user_id, value, note, entry_date)
    values (p_challenge_id, auth.uid(), p_value, nullif(trim(coalesce(p_note, '')), ''), p_entry_date)
    returning * into entry;

    return entry;
end;
$$;


ALTER FUNCTION "public"."add_wellbeing_challenge_entry"("p_challenge_id" "uuid", "p_value" numeric, "p_note" "text", "p_entry_date" "date") OWNER TO "postgres";

--
-- Name: admin_bookings_export("date", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_bookings_export"("p_start_date" "date", "p_end_date" "date") RETURNS TABLE("booking_id" "uuid", "member_name" "text", "email" "text", "start_time" timestamp with time zone, "end_time" timestamp with time zone, "cancelled_at" timestamp with time zone, "checked_in_at" timestamp with time zone, "checked_out_at" timestamp with time zone, "no_show_marked_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "public"."admin_bookings_export"("p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";

--
-- Name: admin_report_summary("date", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_report_summary"("p_start_date" "date", "p_end_date" "date") RETURNS TABLE("total_bookings" integer, "active_members" integer, "attended_count" integer, "no_show_count" integer, "cancelled_count" integer, "peak_hour" integer)
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "public"."admin_report_summary"("p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";

--
-- Name: bookings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "start_time" timestamp with time zone NOT NULL,
    "end_time" timestamp with time zone NOT NULL,
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "checked_in_at" timestamp with time zone,
    "checked_out_at" timestamp with time zone,
    "no_show_marked_at" timestamp with time zone,
    CONSTRAINT "bookings_check" CHECK (("end_time" > "start_time")),
    CONSTRAINT "bookings_check1" CHECK ((((EXTRACT(epoch FROM ("end_time" - "start_time")) / (60)::numeric))::integer = ANY (ARRAY[15, 30, 45, 60]))),
    CONSTRAINT "bookings_start_time_check" CHECK ((EXTRACT(second FROM "start_time") = (0)::numeric)),
    CONSTRAINT "bookings_start_time_check1" CHECK ((((EXTRACT(minute FROM "start_time"))::integer % 15) = 0))
);

ALTER TABLE ONLY "public"."bookings" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."bookings" OWNER TO "postgres";

--
-- Name: cancel_booking("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") RETURNS "public"."bookings"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
    cutoff integer;
    updated_booking public.bookings;
begin
    select cancellation_cutoff_minutes into cutoff from public.facility_rules where id = true;

    update public.bookings
    set cancelled_at = now()
    where id = p_booking_id
      and cancelled_at is null
      and (
        app_private.current_user_is_admin()
        or (user_id = auth.uid() and start_time > now() + make_interval(mins => cutoff))
      )
    returning * into updated_booking;

    if updated_booking.id is null then
        raise exception 'Booking cannot be cancelled after the cutoff.';
    end if;

    return updated_booking;
end;
$$;


ALTER FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") OWNER TO "postgres";

--
-- Name: check_in_booking("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."check_in_booking"("p_code" "text") RETURNS "public"."bookings"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "public"."check_in_booking"("p_code" "text") OWNER TO "postgres";

--
-- Name: check_out_booking("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."check_out_booking"("p_booking_id" "uuid") RETURNS "public"."bookings"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "public"."check_out_booking"("p_booking_id" "uuid") OWNER TO "postgres";

--
-- Name: create_booking(timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_booking"("p_start_time" timestamp with time zone, "p_duration_minutes" integer) RETURNS "public"."bookings"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
    p_end_time timestamptz;
    failure_reason text;
    new_booking public.bookings;
begin
    perform pg_advisory_xact_lock(hashtext('fenix_gym_booking_capacity'));

    p_end_time := p_start_time + make_interval(mins => p_duration_minutes);
    failure_reason := app_private.booking_failure_reason(auth.uid(), p_start_time, p_end_time);

    if failure_reason is not null then
        raise exception using message = failure_reason;
    end if;

    insert into public.bookings (user_id, start_time, end_time)
    values (auth.uid(), p_start_time, p_end_time)
    returning * into new_booking;

    return new_booking;
end;
$$;


ALTER FUNCTION "public"."create_booking"("p_start_time" timestamp with time zone, "p_duration_minutes" integer) OWNER TO "postgres";

--
-- Name: get_availability_for_date("date", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) RETURNS TABLE("start_time" timestamp with time zone, "end_time" timestamp with time zone, "occupied_count" integer, "remaining_capacity" integer, "status" "text", "failure_reason" "text")
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public', 'app_private'
    AS $$
    select *
    from app_private.get_availability_for_date(p_date, p_duration_minutes)
$$;


ALTER FUNCTION "public"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) OWNER TO "postgres";

--
-- Name: wellbeing_challenge_participants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."wellbeing_challenge_participants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "challenge_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."wellbeing_challenge_participants" OWNER TO "postgres";

--
-- Name: join_wellbeing_challenge("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."join_wellbeing_challenge"("p_challenge_id" "uuid") RETURNS "public"."wellbeing_challenge_participants"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
    challenge public.wellbeing_challenges;
    participant public.wellbeing_challenge_participants;
begin
    if not app_private.current_user_is_active_member() then
        raise exception 'Active wellness centre access is required to join challenges.';
    end if;

    select * into challenge
    from public.wellbeing_challenges
    where id = p_challenge_id
      and is_published;

    if challenge.id is null then
        raise exception 'Challenge not found.';
    end if;

    insert into public.wellbeing_challenge_participants (challenge_id, user_id)
    values (p_challenge_id, auth.uid())
    on conflict (challenge_id, user_id) do update
    set joined_at = public.wellbeing_challenge_participants.joined_at
    returning * into participant;

    return participant;
end;
$$;


ALTER FUNCTION "public"."join_wellbeing_challenge"("p_challenge_id" "uuid") OWNER TO "postgres";

--
-- Name: mark_due_no_shows(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."mark_due_no_shows"() RETURNS integer
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "public"."mark_due_no_shows"() OWNER TO "postgres";

--
-- Name: wellness_acknowledgements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."wellness_acknowledgements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "capacity_text" "text" DEFAULT ''::"text" NOT NULL,
    "fair_use_text" "text" DEFAULT ''::"text" NOT NULL,
    "medical_text" "text" DEFAULT ''::"text" NOT NULL,
    "is_active" boolean DEFAULT false NOT NULL,
    "published_at" timestamp with time zone,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wellness_acknowledgements_required_copy_check" CHECK (((NULLIF(TRIM(BOTH FROM "title"), ''::"text") IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM "body"), ''::"text") IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM "fair_use_text"), ''::"text") IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM "medical_text"), ''::"text") IS NOT NULL)))
);


ALTER TABLE "public"."wellness_acknowledgements" OWNER TO "postgres";

--
-- Name: publish_wellness_acknowledgement("text", "text", "text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."publish_wellness_acknowledgement"("p_title" "text", "p_body" "text", "p_capacity_text" "text", "p_fair_use_text" "text", "p_medical_text" "text") RETURNS "public"."wellness_acknowledgements"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
    previous_acknowledgement public.wellness_acknowledgements;
    published_acknowledgement public.wellness_acknowledgements;
begin
    if not app_private.current_user_is_admin() then
        raise exception 'Admin access required.';
    end if;

    if nullif(trim(p_title), '') is null
        or nullif(trim(p_body), '') is null
        or nullif(trim(p_fair_use_text), '') is null
        or nullif(trim(p_medical_text), '') is null then
        raise exception 'Acknowledgement title, body, fair use, and medical wording are required.';
    end if;

    select *
    into previous_acknowledgement
    from public.wellness_acknowledgements
    where is_active
    limit 1;

    update public.wellness_acknowledgements
    set is_active = false
    where is_active;

    insert into public.wellness_acknowledgements (
        version,
        title,
        body,
        capacity_text,
        fair_use_text,
        medical_text,
        is_active,
        published_at,
        created_by
    )
    values (
        'v' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'),
        trim(p_title),
        trim(p_body),
        coalesce(trim(p_capacity_text), ''),
        trim(p_fair_use_text),
        trim(p_medical_text),
        true,
        now(),
        auth.uid()
    )
    returning * into published_acknowledgement;

    perform app_private.log_audit(
        'acknowledgement_published',
        'wellness_acknowledgement',
        published_acknowledgement.id::text,
        case when previous_acknowledgement.id is null then null else to_jsonb(previous_acknowledgement) end,
        to_jsonb(published_acknowledgement)
    );

    return published_acknowledgement;
end;
$$;


ALTER FUNCTION "public"."publish_wellness_acknowledgement"("p_title" "text", "p_body" "text", "p_capacity_text" "text", "p_fair_use_text" "text", "p_medical_text" "text") OWNER TO "postgres";

--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "access_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "induction_completed_at" timestamp with time zone,
    "induction_completed_by" "uuid",
    "last_seen_at" timestamp with time zone,
    CONSTRAINT "profiles_access_status_check" CHECK (("access_status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'paused'::"text", 'suspended'::"text", 'removed'::"text"]))),
    CONSTRAINT "profiles_full_name_check" CHECK (("length"(TRIM(BOTH FROM "full_name")) > 0)),
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['member'::"text", 'admin'::"text"])))
);

ALTER TABLE ONLY "public"."profiles" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" OWNER TO "postgres";

--
-- Name: update_member_access("uuid", "text", boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_member_access"("p_user_id" "uuid", "p_access_status" "text", "p_induction_complete" boolean) RETURNS "public"."profiles"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
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


ALTER FUNCTION "public"."update_member_access"("p_user_id" "uuid", "p_access_status" "text", "p_induction_complete" boolean) OWNER TO "postgres";

--
-- Name: wellbeing_challenge_leaderboard("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."wellbeing_challenge_leaderboard"("p_challenge_id" "uuid") RETURNS TABLE("user_id" "uuid", "member_name" "text", "total_value" numeric, "entry_count" integer, "rank" integer)
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
    challenge public.wellbeing_challenges;
begin
    select * into challenge
    from public.wellbeing_challenges
    where id = p_challenge_id;

    if challenge.id is null then
        raise exception 'Challenge not found.';
    end if;

    if not app_private.current_user_is_admin()
       and not (challenge.is_published and challenge.leaderboard_visible and app_private.current_user_is_active_member()) then
        raise exception 'Leaderboard is not available for this challenge.';
    end if;

    return query
    with totals as (
        select
            e.user_id,
            coalesce(p.full_name, p.email, 'Member') as member_name,
            sum(e.value) as total_value,
            count(*)::integer as entry_count
        from public.wellbeing_challenge_entries e
        join public.profiles p on p.id = e.user_id
        where e.challenge_id = p_challenge_id
        group by e.user_id, p.full_name, p.email
    ),
    ranked as (
        select
            totals.*,
            dense_rank() over (order by totals.total_value desc)::integer as rank
        from totals
    )
    select ranked.user_id, ranked.member_name, ranked.total_value, ranked.entry_count, ranked.rank
    from ranked
    order by ranked.rank asc, ranked.member_name asc;
end;
$$;


ALTER FUNCTION "public"."wellbeing_challenge_leaderboard"("p_challenge_id" "uuid") OWNER TO "postgres";

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."audit_log" (
    "id" bigint NOT NULL,
    "actor_id" "uuid",
    "action" "text" NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "text",
    "before_data" "jsonb",
    "after_data" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."audit_log" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."audit_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: blackout_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."blackout_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "reason" "text" DEFAULT 'Facility unavailable'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "blackout_periods_check" CHECK (("ends_at" > "starts_at"))
);

ALTER TABLE ONLY "public"."blackout_periods" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."blackout_periods" OWNER TO "postgres";

--
-- Name: facility_contact; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."facility_contact" (
    "id" boolean DEFAULT true NOT NULL,
    "display_name" "text" DEFAULT 'Fenix Wellbeing Facility'::"text" NOT NULL,
    "address" "text",
    "phone" "text",
    "email" "text",
    "notes" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "facility_contact_id_check" CHECK ("id")
);


ALTER TABLE "public"."facility_contact" OWNER TO "postgres";

--
-- Name: facility_rules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."facility_rules" (
    "id" boolean DEFAULT true NOT NULL,
    "capacity" integer DEFAULT 20 NOT NULL,
    "booking_interval_minutes" integer DEFAULT 15 NOT NULL,
    "allowed_durations_minutes" integer[] DEFAULT ARRAY[15, 30, 45, 60] NOT NULL,
    "cancellation_cutoff_minutes" integer DEFAULT 60 NOT NULL,
    "max_future_bookings" integer DEFAULT 5 NOT NULL,
    "max_active_bookings_per_day" integer DEFAULT 1 NOT NULL,
    "booking_horizon_days" integer DEFAULT 7 NOT NULL,
    "timezone_identifier" "text" DEFAULT 'Australia/Perth'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "check_in_grace_minutes" integer DEFAULT 15 NOT NULL,
    "check_in_window_before_minutes" integer DEFAULT 15 NOT NULL,
    "check_in_code" "text" DEFAULT 'FENIX-WELLNESS-CENTRE'::"text" NOT NULL,
    CONSTRAINT "facility_rules_booking_horizon_days_check" CHECK (("booking_horizon_days" > 0)),
    CONSTRAINT "facility_rules_booking_interval_minutes_check" CHECK (("booking_interval_minutes" = 15)),
    CONSTRAINT "facility_rules_cancellation_cutoff_minutes_check" CHECK (("cancellation_cutoff_minutes" >= 0)),
    CONSTRAINT "facility_rules_capacity_check" CHECK (("capacity" > 0)),
    CONSTRAINT "facility_rules_id_check" CHECK ("id"),
    CONSTRAINT "facility_rules_max_active_bookings_per_day_check" CHECK (("max_active_bookings_per_day" > 0)),
    CONSTRAINT "facility_rules_max_future_bookings_check" CHECK (("max_future_bookings" > 0))
);

ALTER TABLE ONLY "public"."facility_rules" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."facility_rules" OWNER TO "postgres";

--
-- Name: opening_hours; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."opening_hours" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "weekday" integer NOT NULL,
    "opens_at" time without time zone NOT NULL,
    "closes_at" time without time zone NOT NULL,
    "is_closed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "opening_hours_check" CHECK (("is_closed" OR ("closes_at" > "opens_at"))),
    CONSTRAINT "opening_hours_weekday_check" CHECK ((("weekday" >= 0) AND ("weekday" <= 6)))
);

ALTER TABLE ONLY "public"."opening_hours" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."opening_hours" OWNER TO "postgres";

--
-- Name: profile_acknowledgements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."profile_acknowledgements" (
    "profile_id" "uuid" NOT NULL,
    "acknowledgement_id" "uuid" NOT NULL,
    "version" "text" NOT NULL,
    "accepted_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profile_acknowledgements" OWNER TO "postgres";

--
-- Name: program_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."program_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "resource_type" "text" DEFAULT 'link'::"text" NOT NULL,
    "url" "text",
    "storage_path" "text",
    "assigned_by" "uuid" DEFAULT "auth"."uid"(),
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "archived_at" timestamp with time zone,
    CONSTRAINT "program_assignments_source_check" CHECK (((("resource_type" = 'link'::"text") AND (NULLIF(TRIM(BOTH FROM COALESCE("url", ''::"text")), ''::"text") IS NOT NULL)) OR (("resource_type" = 'pdf'::"text") AND (NULLIF(TRIM(BOTH FROM COALESCE("storage_path", ''::"text")), ''::"text") IS NOT NULL)))),
    CONSTRAINT "program_assignments_type_check" CHECK (("resource_type" = ANY (ARRAY['link'::"text", 'pdf'::"text"])))
);


ALTER TABLE "public"."program_assignments" OWNER TO "postgres";

--
-- Name: wellbeing_challenges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."wellbeing_challenges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "challenge_type" "text" NOT NULL,
    "metric_name" "text" NOT NULL,
    "metric_unit" "text",
    "target_value" numeric,
    "starts_on" "date" NOT NULL,
    "ends_on" "date" NOT NULL,
    "rules" "text",
    "leaderboard_visible" boolean DEFAULT true NOT NULL,
    "is_published" boolean DEFAULT false NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wellbeing_challenges_dates_check" CHECK (("starts_on" <= "ends_on")),
    CONSTRAINT "wellbeing_challenges_target_check" CHECK ((("target_value" IS NULL) OR ("target_value" > (0)::numeric)))
);


ALTER TABLE "public"."wellbeing_challenges" OWNER TO "postgres";

--
-- Name: wellness_resources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."wellness_resources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "category" "text" DEFAULT 'General'::"text" NOT NULL,
    "resource_type" "text" DEFAULT 'link'::"text" NOT NULL,
    "url" "text",
    "storage_path" "text",
    "is_published" boolean DEFAULT false NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wellness_resources_source_check" CHECK (((("resource_type" = 'link'::"text") AND (NULLIF(TRIM(BOTH FROM COALESCE("url", ''::"text")), ''::"text") IS NOT NULL)) OR (("resource_type" = 'pdf'::"text") AND (NULLIF(TRIM(BOTH FROM COALESCE("storage_path", ''::"text")), ''::"text") IS NOT NULL)))),
    CONSTRAINT "wellness_resources_type_check" CHECK (("resource_type" = ANY (ARRAY['link'::"text", 'pdf'::"text"])))
);


ALTER TABLE "public"."wellness_resources" OWNER TO "postgres";

--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");


--
-- Name: blackout_periods blackout_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."blackout_periods"
    ADD CONSTRAINT "blackout_periods_pkey" PRIMARY KEY ("id");


--
-- Name: bookings bookings_no_active_overlap_per_user; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_no_active_overlap_per_user" EXCLUDE USING "gist" ("user_id" WITH =, "tstzrange"("start_time", "end_time", '[)'::"text") WITH &&) WHERE (("cancelled_at" IS NULL));


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");


--
-- Name: facility_contact facility_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."facility_contact"
    ADD CONSTRAINT "facility_contact_pkey" PRIMARY KEY ("id");


--
-- Name: facility_rules facility_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."facility_rules"
    ADD CONSTRAINT "facility_rules_pkey" PRIMARY KEY ("id");


--
-- Name: opening_hours opening_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."opening_hours"
    ADD CONSTRAINT "opening_hours_pkey" PRIMARY KEY ("id");


--
-- Name: opening_hours opening_hours_weekday_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."opening_hours"
    ADD CONSTRAINT "opening_hours_weekday_key" UNIQUE ("weekday");


--
-- Name: profile_acknowledgements profile_acknowledgements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profile_acknowledgements"
    ADD CONSTRAINT "profile_acknowledgements_pkey" PRIMARY KEY ("profile_id", "acknowledgement_id");


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");


--
-- Name: program_assignments program_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."program_assignments"
    ADD CONSTRAINT "program_assignments_pkey" PRIMARY KEY ("id");


--
-- Name: wellbeing_challenge_entries wellbeing_challenge_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_entries"
    ADD CONSTRAINT "wellbeing_challenge_entries_pkey" PRIMARY KEY ("id");


--
-- Name: wellbeing_challenge_participants wellbeing_challenge_participants_challenge_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_participants"
    ADD CONSTRAINT "wellbeing_challenge_participants_challenge_id_user_id_key" UNIQUE ("challenge_id", "user_id");


--
-- Name: wellbeing_challenge_participants wellbeing_challenge_participants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_participants"
    ADD CONSTRAINT "wellbeing_challenge_participants_pkey" PRIMARY KEY ("id");


--
-- Name: wellbeing_challenges wellbeing_challenges_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenges"
    ADD CONSTRAINT "wellbeing_challenges_pkey" PRIMARY KEY ("id");


--
-- Name: wellness_acknowledgements wellness_acknowledgements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellness_acknowledgements"
    ADD CONSTRAINT "wellness_acknowledgements_pkey" PRIMARY KEY ("id");


--
-- Name: wellness_acknowledgements wellness_acknowledgements_version_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellness_acknowledgements"
    ADD CONSTRAINT "wellness_acknowledgements_version_key" UNIQUE ("version");


--
-- Name: wellness_resources wellness_resources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellness_resources"
    ADD CONSTRAINT "wellness_resources_pkey" PRIMARY KEY ("id");


--
-- Name: blackout_periods_time_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "blackout_periods_time_idx" ON "public"."blackout_periods" USING "btree" ("starts_at", "ends_at");


--
-- Name: bookings_active_time_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "bookings_active_time_idx" ON "public"."bookings" USING "btree" ("start_time", "end_time") WHERE ("cancelled_at" IS NULL);


--
-- Name: bookings_user_start_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "bookings_user_start_idx" ON "public"."bookings" USING "btree" ("user_id", "start_time");


--
-- Name: idx_audit_log_actor_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_log_actor_id" ON "public"."audit_log" USING "btree" ("actor_id");


--
-- Name: idx_challenge_entries_challenge_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_challenge_entries_challenge_user" ON "public"."wellbeing_challenge_entries" USING "btree" ("challenge_id", "user_id");


--
-- Name: idx_challenge_entries_entry_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_challenge_entries_entry_date" ON "public"."wellbeing_challenge_entries" USING "btree" ("entry_date");


--
-- Name: idx_challenge_entries_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_challenge_entries_user_id" ON "public"."wellbeing_challenge_entries" USING "btree" ("user_id");


--
-- Name: idx_challenge_participants_challenge_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_challenge_participants_challenge_id" ON "public"."wellbeing_challenge_participants" USING "btree" ("challenge_id");


--
-- Name: idx_challenge_participants_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_challenge_participants_user_id" ON "public"."wellbeing_challenge_participants" USING "btree" ("user_id");


--
-- Name: idx_profiles_induction_completed_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_profiles_induction_completed_by" ON "public"."profiles" USING "btree" ("induction_completed_by");


--
-- Name: idx_program_assignments_assigned_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_program_assignments_assigned_by" ON "public"."program_assignments" USING "btree" ("assigned_by");


--
-- Name: idx_program_assignments_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_program_assignments_user_id" ON "public"."program_assignments" USING "btree" ("user_id");


--
-- Name: idx_wellbeing_challenges_created_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_wellbeing_challenges_created_by" ON "public"."wellbeing_challenges" USING "btree" ("created_by");


--
-- Name: idx_wellbeing_challenges_dates; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_wellbeing_challenges_dates" ON "public"."wellbeing_challenges" USING "btree" ("starts_on", "ends_on");


--
-- Name: idx_wellness_resources_created_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_wellness_resources_created_by" ON "public"."wellness_resources" USING "btree" ("created_by");


--
-- Name: wellness_acknowledgements_one_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "wellness_acknowledgements_one_active_idx" ON "public"."wellness_acknowledgements" USING "btree" ("is_active") WHERE "is_active";


--
-- Name: profiles audit_profile_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "audit_profile_update" AFTER UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "app_private"."audit_profile_update"();


--
-- Name: profiles prevent_member_profile_escalation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "prevent_member_profile_escalation" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "app_private"."prevent_member_profile_escalation"();


--
-- Name: wellness_acknowledgements touch_wellness_acknowledgements_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "touch_wellness_acknowledgements_updated_at" BEFORE UPDATE ON "public"."wellness_acknowledgements" FOR EACH ROW EXECUTE FUNCTION "app_private"."touch_updated_at"();


--
-- Name: wellbeing_challenge_entries wellbeing_challenge_entries_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "wellbeing_challenge_entries_touch_updated_at" BEFORE UPDATE ON "public"."wellbeing_challenge_entries" FOR EACH ROW EXECUTE FUNCTION "app_private"."touch_updated_at"();


--
-- Name: wellbeing_challenges wellbeing_challenges_audit; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "wellbeing_challenges_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."wellbeing_challenges" FOR EACH ROW EXECUTE FUNCTION "app_private"."audit_wellbeing_challenge_change"();


--
-- Name: wellbeing_challenges wellbeing_challenges_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "wellbeing_challenges_touch_updated_at" BEFORE UPDATE ON "public"."wellbeing_challenges" FOR EACH ROW EXECUTE FUNCTION "app_private"."touch_updated_at"();


--
-- Name: audit_log audit_log_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id");


--
-- Name: bookings bookings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;


--
-- Name: profile_acknowledgements profile_acknowledgements_acknowledgement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profile_acknowledgements"
    ADD CONSTRAINT "profile_acknowledgements_acknowledgement_id_fkey" FOREIGN KEY ("acknowledgement_id") REFERENCES "public"."wellness_acknowledgements"("id");


--
-- Name: profile_acknowledgements profile_acknowledgements_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profile_acknowledgements"
    ADD CONSTRAINT "profile_acknowledgements_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: profiles profiles_induction_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_induction_completed_by_fkey" FOREIGN KEY ("induction_completed_by") REFERENCES "public"."profiles"("id");


--
-- Name: program_assignments program_assignments_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."program_assignments"
    ADD CONSTRAINT "program_assignments_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."profiles"("id");


--
-- Name: program_assignments program_assignments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."program_assignments"
    ADD CONSTRAINT "program_assignments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;


--
-- Name: wellbeing_challenge_entries wellbeing_challenge_entries_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_entries"
    ADD CONSTRAINT "wellbeing_challenge_entries_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "public"."wellbeing_challenges"("id") ON DELETE CASCADE;


--
-- Name: wellbeing_challenge_entries wellbeing_challenge_entries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_entries"
    ADD CONSTRAINT "wellbeing_challenge_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;


--
-- Name: wellbeing_challenge_participants wellbeing_challenge_participants_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_participants"
    ADD CONSTRAINT "wellbeing_challenge_participants_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "public"."wellbeing_challenges"("id") ON DELETE CASCADE;


--
-- Name: wellbeing_challenge_participants wellbeing_challenge_participants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenge_participants"
    ADD CONSTRAINT "wellbeing_challenge_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;


--
-- Name: wellbeing_challenges wellbeing_challenges_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellbeing_challenges"
    ADD CONSTRAINT "wellbeing_challenges_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");


--
-- Name: wellness_acknowledgements wellness_acknowledgements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellness_acknowledgements"
    ADD CONSTRAINT "wellness_acknowledgements_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");


--
-- Name: wellness_resources wellness_resources_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."wellness_resources"
    ADD CONSTRAINT "wellness_resources_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_log_admin_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "audit_log_admin_select" ON "public"."audit_log" FOR SELECT TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: blackout_periods; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."blackout_periods" ENABLE ROW LEVEL SECURITY;

--
-- Name: blackout_periods blackout_periods_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "blackout_periods_admin_delete" ON "public"."blackout_periods" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: blackout_periods blackout_periods_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "blackout_periods_admin_insert" ON "public"."blackout_periods" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: blackout_periods blackout_periods_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "blackout_periods_admin_update" ON "public"."blackout_periods" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: blackout_periods blackout_periods_select_authenticated; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "blackout_periods_select_authenticated" ON "public"."blackout_periods" FOR SELECT TO "authenticated" USING (true);


--
-- Name: bookings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;

--
-- Name: bookings bookings_delete_admin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "bookings_delete_admin" ON "public"."bookings" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: bookings bookings_insert_validated_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "bookings_insert_validated_own" ON "public"."bookings" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("app_private"."booking_failure_reason"("user_id", "start_time", "end_time") IS NULL)));


--
-- Name: bookings bookings_select_own_or_admin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "bookings_select_own_or_admin" ON "public"."bookings" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: bookings bookings_update_cancel_own_or_admin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "bookings_update_cancel_own_or_admin" ON "public"."bookings" FOR UPDATE TO "authenticated" USING ((( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin") OR (("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("cancelled_at" IS NULL) AND ("start_time" > ("now"() + "make_interval"("mins" => ( SELECT "facility_rules"."cancellation_cutoff_minutes"
   FROM "public"."facility_rules"
  WHERE ("facility_rules"."id" = true)))))))) WITH CHECK ((( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin") OR ("user_id" = ( SELECT "auth"."uid"() AS "uid"))));


--
-- Name: wellbeing_challenge_entries challenge_entries_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "challenge_entries_admin_delete" ON "public"."wellbeing_challenge_entries" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellbeing_challenge_entries challenge_entries_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "challenge_entries_insert" ON "public"."wellbeing_challenge_entries" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "app_private"."current_user_is_active_member"() AS "current_user_is_active_member")));


--
-- Name: wellbeing_challenge_entries challenge_entries_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "challenge_entries_select" ON "public"."wellbeing_challenge_entries" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin") OR (EXISTS ( SELECT 1
   FROM "public"."wellbeing_challenges" "wc"
  WHERE (("wc"."id" = "wellbeing_challenge_entries"."challenge_id") AND "wc"."is_published" AND "wc"."leaderboard_visible" AND ( SELECT "app_private"."current_user_is_active_member"() AS "current_user_is_active_member"))))));


--
-- Name: wellbeing_challenge_entries challenge_entries_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "challenge_entries_update_own" ON "public"."wellbeing_challenge_entries" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));


--
-- Name: wellbeing_challenge_participants challenge_participants_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "challenge_participants_insert" ON "public"."wellbeing_challenge_participants" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "app_private"."current_user_is_active_member"() AS "current_user_is_active_member")));


--
-- Name: wellbeing_challenge_participants challenge_participants_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "challenge_participants_select" ON "public"."wellbeing_challenge_participants" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: facility_contact; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."facility_contact" ENABLE ROW LEVEL SECURITY;

--
-- Name: facility_contact facility_contact_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_contact_admin_delete" ON "public"."facility_contact" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: facility_contact facility_contact_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_contact_admin_insert" ON "public"."facility_contact" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: facility_contact facility_contact_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_contact_admin_update" ON "public"."facility_contact" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: facility_contact facility_contact_select_authenticated; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_contact_select_authenticated" ON "public"."facility_contact" FOR SELECT TO "authenticated" USING (true);


--
-- Name: facility_rules; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."facility_rules" ENABLE ROW LEVEL SECURITY;

--
-- Name: facility_rules facility_rules_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_rules_admin_delete" ON "public"."facility_rules" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: facility_rules facility_rules_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_rules_admin_insert" ON "public"."facility_rules" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: facility_rules facility_rules_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_rules_admin_update" ON "public"."facility_rules" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: facility_rules facility_rules_select_authenticated; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "facility_rules_select_authenticated" ON "public"."facility_rules" FOR SELECT TO "authenticated" USING (true);


--
-- Name: opening_hours; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."opening_hours" ENABLE ROW LEVEL SECURITY;

--
-- Name: opening_hours opening_hours_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "opening_hours_admin_delete" ON "public"."opening_hours" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: opening_hours opening_hours_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "opening_hours_admin_insert" ON "public"."opening_hours" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: opening_hours opening_hours_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "opening_hours_admin_update" ON "public"."opening_hours" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: opening_hours opening_hours_select_authenticated; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "opening_hours_select_authenticated" ON "public"."opening_hours" FOR SELECT TO "authenticated" USING (true);


--
-- Name: profile_acknowledgements; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."profile_acknowledgements" ENABLE ROW LEVEL SECURITY;

--
-- Name: profile_acknowledgements profile_acknowledgements_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profile_acknowledgements_insert_own" ON "public"."profile_acknowledgements" FOR INSERT WITH CHECK ((("profile_id" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."wellness_acknowledgements" "acknowledgement"
  WHERE (("acknowledgement"."id" = "profile_acknowledgements"."acknowledgement_id") AND ("acknowledgement"."version" = "profile_acknowledgements"."version") AND "acknowledgement"."is_active")))));


--
-- Name: profile_acknowledgements profile_acknowledgements_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profile_acknowledgements_select" ON "public"."profile_acknowledgements" FOR SELECT USING ((("profile_id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profiles_admin_delete" ON "public"."profiles" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: profiles profiles_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profiles_admin_insert" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: profiles profiles_select_own_or_admin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profiles_select_own_or_admin" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: profiles profiles_update_admin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profiles_update_admin" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: profiles profiles_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("id" = ( SELECT "auth"."uid"() AS "uid")));


--
-- Name: program_assignments; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."program_assignments" ENABLE ROW LEVEL SECURITY;

--
-- Name: program_assignments program_assignments_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "program_assignments_admin_delete" ON "public"."program_assignments" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: program_assignments program_assignments_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "program_assignments_admin_insert" ON "public"."program_assignments" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: program_assignments program_assignments_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "program_assignments_admin_update" ON "public"."program_assignments" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: program_assignments program_assignments_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "program_assignments_select" ON "public"."program_assignments" FOR SELECT TO "authenticated" USING (((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "app_private"."current_user_is_active_member"() AS "current_user_is_active_member")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: wellbeing_challenge_entries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."wellbeing_challenge_entries" ENABLE ROW LEVEL SECURITY;

--
-- Name: wellbeing_challenge_participants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."wellbeing_challenge_participants" ENABLE ROW LEVEL SECURITY;

--
-- Name: wellbeing_challenges; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."wellbeing_challenges" ENABLE ROW LEVEL SECURITY;

--
-- Name: wellbeing_challenges wellbeing_challenges_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellbeing_challenges_admin_delete" ON "public"."wellbeing_challenges" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellbeing_challenges wellbeing_challenges_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellbeing_challenges_admin_insert" ON "public"."wellbeing_challenges" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellbeing_challenges wellbeing_challenges_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellbeing_challenges_admin_update" ON "public"."wellbeing_challenges" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellbeing_challenges wellbeing_challenges_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellbeing_challenges_select" ON "public"."wellbeing_challenges" FOR SELECT TO "authenticated" USING ((("is_published" AND ( SELECT "app_private"."current_user_is_active_member"() AS "current_user_is_active_member")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: wellness_acknowledgements; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."wellness_acknowledgements" ENABLE ROW LEVEL SECURITY;

--
-- Name: wellness_acknowledgements wellness_acknowledgements_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_acknowledgements_admin_insert" ON "public"."wellness_acknowledgements" FOR INSERT WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellness_acknowledgements wellness_acknowledgements_admin_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_acknowledgements_admin_select" ON "public"."wellness_acknowledgements" FOR SELECT TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellness_acknowledgements wellness_acknowledgements_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_acknowledgements_admin_update" ON "public"."wellness_acknowledgements" FOR UPDATE USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellness_acknowledgements wellness_acknowledgements_public_active_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_acknowledgements_public_active_select" ON "public"."wellness_acknowledgements" FOR SELECT USING ("is_active");


--
-- Name: wellness_resources; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."wellness_resources" ENABLE ROW LEVEL SECURITY;

--
-- Name: wellness_resources wellness_resources_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_resources_admin_delete" ON "public"."wellness_resources" FOR DELETE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellness_resources wellness_resources_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_resources_admin_insert" ON "public"."wellness_resources" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellness_resources wellness_resources_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_resources_admin_update" ON "public"."wellness_resources" FOR UPDATE TO "authenticated" USING (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")) WITH CHECK (( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin"));


--
-- Name: wellness_resources wellness_resources_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "wellness_resources_select" ON "public"."wellness_resources" FOR SELECT TO "authenticated" USING ((("is_published" AND ( SELECT "app_private"."current_user_is_active_member"() AS "current_user_is_active_member")) OR ( SELECT "app_private"."current_user_is_admin"() AS "current_user_is_admin")));


--
-- Name: SCHEMA "app_private"; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA "app_private" TO "authenticated";
GRANT USAGE ON SCHEMA "app_private" TO "service_role";


--
-- Name: SCHEMA "public"; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";


--
-- Name: FUNCTION "booking_failure_reason"("p_user_id" "uuid", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone); Type: ACL; Schema: app_private; Owner: postgres
--

REVOKE ALL ON FUNCTION "app_private"."booking_failure_reason"("p_user_id" "uuid", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."booking_failure_reason"("p_user_id" "uuid", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."booking_failure_reason"("p_user_id" "uuid", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) TO "service_role";


--
-- Name: FUNCTION "current_user_is_admin"(); Type: ACL; Schema: app_private; Owner: postgres
--

REVOKE ALL ON FUNCTION "app_private"."current_user_is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."current_user_is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."current_user_is_admin"() TO "service_role";


--
-- Name: FUNCTION "get_availability_for_date"("p_date" "date", "p_duration_minutes" integer); Type: ACL; Schema: app_private; Owner: postgres
--

REVOKE ALL ON FUNCTION "app_private"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) TO "service_role";


--
-- Name: FUNCTION "handle_new_user_profile"(); Type: ACL; Schema: app_private; Owner: postgres
--

REVOKE ALL ON FUNCTION "app_private"."handle_new_user_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."handle_new_user_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."handle_new_user_profile"() TO "service_role";


--
-- Name: FUNCTION "is_approved_staff_email"("email" "text"); Type: ACL; Schema: app_private; Owner: postgres
--

REVOKE ALL ON FUNCTION "app_private"."is_approved_staff_email"("email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."is_approved_staff_email"("email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."is_approved_staff_email"("email" "text") TO "service_role";


--
-- Name: TABLE "wellbeing_challenge_entries"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."wellbeing_challenge_entries" TO "anon";
GRANT ALL ON TABLE "public"."wellbeing_challenge_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."wellbeing_challenge_entries" TO "service_role";


--
-- Name: FUNCTION "add_wellbeing_challenge_entry"("p_challenge_id" "uuid", "p_value" numeric, "p_note" "text", "p_entry_date" "date"); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION "public"."add_wellbeing_challenge_entry"("p_challenge_id" "uuid", "p_value" numeric, "p_note" "text", "p_entry_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."add_wellbeing_challenge_entry"("p_challenge_id" "uuid", "p_value" numeric, "p_note" "text", "p_entry_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_wellbeing_challenge_entry"("p_challenge_id" "uuid", "p_value" numeric, "p_note" "text", "p_entry_date" "date") TO "service_role";


--
-- Name: FUNCTION "admin_bookings_export"("p_start_date" "date", "p_end_date" "date"); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."admin_bookings_export"("p_start_date" "date", "p_end_date" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_bookings_export"("p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_bookings_export"("p_start_date" "date", "p_end_date" "date") TO "service_role";


--
-- Name: FUNCTION "admin_report_summary"("p_start_date" "date", "p_end_date" "date"); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."admin_report_summary"("p_start_date" "date", "p_end_date" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_report_summary"("p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_report_summary"("p_start_date" "date", "p_end_date" "date") TO "service_role";


--
-- Name: TABLE "bookings"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."bookings" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."bookings" TO "authenticated";


--
-- Name: COLUMN "bookings"."cancelled_at"; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE("cancelled_at") ON TABLE "public"."bookings" TO "authenticated";


--
-- Name: FUNCTION "cancel_booking"("p_booking_id" "uuid"); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "authenticated";


--
-- Name: FUNCTION "check_in_booking"("p_code" "text"); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."check_in_booking"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_in_booking"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_in_booking"("p_code" "text") TO "service_role";


--
-- Name: FUNCTION "check_out_booking"("p_booking_id" "uuid"); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION "public"."check_out_booking"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_out_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_out_booking"("p_booking_id" "uuid") TO "service_role";


--
-- Name: FUNCTION "create_booking"("p_start_time" timestamp with time zone, "p_duration_minutes" integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."create_booking"("p_start_time" timestamp with time zone, "p_duration_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_booking"("p_start_time" timestamp with time zone, "p_duration_minutes" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."create_booking"("p_start_time" timestamp with time zone, "p_duration_minutes" integer) TO "authenticated";


--
-- Name: FUNCTION "get_availability_for_date"("p_date" "date", "p_duration_minutes" integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_availability_for_date"("p_date" "date", "p_duration_minutes" integer) TO "authenticated";


--
-- Name: TABLE "wellbeing_challenge_participants"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."wellbeing_challenge_participants" TO "anon";
GRANT ALL ON TABLE "public"."wellbeing_challenge_participants" TO "authenticated";
GRANT ALL ON TABLE "public"."wellbeing_challenge_participants" TO "service_role";


--
-- Name: FUNCTION "join_wellbeing_challenge"("p_challenge_id" "uuid"); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION "public"."join_wellbeing_challenge"("p_challenge_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."join_wellbeing_challenge"("p_challenge_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_wellbeing_challenge"("p_challenge_id" "uuid") TO "service_role";


--
-- Name: FUNCTION "mark_due_no_shows"(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."mark_due_no_shows"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_due_no_shows"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_due_no_shows"() TO "service_role";


--
-- Name: TABLE "wellness_acknowledgements"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."wellness_acknowledgements" TO "anon";
GRANT ALL ON TABLE "public"."wellness_acknowledgements" TO "authenticated";
GRANT ALL ON TABLE "public"."wellness_acknowledgements" TO "service_role";


--
-- Name: FUNCTION "publish_wellness_acknowledgement"("p_title" "text", "p_body" "text", "p_capacity_text" "text", "p_fair_use_text" "text", "p_medical_text" "text"); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."publish_wellness_acknowledgement"("p_title" "text", "p_body" "text", "p_capacity_text" "text", "p_fair_use_text" "text", "p_medical_text" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_wellness_acknowledgement"("p_title" "text", "p_body" "text", "p_capacity_text" "text", "p_fair_use_text" "text", "p_medical_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."publish_wellness_acknowledgement"("p_title" "text", "p_body" "text", "p_capacity_text" "text", "p_fair_use_text" "text", "p_medical_text" "text") TO "service_role";


--
-- Name: FUNCTION "rls_auto_enable"(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";


--
-- Name: TABLE "profiles"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."profiles" TO "service_role";
GRANT SELECT,UPDATE ON TABLE "public"."profiles" TO "authenticated";


--
-- Name: COLUMN "profiles"."full_name"; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE("full_name") ON TABLE "public"."profiles" TO "authenticated";


--
-- Name: COLUMN "profiles"."email"; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE("email") ON TABLE "public"."profiles" TO "authenticated";


--
-- Name: COLUMN "profiles"."phone"; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE("phone") ON TABLE "public"."profiles" TO "authenticated";


--
-- Name: FUNCTION "update_member_access"("p_user_id" "uuid", "p_access_status" "text", "p_induction_complete" boolean); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."update_member_access"("p_user_id" "uuid", "p_access_status" "text", "p_induction_complete" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_member_access"("p_user_id" "uuid", "p_access_status" "text", "p_induction_complete" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_member_access"("p_user_id" "uuid", "p_access_status" "text", "p_induction_complete" boolean) TO "service_role";


--
-- Name: FUNCTION "wellbeing_challenge_leaderboard"("p_challenge_id" "uuid"); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION "public"."wellbeing_challenge_leaderboard"("p_challenge_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."wellbeing_challenge_leaderboard"("p_challenge_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."wellbeing_challenge_leaderboard"("p_challenge_id" "uuid") TO "service_role";


--
-- Name: TABLE "audit_log"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_log" TO "service_role";


--
-- Name: SEQUENCE "audit_log_id_seq"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE "public"."audit_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."audit_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."audit_log_id_seq" TO "service_role";


--
-- Name: TABLE "blackout_periods"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."blackout_periods" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."blackout_periods" TO "authenticated";


--
-- Name: TABLE "facility_contact"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."facility_contact" TO "anon";
GRANT ALL ON TABLE "public"."facility_contact" TO "authenticated";
GRANT ALL ON TABLE "public"."facility_contact" TO "service_role";


--
-- Name: TABLE "facility_rules"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."facility_rules" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."facility_rules" TO "authenticated";


--
-- Name: TABLE "opening_hours"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."opening_hours" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."opening_hours" TO "authenticated";


--
-- Name: TABLE "profile_acknowledgements"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."profile_acknowledgements" TO "anon";
GRANT ALL ON TABLE "public"."profile_acknowledgements" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_acknowledgements" TO "service_role";


--
-- Name: TABLE "program_assignments"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."program_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."program_assignments" TO "service_role";


--
-- Name: TABLE "wellbeing_challenges"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."wellbeing_challenges" TO "anon";
GRANT ALL ON TABLE "public"."wellbeing_challenges" TO "authenticated";
GRANT ALL ON TABLE "public"."wellbeing_challenges" TO "service_role";


--
-- Name: TABLE "wellness_resources"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."wellness_resources" TO "anon";
GRANT ALL ON TABLE "public"."wellness_resources" TO "authenticated";
GRANT ALL ON TABLE "public"."wellness_resources" TO "service_role";


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";


--
-- PostgreSQL database dump complete
--

-- -----------------------------------------------------------------------------
-- Fenix Wellbeing Facility bootstrap data and Supabase platform glue
-- -----------------------------------------------------------------------------

-- Keep new Auth sign-ups in sync with public.profiles.
DROP TRIGGER IF EXISTS "on_auth_user_created" ON "auth"."users";
CREATE TRIGGER "on_auth_user_created"
AFTER INSERT ON "auth"."users"
FOR EACH ROW EXECUTE FUNCTION "app_private"."handle_new_user_profile"();

-- Private PDF storage for shared resources and personal programs.
INSERT INTO "storage"."buckets" ("id", "name", "public", "file_size_limit", "allowed_mime_types")
VALUES ('wellness-resources', 'wellness-resources', false, 10485760, ARRAY['application/pdf'])
ON CONFLICT ("id") DO UPDATE SET
    "public" = EXCLUDED."public",
    "file_size_limit" = EXCLUDED."file_size_limit",
    "allowed_mime_types" = EXCLUDED."allowed_mime_types";

DROP POLICY IF EXISTS "storage_wellness_select" ON "storage"."objects";
DROP POLICY IF EXISTS "storage_wellness_admin_write" ON "storage"."objects";
DROP POLICY IF EXISTS "storage_wellness_admin_insert" ON "storage"."objects";
DROP POLICY IF EXISTS "storage_wellness_admin_update" ON "storage"."objects";
DROP POLICY IF EXISTS "storage_wellness_admin_delete" ON "storage"."objects";

CREATE POLICY "storage_wellness_select" ON "storage"."objects"
FOR SELECT TO "authenticated"
USING (
    "bucket_id" = 'wellness-resources'
    AND (
        (SELECT "app_private"."current_user_is_admin"())
        OR EXISTS (
            SELECT 1
            FROM "public"."wellness_resources" "wr"
            WHERE "wr"."storage_path" = "name"
              AND "wr"."is_published"
              AND (SELECT "app_private"."current_user_is_active_member"())
        )
        OR EXISTS (
            SELECT 1
            FROM "public"."program_assignments" "pa"
            WHERE "pa"."storage_path" = "name"
              AND "pa"."user_id" = (SELECT "auth"."uid"())
              AND "pa"."archived_at" IS NULL
              AND (SELECT "app_private"."current_user_is_active_member"())
        )
    )
);

CREATE POLICY "storage_wellness_admin_insert" ON "storage"."objects"
FOR INSERT TO "authenticated"
WITH CHECK ("bucket_id" = 'wellness-resources' AND (SELECT "app_private"."current_user_is_admin"()));

CREATE POLICY "storage_wellness_admin_update" ON "storage"."objects"
FOR UPDATE TO "authenticated"
USING ("bucket_id" = 'wellness-resources' AND (SELECT "app_private"."current_user_is_admin"()))
WITH CHECK ("bucket_id" = 'wellness-resources' AND (SELECT "app_private"."current_user_is_admin"()));

CREATE POLICY "storage_wellness_admin_delete" ON "storage"."objects"
FOR DELETE TO "authenticated"
USING ("bucket_id" = 'wellness-resources' AND (SELECT "app_private"."current_user_is_admin"()));

-- Starter booking rules. Admins can change these inside the app.
INSERT INTO "public"."facility_rules" (
    "id",
    "capacity",
    "booking_interval_minutes",
    "allowed_durations_minutes",
    "cancellation_cutoff_minutes",
    "max_future_bookings",
    "max_active_bookings_per_day",
    "booking_horizon_days",
    "timezone_identifier",
    "check_in_grace_minutes",
    "check_in_window_before_minutes",
    "check_in_code"
)
VALUES (
    true,
    20,
    15,
    ARRAY[15, 30, 45],
    60,
    5,
    1,
    7,
    'Australia/Perth',
    15,
    10,
    'FENIX-WELLBEING-FACILITY'
)
ON CONFLICT ("id") DO UPDATE SET
    "capacity" = EXCLUDED."capacity",
    "booking_interval_minutes" = EXCLUDED."booking_interval_minutes",
    "allowed_durations_minutes" = EXCLUDED."allowed_durations_minutes",
    "cancellation_cutoff_minutes" = EXCLUDED."cancellation_cutoff_minutes",
    "max_future_bookings" = EXCLUDED."max_future_bookings",
    "max_active_bookings_per_day" = EXCLUDED."max_active_bookings_per_day",
    "booking_horizon_days" = EXCLUDED."booking_horizon_days",
    "timezone_identifier" = EXCLUDED."timezone_identifier",
    "check_in_grace_minutes" = EXCLUDED."check_in_grace_minutes",
    "check_in_window_before_minutes" = EXCLUDED."check_in_window_before_minutes",
    "check_in_code" = EXCLUDED."check_in_code";

-- Default opening hours: 07:00 to 19:00 every day. Admins can change these in-app.
INSERT INTO "public"."opening_hours" ("weekday", "opens_at", "closes_at", "is_closed")
VALUES
    (0, '07:00', '19:00', false),
    (1, '07:00', '19:00', false),
    (2, '07:00', '19:00', false),
    (3, '07:00', '19:00', false),
    (4, '07:00', '19:00', false),
    (5, '07:00', '19:00', false),
    (6, '07:00', '19:00', false)
ON CONFLICT ("weekday") DO UPDATE SET
    "opens_at" = EXCLUDED."opens_at",
    "closes_at" = EXCLUDED."closes_at",
    "is_closed" = EXCLUDED."is_closed";

INSERT INTO "public"."facility_contact" (
    "id",
    "display_name",
    "address",
    "phone",
    "email",
    "notes"
)
VALUES (
    true,
    'Fenix Wellbeing Facility',
    '',
    '',
    '',
    'Contact your Fenix admin or HR team for wellbeing facility support.'
)
ON CONFLICT ("id") DO UPDATE SET
    "display_name" = EXCLUDED."display_name",
    "address" = EXCLUDED."address",
    "phone" = EXCLUDED."phone",
    "email" = EXCLUDED."email",
    "notes" = EXCLUDED."notes";

INSERT INTO "public"."wellness_acknowledgements" (
    "id",
    "version",
    "title",
    "body",
    "capacity_text",
    "fair_use_text",
    "medical_text",
    "is_active",
    "published_at",
    "created_at",
    "updated_at"
)
VALUES (
    'ac0bbc7e-402c-4d8e-a4e3-57c6fa6101a1',
    '2026-06-06-v1',
    'Wellbeing Facility Acknowledgement',
    'Please read and acknowledge this before using the wellbeing facility. Use of the facility is voluntary and at your own risk.',
    'The wellbeing facility is limited to 20 people at a time.',
    'To keep access fair, each staff member can book one session per day, up to 7 days in advance.',
    'If you have a medical condition, injury, or any concern about exercise, seek medical advice before using the facility.',
    true,
    NOW(),
    NOW(),
    NOW()
)
ON CONFLICT ("version") DO UPDATE SET
    "title" = EXCLUDED."title",
    "body" = EXCLUDED."body",
    "capacity_text" = EXCLUDED."capacity_text",
    "fair_use_text" = EXCLUDED."fair_use_text",
    "medical_text" = EXCLUDED."medical_text",
    "is_active" = EXCLUDED."is_active",
    "published_at" = COALESCE("public"."wellness_acknowledgements"."published_at", NOW()),
    "updated_at" = NOW();
