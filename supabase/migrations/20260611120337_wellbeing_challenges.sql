update public.facility_rules
set check_in_window_before_minutes = 10
where id = true;

create table if not exists public.wellbeing_challenges (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    description text,
    challenge_type text not null,
    metric_name text not null,
    metric_unit text,
    target_value numeric,
    starts_on date not null,
    ends_on date not null,
    rules text,
    leaderboard_visible boolean not null default true,
    is_published boolean not null default false,
    created_by uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint wellbeing_challenges_dates_check check (starts_on <= ends_on),
    constraint wellbeing_challenges_target_check check (target_value is null or target_value > 0)
);

create table if not exists public.wellbeing_challenge_participants (
    id uuid primary key default gen_random_uuid(),
    challenge_id uuid not null references public.wellbeing_challenges(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    joined_at timestamptz not null default now(),
    unique (challenge_id, user_id)
);

create table if not exists public.wellbeing_challenge_entries (
    id uuid primary key default gen_random_uuid(),
    challenge_id uuid not null references public.wellbeing_challenges(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    value numeric not null check (value > 0),
    note text,
    entry_date date not null default ((now() at time zone 'Australia/Perth')::date),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_wellbeing_challenges_dates on public.wellbeing_challenges(starts_on, ends_on);
create index if not exists idx_wellbeing_challenges_created_by on public.wellbeing_challenges(created_by);
create index if not exists idx_challenge_participants_challenge_id on public.wellbeing_challenge_participants(challenge_id);
create index if not exists idx_challenge_participants_user_id on public.wellbeing_challenge_participants(user_id);
create index if not exists idx_challenge_entries_challenge_user on public.wellbeing_challenge_entries(challenge_id, user_id);
create index if not exists idx_challenge_entries_entry_date on public.wellbeing_challenge_entries(entry_date);

alter table public.wellbeing_challenges enable row level security;
alter table public.wellbeing_challenge_participants enable row level security;
alter table public.wellbeing_challenge_entries enable row level security;

create or replace function app_private.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, app_private
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists wellbeing_challenges_touch_updated_at on public.wellbeing_challenges;
create trigger wellbeing_challenges_touch_updated_at
before update on public.wellbeing_challenges
for each row execute function app_private.touch_updated_at();

drop trigger if exists wellbeing_challenge_entries_touch_updated_at on public.wellbeing_challenge_entries;
create trigger wellbeing_challenge_entries_touch_updated_at
before update on public.wellbeing_challenge_entries
for each row execute function app_private.touch_updated_at();

create or replace function app_private.audit_wellbeing_challenge_change()
returns trigger
language plpgsql
set search_path = public, app_private
as $$
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

drop trigger if exists wellbeing_challenges_audit on public.wellbeing_challenges;
create trigger wellbeing_challenges_audit
after insert or update or delete on public.wellbeing_challenges
for each row execute function app_private.audit_wellbeing_challenge_change();

drop policy if exists wellbeing_challenges_select on public.wellbeing_challenges;
create policy wellbeing_challenges_select on public.wellbeing_challenges
for select to authenticated
using ((is_published and (select app_private.current_user_is_active_member())) or (select app_private.current_user_is_admin()));

drop policy if exists wellbeing_challenges_admin_insert on public.wellbeing_challenges;
create policy wellbeing_challenges_admin_insert on public.wellbeing_challenges
for insert to authenticated
with check ((select app_private.current_user_is_admin()));

drop policy if exists wellbeing_challenges_admin_update on public.wellbeing_challenges;
create policy wellbeing_challenges_admin_update on public.wellbeing_challenges
for update to authenticated
using ((select app_private.current_user_is_admin()))
with check ((select app_private.current_user_is_admin()));

drop policy if exists wellbeing_challenges_admin_delete on public.wellbeing_challenges;
create policy wellbeing_challenges_admin_delete on public.wellbeing_challenges
for delete to authenticated
using ((select app_private.current_user_is_admin()));

drop policy if exists challenge_participants_select on public.wellbeing_challenge_participants;
create policy challenge_participants_select on public.wellbeing_challenge_participants
for select to authenticated
using (user_id = (select auth.uid()) or (select app_private.current_user_is_admin()));

drop policy if exists challenge_participants_insert on public.wellbeing_challenge_participants;
create policy challenge_participants_insert on public.wellbeing_challenge_participants
for insert to authenticated
with check (user_id = (select auth.uid()) and (select app_private.current_user_is_active_member()));

drop policy if exists challenge_entries_select on public.wellbeing_challenge_entries;
create policy challenge_entries_select on public.wellbeing_challenge_entries
for select to authenticated
using (
    user_id = (select auth.uid())
    or (select app_private.current_user_is_admin())
    or exists (
        select 1
        from public.wellbeing_challenges wc
        where wc.id = challenge_id
          and wc.is_published
          and wc.leaderboard_visible
          and (select app_private.current_user_is_active_member())
    )
);

drop policy if exists challenge_entries_insert on public.wellbeing_challenge_entries;
create policy challenge_entries_insert on public.wellbeing_challenge_entries
for insert to authenticated
with check (user_id = (select auth.uid()) and (select app_private.current_user_is_active_member()));

drop policy if exists challenge_entries_update_own on public.wellbeing_challenge_entries;
create policy challenge_entries_update_own on public.wellbeing_challenge_entries
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists challenge_entries_admin_delete on public.wellbeing_challenge_entries;
create policy challenge_entries_admin_delete on public.wellbeing_challenge_entries
for delete to authenticated
using ((select app_private.current_user_is_admin()));

create or replace function public.join_wellbeing_challenge(p_challenge_id uuid)
returns public.wellbeing_challenge_participants
language plpgsql
set search_path = public, app_private
as $$
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

create or replace function public.add_wellbeing_challenge_entry(
    p_challenge_id uuid,
    p_value numeric,
    p_note text,
    p_entry_date date
)
returns public.wellbeing_challenge_entries
language plpgsql
set search_path = public, app_private
as $$
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

create or replace function public.wellbeing_challenge_leaderboard(p_challenge_id uuid)
returns table (
    user_id uuid,
    member_name text,
    total_value numeric,
    entry_count integer,
    rank integer
)
language plpgsql
stable
set search_path = public, app_private
as $$
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

grant select, insert, update, delete on public.wellbeing_challenges to authenticated;
grant select, insert, update, delete on public.wellbeing_challenge_participants to authenticated;
grant select, insert, update, delete on public.wellbeing_challenge_entries to authenticated;
grant execute on function public.join_wellbeing_challenge(uuid) to authenticated;
grant execute on function public.add_wellbeing_challenge_entry(uuid, numeric, text, date) to authenticated;
grant execute on function public.wellbeing_challenge_leaderboard(uuid) to authenticated;
