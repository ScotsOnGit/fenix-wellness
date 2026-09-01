-- Versioned acknowledgement wording for the wellbeing facility.
-- Admins can publish new versions; members accept the active version once per version.

create table if not exists public.wellness_acknowledgements (
    id uuid primary key default gen_random_uuid(),
    version text not null unique,
    title text not null,
    body text not null,
    capacity_text text not null default '',
    fair_use_text text not null default '',
    medical_text text not null default '',
    is_active boolean not null default false,
    published_at timestamptz,
    created_by uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint wellness_acknowledgements_required_copy_check check (
        nullif(trim(title), '') is not null
        and nullif(trim(body), '') is not null
        and nullif(trim(fair_use_text), '') is not null
        and nullif(trim(medical_text), '') is not null
    )
);

create unique index if not exists wellness_acknowledgements_one_active_idx
on public.wellness_acknowledgements (is_active)
where is_active;

create table if not exists public.profile_acknowledgements (
    profile_id uuid not null references public.profiles(id) on delete cascade,
    acknowledgement_id uuid not null references public.wellness_acknowledgements(id),
    version text not null,
    accepted_at timestamptz not null default now(),
    primary key (profile_id, acknowledgement_id)
);

alter table public.wellness_acknowledgements
    alter column created_by set default auth.uid();

alter table public.wellness_acknowledgements enable row level security;
alter table public.profile_acknowledgements enable row level security;

drop policy if exists wellness_acknowledgements_select on public.wellness_acknowledgements;
create policy wellness_acknowledgements_select
on public.wellness_acknowledgements
for select
using (is_active or (select app_private.current_user_is_admin()));

drop policy if exists wellness_acknowledgements_admin_insert on public.wellness_acknowledgements;
create policy wellness_acknowledgements_admin_insert
on public.wellness_acknowledgements
for insert
with check ((select app_private.current_user_is_admin()));

drop policy if exists wellness_acknowledgements_admin_update on public.wellness_acknowledgements;
create policy wellness_acknowledgements_admin_update
on public.wellness_acknowledgements
for update
using ((select app_private.current_user_is_admin()))
with check ((select app_private.current_user_is_admin()));

drop policy if exists profile_acknowledgements_select on public.profile_acknowledgements;
create policy profile_acknowledgements_select
on public.profile_acknowledgements
for select
using (profile_id = (select auth.uid()) or (select app_private.current_user_is_admin()));

drop policy if exists profile_acknowledgements_insert_own on public.profile_acknowledgements;
create policy profile_acknowledgements_insert_own
on public.profile_acknowledgements
for insert
with check (
    profile_id = (select auth.uid())
    and exists (
        select 1
        from public.wellness_acknowledgements acknowledgement
        where acknowledgement.id = acknowledgement_id
          and acknowledgement.version = profile_acknowledgements.version
          and acknowledgement.is_active
    )
);

grant select on public.wellness_acknowledgements to anon, authenticated;
grant insert, update on public.wellness_acknowledgements to authenticated;
grant select, insert on public.profile_acknowledgements to authenticated;

create or replace function app_private.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists touch_wellness_acknowledgements_updated_at on public.wellness_acknowledgements;
create trigger touch_wellness_acknowledgements_updated_at
before update on public.wellness_acknowledgements
for each row execute function app_private.touch_updated_at();

insert into public.wellness_acknowledgements (
    version,
    title,
    body,
    capacity_text,
    fair_use_text,
    medical_text,
    is_active,
    published_at
)
select
    '2026-06-06-v1',
    'Wellbeing Facility Acknowledgement',
    'Please read and acknowledge this before using the wellbeing facility. Use of the facility is voluntary and at your own risk.',
    'The wellbeing facility is limited to 20 people at a time.',
    'To keep access fair, each staff member can book one session per day, up to 7 days in advance.',
    'If you have a medical condition, injury, or any concern about exercise, seek medical advice before using the facility.',
    true,
    now()
where not exists (
    select 1
    from public.wellness_acknowledgements
    where is_active
);

create or replace function public.publish_wellness_acknowledgement(
    p_title text,
    p_body text,
    p_capacity_text text,
    p_fair_use_text text,
    p_medical_text text
)
returns public.wellness_acknowledgements
language plpgsql
security invoker
set search_path = public, app_private
as $$
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

revoke execute on function public.publish_wellness_acknowledgement(text, text, text, text, text) from public;
revoke execute on function public.publish_wellness_acknowledgement(text, text, text, text, text) from anon;
grant execute on function public.publish_wellness_acknowledgement(text, text, text, text, text) to authenticated;
