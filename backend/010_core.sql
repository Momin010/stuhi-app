-- STUHI app — core schema
-- Self-hosted on Mark's box (server/), https://stuhi-api.porkkanat.com.
-- Moved off hosted Supabase 23 Sep 2026 after the free project was paused.
-- Applied in filename order by server/setup.sh (run via server/deploy.sh).
--
-- Ordering: 010_core (this file) → 030_matching.sql → 090_seed_demo.sql
--
-- Design rules that the App Store review depends on, do not break them:
--   * Nobody's bio or free text is readable by "any authenticated user".
--     Attendee-visible data is gated on being a confirmed attendee of the
--     same event (Guideline 1.2, and basic decency towards 15-19 year olds).
--   * Every table with user content has RLS enabled and real policies.
--   * account_role is granted by the organisation, never self-claimed.
--     A client can read its own role but can never write it.

begin;

create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────

-- Who someone is inside STUHI. Ordered least → most privileged.
--   member : general public / event attendee. Self sign-up.
--   monk   : active at STUHI, holds a @stuhi.org address. Sees internal feed.
--   staff  : monk + can operate the door/meal scanner during an event.
--   admin  : core team. Can publish, import guests, run auto-assign.
do $$ begin
  create type account_role as enum ('member', 'monk', 'staff', 'admin');
exception when duplicate_object then null; end $$;

-- The fixed role taxonomy used for team matching. Deliberately closed:
-- free-text skills make matching impossible and moderation harder.
do $$ begin
  create type role_tag as enum (
    'design', 'frontend', 'backend', 'hardware', 'ai', 'business', 'media'
  );
exception when duplicate_object then null; end $$;

-- Who an announcement or schedule item is for.
do $$ begin
  create type audience as enum ('public', 'attendee', 'monk');
exception when duplicate_object then null; end $$;

do $$ begin
  create type ticket_state as enum ('issued', 'admitted', 'void');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- profiles — one row per auth.users row
-- ─────────────────────────────────────────────────────────────────────────
-- NOTE for 030_matching.sql: the matching migration may ALTER this table to
-- add columns it needs, but must not recreate it. The columns below are the
-- contract: id, account_role, bio, primary_role, secondary_role,
-- skill_level, languages, looking_for_team, deleted_at.

create table if not exists profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  email             text        not null,
  full_name         text        not null default '',
  display_name      text        not null default '',

  account_role      account_role not null default 'member',

  -- Matching profile. All optional until the attendee opts into matching.
  bio               text,
  primary_role      role_tag,
  secondary_role    role_tag,
  skill_level       smallint,                 -- 1 beginner, 2 some, 3 confident
  languages         text[]      not null default '{}',   -- 'fi', 'en'
  looking_for_team  boolean     not null default false,

  -- Moderation state. Set by admins; a suspended profile is hidden from
  -- every attendee-facing listing and cannot send requests or invites.
  suspended_at      timestamptz,
  suspended_reason  text,

  push_token        text,
  push_opted_in     boolean     not null default false,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  -- Soft delete. 5.1.1(v) account deletion sets this and scrubs personal
  -- fields; check-in counts survive as anonymous aggregates.
  deleted_at        timestamptz,

  constraint bio_length         check (bio is null or char_length(bio) <= 280),
  constraint skill_level_range  check (skill_level is null or skill_level between 1 and 3),
  constraint roles_differ       check (secondary_role is null or secondary_role is distinct from primary_role)
);

create index if not exists profiles_role_idx        on profiles (account_role) where deleted_at is null;
create index if not exists profiles_looking_idx     on profiles (looking_for_team) where deleted_at is null and suspended_at is null;
create unique index if not exists profiles_email_idx on profiles (lower(email)) where deleted_at is null;

-- ─────────────────────────────────────────────────────────────────────────
-- events
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists events (
  id            uuid primary key default gen_random_uuid(),
  slug          text        not null unique,
  name          text        not null,
  tagline       text,
  venue         text,
  venue_address text,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  timezone      text        not null default 'Europe/Helsinki',
  -- An unpublished event is invisible to members. Lets us seed the reviewer's
  -- world without showing half-built content to attendees.
  published     boolean     not null default false,
  created_at    timestamptz not null default now(),

  constraint event_dates check (ends_at > starts_at)
);

-- ─────────────────────────────────────────────────────────────────────────
-- challenges — the hackathon's problem statements
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists challenges (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references events(id) on delete cascade,
  ordinal      smallint not null default 0,
  title        text not null,
  summary      text not null default '',
  body         text not null default '',      -- markdown
  partner      text,                           -- sponsoring company, if any
  prize        text,
  published    boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists challenges_event_idx on challenges (event_id, ordinal);

-- ─────────────────────────────────────────────────────────────────────────
-- schedule_items
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists schedule_items (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references events(id) on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  title       text not null,
  detail      text,
  location    text,
  -- 'meal' items are what the scanner's meal mode claims against.
  kind        text not null default 'session',   -- session | meal | ceremony | break
  for_audience audience not null default 'attendee',
  published   boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists schedule_event_idx on schedule_items (event_id, starts_at);

-- ─────────────────────────────────────────────────────────────────────────
-- announcements — the feed. Monk-only items live here too, gated by audience.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists announcements (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid references events(id) on delete cascade,   -- null = org-wide
  title        text not null,
  body         text not null default '',
  for_audience audience not null default 'attendee',
  pinned       boolean not null default false,
  -- Set when a push was actually delivered for this announcement, so the
  -- organiser can see what has already gone out and not double-send.
  pushed_at    timestamptz,
  author_id    uuid references profiles(id) on delete set null,
  published    boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists announcements_feed_idx on announcements (for_audience, pinned desc, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────
-- guest_list — imported from the Luma CSV export
-- ─────────────────────────────────────────────────────────────────────────
-- STUHI has no Luma Plus, so there is no Luma API. Organisers export the
-- guest list as CSV and we import it here. This is personal data about
-- people who have not installed the app yet, so: minimum fields, admin-only
-- read, and it is purged after the event (see docs/PRIVACY.md).

create table if not exists guest_list (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id) on delete cascade,
  email         text not null,
  full_name     text not null default '',
  source        text not null default 'luma-csv',
  imported_at   timestamptz not null default now(),
  -- Set once someone signs up in the app with a matching email.
  claimed_by    uuid references profiles(id) on delete set null,
  claimed_at    timestamptz
);

create unique index if not exists guest_list_email_idx on guest_list (event_id, lower(email));

-- ─────────────────────────────────────────────────────────────────────────
-- tickets — the app's own admission QR
-- ─────────────────────────────────────────────────────────────────────────
-- The QR encodes `code` only: a random opaque string, no personal data, so a
-- photograph of someone's screen leaks nothing. The scanner resolves it
-- server-side.

create table if not exists tickets (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references events(id) on delete cascade,
  profile_id   uuid not null references profiles(id) on delete cascade,
  code         text not null unique default encode(gen_random_bytes(16), 'hex'),
  state        ticket_state not null default 'issued',
  issued_at    timestamptz not null default now(),
  admitted_at  timestamptz,
  admitted_by  uuid references profiles(id) on delete set null
);

create unique index if not exists tickets_one_per_person on tickets (event_id, profile_id);
create index if not exists tickets_code_idx on tickets (code);

-- ─────────────────────────────────────────────────────────────────────────
-- meal_claims — one row per person per meal, so nobody eats twice and
-- catering gets a real number
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists meal_claims (
  id                uuid primary key default gen_random_uuid(),
  schedule_item_id  uuid not null references schedule_items(id) on delete cascade,
  ticket_id         uuid not null references tickets(id) on delete cascade,
  claimed_at        timestamptz not null default now(),
  claimed_by        uuid references profiles(id) on delete set null
);

create unique index if not exists meal_claims_once on meal_claims (schedule_item_id, ticket_id);

-- ─────────────────────────────────────────────────────────────────────────
-- Moderation — Guideline 1.2 requires report and block to exist in the app
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists blocks (
  blocker_id  uuid not null references profiles(id) on delete cascade,
  blocked_id  uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

create table if not exists reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid references profiles(id) on delete set null,
  subject_id    uuid references profiles(id) on delete set null,
  -- What was reported: a profile, a team name, a message.
  subject_kind  text not null default 'profile',
  subject_ref   uuid,
  reason        text not null,
  detail        text,
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz,
  resolved_by   uuid references profiles(id) on delete set null,
  resolution    text
);

create index if not exists reports_open_idx on reports (created_at desc) where resolved_at is null;

-- ─────────────────────────────────────────────────────────────────────────
-- Helper functions used by policies
-- ─────────────────────────────────────────────────────────────────────────

create or replace function my_role() returns account_role
language sql stable security definer set search_path = public as $$
  select account_role from profiles where id = auth.uid() and deleted_at is null
$$;

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_role() in ('staff','admin'), false)
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_role() = 'admin', false)
$$;

create or replace function is_monk() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_role() in ('monk','staff','admin'), false)
$$;

-- Is the current user a confirmed attendee of this event? Holding a ticket
-- is what unlocks seeing other attendees at all.
create or replace function attends(evt uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tickets t
    where t.event_id = evt and t.profile_id = auth.uid() and t.state <> 'void'
  )
$$;

-- Keep updated_at honest.
create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists profiles_touch on profiles;
create trigger profiles_touch before update on profiles
  for each row execute function touch_updated_at();

-- New auth user → profile row. Everyone starts as 'member'; monk/staff/admin
-- is granted afterwards by an admin, never claimed at sign-up.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────
-- Row Level Security
-- ─────────────────────────────────────────────────────────────────────────

alter table profiles       enable row level security;
alter table events         enable row level security;
alter table challenges     enable row level security;
alter table schedule_items enable row level security;
alter table announcements  enable row level security;
alter table guest_list     enable row level security;
alter table tickets        enable row level security;
alter table meal_claims    enable row level security;
alter table blocks         enable row level security;
alter table reports        enable row level security;

-- profiles ----------------------------------------------------------------
-- You always see yourself.
drop policy if exists profiles_self_read on profiles;
create policy profiles_self_read on profiles
  for select using (id = auth.uid());

-- You see another attendee only if you both hold a ticket to the same event,
-- neither of you has blocked the other, and they are neither suspended nor
-- deleted. This is what stops the bio field being a public directory of minors.
drop policy if exists profiles_attendee_read on profiles;
create policy profiles_attendee_read on profiles
  for select using (
    deleted_at is null
    and suspended_at is null
    and exists (
      select 1
      from tickets mine
      join tickets theirs on theirs.event_id = mine.event_id
      where mine.profile_id = auth.uid()
        and mine.state <> 'void'
        and theirs.profile_id = profiles.id
        and theirs.state <> 'void'
    )
    and not exists (
      select 1 from blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = profiles.id)
         or (b.blocker_id = profiles.id and b.blocked_id = auth.uid())
    )
  );

drop policy if exists profiles_staff_read on profiles;
create policy profiles_staff_read on profiles
  for select using (is_staff());

-- You may edit your own profile, but never your own account_role or
-- suspension. Those columns are protected by the trigger below rather than
-- by the policy, because Postgres RLS cannot express column-level writes.
drop policy if exists profiles_self_write on profiles;
create policy profiles_self_write on profiles
  for update using (id = auth.uid() and deleted_at is null)
             with check (id = auth.uid());

create or replace function guard_profile_privileges() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() is null only on a trusted server-side connection (psql, the
  -- Management API, a migration). Every client request carries a JWT, so this
  -- is not a hole a user can reach. Without it there is no bootstrap: the
  -- first admin could never be created, because only an admin may create one.
  if auth.uid() is null or is_admin() then return new; end if;

  if new.account_role  is distinct from old.account_role
     or new.suspended_at is distinct from old.suspended_at then
    raise exception 'account_role and suspension are granted by STUHI, not self-assigned';
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard on profiles;
create trigger profiles_guard before update on profiles
  for each row execute function guard_profile_privileges();

drop policy if exists profiles_admin_write on profiles;
create policy profiles_admin_write on profiles
  for update using (is_admin()) with check (is_admin());

-- events / challenges / schedule -----------------------------------------
-- Published event content is readable WITHOUT signing in. Guideline 5.1.1(v):
-- "If your app doesn't include significant account-based features, let people
-- use it without a login." Schedule and challenges are the app's shop window
-- and gating them behind auth is a real rejection risk.
drop policy if exists events_public_read on events;
create policy events_public_read on events
  for select using (published or is_admin());

drop policy if exists challenges_public_read on challenges;
create policy challenges_public_read on challenges
  for select using (
    is_admin() or (published and exists (
      select 1 from events e where e.id = challenges.event_id and e.published
    ))
  );

drop policy if exists schedule_public_read on schedule_items;
create policy schedule_public_read on schedule_items
  for select using (
    is_admin()
    or (published and for_audience = 'public')
    or (published and for_audience = 'attendee' and auth.uid() is not null)
    or (published and for_audience = 'monk' and is_monk())
  );

drop policy if exists events_admin_write on events;
create policy events_admin_write on events for all using (is_admin()) with check (is_admin());
drop policy if exists challenges_admin_write on challenges;
create policy challenges_admin_write on challenges for all using (is_admin()) with check (is_admin());
drop policy if exists schedule_admin_write on schedule_items;
create policy schedule_admin_write on schedule_items for all using (is_admin()) with check (is_admin());

-- announcements -----------------------------------------------------------
-- This is the monk/member split made real.
drop policy if exists announcements_read on announcements;
create policy announcements_read on announcements
  for select using (
    is_admin()
    or (published and for_audience = 'public')
    or (published and for_audience = 'attendee' and auth.uid() is not null)
    or (published and for_audience = 'monk' and is_monk())
  );

drop policy if exists announcements_admin_write on announcements;
create policy announcements_admin_write on announcements
  for all using (is_admin()) with check (is_admin());

-- guest_list --------------------------------------------------------------
-- Admin only. Nobody else ever reads the imported list.
drop policy if exists guest_list_admin on guest_list;
create policy guest_list_admin on guest_list
  for all using (is_admin()) with check (is_admin());

-- tickets -----------------------------------------------------------------
drop policy if exists tickets_self_read on tickets;
create policy tickets_self_read on tickets
  for select using (profile_id = auth.uid());

drop policy if exists tickets_staff on tickets;
create policy tickets_staff on tickets
  for all using (is_staff()) with check (is_staff());

-- meal_claims -------------------------------------------------------------
drop policy if exists meal_claims_self_read on meal_claims;
create policy meal_claims_self_read on meal_claims
  for select using (
    exists (select 1 from tickets t where t.id = meal_claims.ticket_id and t.profile_id = auth.uid())
  );

drop policy if exists meal_claims_staff on meal_claims;
create policy meal_claims_staff on meal_claims
  for all using (is_staff()) with check (is_staff());

-- blocks ------------------------------------------------------------------
-- You manage your own block list and can see only your own.
drop policy if exists blocks_own on blocks;
create policy blocks_own on blocks
  for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

drop policy if exists blocks_admin_read on blocks;
create policy blocks_admin_read on blocks
  for select using (is_admin());

-- reports -----------------------------------------------------------------
-- You may file a report and see your own. Only admins read the queue.
drop policy if exists reports_insert on reports;
create policy reports_insert on reports
  for insert with check (reporter_id = auth.uid());

drop policy if exists reports_own_read on reports;
create policy reports_own_read on reports
  for select using (reporter_id = auth.uid());

drop policy if exists reports_admin on reports;
create policy reports_admin on reports
  for all using (is_admin()) with check (is_admin());

-- ─────────────────────────────────────────────────────────────────────────
-- Scanning — one round trip, server time, unambiguous outcome
-- ─────────────────────────────────────────────────────────────────────────
-- Doing this in the app would mean a PATCH carrying a client timestamp (so
-- device clock skew lands in the column) and inferring "already collected"
-- from an HTTP status code. Both are done properly here instead. The outcome
-- string is what the scanner UI switches on:
--   ok | already | void | unknown

create or replace function admit_ticket(ticket_code text)
returns table (outcome text, holder text, at timestamptz)
language plpgsql security definer set search_path = public as $$
declare t tickets%rowtype; who text;
begin
  if not is_staff() then raise exception 'staff only'; end if;

  select * into t from tickets where code = ticket_code;
  if not found then
    return query select 'unknown'::text, null::text, null::timestamptz; return;
  end if;

  select coalesce(nullif(display_name,''), full_name, 'Guest')
    into who from profiles where id = t.profile_id;

  if t.state = 'void' then
    return query select 'void'::text, who, null::timestamptz; return;
  end if;

  if t.state = 'admitted' then
    -- Not an error. Staff need to see WHEN they first came in, because this
    -- is how a passed-back phone gets caught.
    return query select 'already'::text, who, t.admitted_at; return;
  end if;

  update tickets
     set state = 'admitted', admitted_at = now(), admitted_by = auth.uid()
   where id = t.id;

  return query select 'ok'::text, who, now();
end $$;

create or replace function claim_meal(ticket_code text, item uuid)
returns table (outcome text, holder text, at timestamptz)
language plpgsql security definer set search_path = public as $$
declare t tickets%rowtype; who text; existing timestamptz;
begin
  if not is_staff() then raise exception 'staff only'; end if;

  select * into t from tickets where code = ticket_code;
  if not found then
    return query select 'unknown'::text, null::text, null::timestamptz; return;
  end if;

  select coalesce(nullif(display_name,''), full_name, 'Guest')
    into who from profiles where id = t.profile_id;

  if t.state = 'void' then
    return query select 'void'::text, who, null::timestamptz; return;
  end if;

  select claimed_at into existing
    from meal_claims where schedule_item_id = item and ticket_id = t.id;
  if found then
    return query select 'already'::text, who, existing; return;
  end if;

  insert into meal_claims (schedule_item_id, ticket_id, claimed_by)
  values (item, t.id, auth.uid());

  return query select 'ok'::text, who, now();
end $$;

revoke all on function admit_ticket(text) from public;
revoke all on function claim_meal(text, uuid) from public;
grant execute on function admit_ticket(text) to authenticated;
grant execute on function claim_meal(text, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Your own block list, with names
-- ─────────────────────────────────────────────────────────────────────────
-- profiles_attendee_read deliberately hides anyone in a block relationship in
-- EITHER direction, which is correct — but it also means you cannot see the
-- names of the people you yourself blocked, so the "Blocked people" screen
-- would show a list of anonymous rows. This function is the narrow, deliberate
-- exception: security definer, returns only the caller's own block list, and
-- only a display name.

create or replace function my_blocked_people()
returns table (id uuid, display_name text, blocked_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, b.created_at
    from blocks b
    join profiles p on p.id = b.blocked_id
   where b.blocker_id = auth.uid()
   order by b.created_at desc
$$;

revoke all on function my_blocked_people() from public;
grant execute on function my_blocked_people() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Account deletion — Guideline 5.1.1(v)
-- ─────────────────────────────────────────────────────────────────────────
-- Called from the app by the signed-in user. Scrubs personal data, keeps the
-- row so foreign keys and anonymous head-counts survive, then the client
-- signs out. The auth.users row is removed by a nightly admin job (the
-- anon/publishable key cannot delete auth users).

create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in'; end if;

  delete from blocks where blocker_id = uid or blocked_id = uid;
  update reports set reporter_id = null where reporter_id = uid;

  update profiles set
    email            = 'deleted+' || uid::text || '@stuhi.invalid',
    full_name        = '',
    display_name     = 'Deleted account',
    bio              = null,
    primary_role     = null,
    secondary_role   = null,
    skill_level      = null,
    languages        = '{}',
    looking_for_team = false,
    push_token       = null,
    push_opted_in    = false,
    deleted_at       = now()
  where id = uid;

  update guest_list set claimed_by = null where claimed_by = uid;
  update tickets set state = 'void' where profile_id = uid;
end $$;

revoke all on function delete_my_account() from public;
grant execute on function delete_my_account() to authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented; destroys all data)
-- ─────────────────────────────────────────────────────────────────────────
-- drop function if exists delete_my_account, guard_profile_privileges,
--   handle_new_user, touch_updated_at, attends, is_admin, is_monk, is_staff, my_role;
-- drop table if exists reports, blocks, meal_claims, tickets, guest_list,
--   announcements, schedule_items, challenges, events, profiles cascade;
-- drop type if exists ticket_state, audience, role_tag, account_role;
