-- ═════════════════════════════════════════════════════════════════════════
-- STUHI app — 030_matching.sql
-- Team matching: schema, RLS, the link machine (Mechanics A + B) and the
-- auto-assign safety net (Mechanic C).
--
-- Implements docs/MATCHING.md. Hosted Supabase Postgres 15+ (EU region).
-- Ordering: 010_core.sql → 020_moderation.sql → 030_matching.sql (this file)
--           → 090_seed_demo.sql
-- Encoding: UTF-8. Finnish and English data is stored verbatim, and every
-- attendee-visible string this file produces exists in both languages.
--
-- ─────────────────────────────────────────────────────────────────────────
-- WHAT THIS FILE REQUIRES OF `public.profiles`
-- ─────────────────────────────────────────────────────────────────────────
-- profiles is created by 010_core.sql and is NOT created here. This file
-- ALTERs it additively (010_core explicitly sanctions that). This list is the
-- contract; reconcile the core schema against it, not the other way round:
--
--   id               uuid  primary key references auth.users(id)  -- = auth.uid()
--   display_name     text  not null            -- "Aino K." Shown to other attendees.
--   account_role     account_role not null     -- member|monk|staff|admin
--   primary_role     role_tag                  -- null until onboarding completes
--   secondary_role   role_tag                  -- null allowed, must differ from primary
--   skill_level      smallint                  -- 1 first_time, 2 been_to_a_few, 3 lots
--                                              -- THIS is the matcher's experience band.
--   languages        text[] not null default '{}'    -- subset of {'fi','en'}
--   looking_for_team boolean not null default false  -- opt-in to being browsable
--   bio              text                      -- UGC. The matcher never reads it.
--   suspended_at     timestamptz               -- suspended ⇒ invisible and unmatched
--   deleted_at       timestamptz               -- soft delete ⇒ invisible and unmatched
--
-- Columns this file ADDS to profiles (all with safe defaults, no backfill):
--   wants_team, solo_opted_at, wants_late_seat, starved, bio_status,
--   bio_submitted_at, bio_reviewed_by, bio_reviewed_at, terms_version,
--   terms_accepted_at, safety_lead
--
-- ALSO REQUIRED, from 010_core.sql:
--   events(id uuid pk, published boolean)            -- one row per event
--   challenges(id uuid pk, event_id, ordinal smallint, published boolean)
--   tickets(event_id, profile_id, state ticket_state)
--       `tickets.state = 'admitted'` IS check-in, and it is the hard cohort
--       gate for auto-assign. A ticket that is merely 'issued' is a
--       registration, not an attendee.
--   blocks(blocker_id, blocked_id)                   -- attendee-initiated, silent
--   role_tag enum ('design','frontend','backend','hardware','ai','business','media')
--   functions my_role(), is_staff(), is_admin(), attends(uuid)
--
-- Deliberate reconciliations with docs/MATCHING.md, so nobody reads these as
-- mistakes:
--   * challenges.id is uuid here (010_core), not smallint. Every tie-break
--     that used a challenge id uses (challenges.ordinal, challenge_id::text)
--     instead, which is still a total order.
--   * role_t is 010_core's `role_tag`; its AI member is spelled 'ai'.
--   * exp_t is 010_core's `skill_level` smallint 1..3, so exp_ord(e) is the
--     integer itself. There is no second experience column.
--   * lang_t is 010_core's `languages text[]`; lang_class() derives
--     fi_only / en_only / both from it.
--   * registrations/presence_t is 010_core's `tickets`/`ticket_state`. Legal
--     name and contact email live on profiles.full_name/email and are never
--     read by anything in this file. Grep it: no hits.
--   * organizer         ≈ is_admin()
--     organizer_checkin ≈ is_staff()
--     organizer_safety  ≈ is_safety()   (admin, or profiles.safety_lead)
--   * 020_moderation.sql's moderate_team() also reads `new.pitch`, and its
--     join-request filter expects a `join_requests.message`. Neither exists
--     here, on purpose: there is NO free text on a request or an invite, so
--     zero attacker-controlled characters travel between two strangers. 020
--     guards both with to_regclass and creates neither trigger when applied
--     in order; this file then binds its own name-only trigger to `teams`
--     below, so re-applying 020 afterwards cannot break team creation.
--
-- KNOWN FOLLOW-UP, not in this file: core's delete_my_account() should also
-- call match_release_seat(uid). One line in 010_core.
-- ═════════════════════════════════════════════════════════════════════════

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- Preflight. Fail loudly and specifically, not with a cascade of
-- "relation does not exist" fifty lines later.
-- ─────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v_missing text := '';
  v_name    text;
begin
  foreach v_name in array array['profiles','events','challenges','tickets','blocks'] loop
    if to_regclass('public.' || v_name) is null then
      v_missing := v_missing || ' table:' || v_name;
    end if;
  end loop;

  if to_regtype('public.role_tag') is null then
    v_missing := v_missing || ' type:role_tag';
  end if;

  foreach v_name in array array['id','display_name','account_role','primary_role',
                                'secondary_role','skill_level','languages',
                                'looking_for_team','bio','suspended_at','deleted_at'] loop
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'profiles'
                     and column_name = v_name) then
      v_missing := v_missing || ' profiles.' || v_name;
    end if;
  end loop;

  if v_missing <> '' then
    raise exception '030_matching.sql: 010_core.sql has not been applied, or has drifted. Missing:%',
      v_missing;
  end if;
end
$preflight$;

-- ─────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────
-- Every one of these is closed on purpose. An enum cannot quietly become an
-- unmoderated free-text channel describing a named 16-year-old inside an
-- organiser console. A text column always eventually does.

do $$ begin
  -- build = someone who makes it work; craft = someone who makes it look and
  -- sound like something; voice = someone who can stand up and say what it is.
  -- "One of each of the seven roles" is unsatisfiable in a team of four and
  -- has no defined failure behaviour. Three classes at size 4 is satisfiable
  -- and checkable in one expression.
  create type role_class_t as enum ('build','craft','voice');
exception when duplicate_object then null; end $$;

do $$ begin
  create type lang_class_t as enum ('fi_only','en_only','both');
exception when duplicate_object then null; end $$;

do $$ begin
  create type work_lang_t as enum ('fi','en');
exception when duplicate_object then null; end $$;

do $$ begin
  -- 'request' = person → team (Mechanic A). 'invite' = team → person (B).
  -- ONE table, one state machine, one expiry job, one RLS set.
  create type link_dir_t as enum ('request','invite');
exception when duplicate_object then null; end $$;

do $$ begin
  -- dismissed / expired / superseded are three different facts that render to
  -- the sender as ONE byte-identical string. See the my_links view.
  create type link_state_t as enum
    ('pending','accepted','withdrawn','dismissed','expired','superseded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type join_via_t as enum
    ('founder','invite','request','auto','organiser','late','split');
exception when duplicate_object then null; end $$;

do $$ begin
  create type team_state_t as enum ('forming','active','disbanded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type team_origin_t as enum ('self_formed','auto','late_pool','organiser');
exception when duplicate_object then null; end $$;

do $$ begin
  -- dry    : rehearsal, may run on the registration roster, labelled UNRELIABLE
  -- full   : the 09:00 run
  -- repair : minimum-churn reconciliation later in the event
  -- single : one walk-in
  -- There are four modes and there will not be a fifth.
  create type run_mode_t as enum ('dry','full','repair','single');
exception when duplicate_object then null; end $$;

do $$ begin
  create type run_state_t as enum ('draft','previewed','published','discarded','failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type bio_state_t as enum ('none','pending','approved','rejected','removed');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- Pure helpers. The only place the taxonomy is interpreted.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function role_class(r role_tag) returns role_class_t
language sql immutable parallel safe as $$
  select case r
    when 'frontend' then 'build'
    when 'backend'  then 'build'
    when 'hardware' then 'build'
    when 'ai'       then 'build'
    when 'design'   then 'craft'
    when 'media'    then 'craft'
    else 'voice'                     -- business
  end::role_class_t
$$;

-- Tie-break ordinal for role_tag: design, frontend, backend, hardware, ai,
-- business, media. STABLE rather than IMMUTABLE because enum_range depends on
-- catalog state; it is only ever used in ORDER BY, never in an index.
create or replace function role_ordinal(r role_tag) returns int
language sql stable parallel safe as $$
  select array_position(enum_range(null::role_tag), r)
$$;

-- fi_only / en_only / both, derived from profiles.languages.
-- NULL means "profile incomplete", which keeps the person out of every pool.
create or replace function lang_class(langs text[]) returns lang_class_t
language sql immutable parallel safe as $$
  select case
    when langs is null then null
    when ('fi' = any(langs)) and ('en' = any(langs)) then 'both'
    when ('fi' = any(langs)) then 'fi_only'
    when ('en' = any(langs)) then 'en_only'
    else null
  end::lang_class_t
$$;

create or replace function match_clamp(v int, lo int, hi int) returns int
language sql immutable parallel safe as $$
  select greatest(lo, least(hi, v))
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Additive columns on 010_core tables
-- ─────────────────────────────────────────────────────────────────────────

-- profiles: matching intent, the starvation counter, bio moderation state.
alter table profiles add column if not exists wants_team        boolean not null default true;
alter table profiles add column if not exists solo_opted_at     timestamptz;
alter table profiles add column if not exists wants_late_seat   boolean not null default true;
-- starved: closed outbound links that were never accepted. NEVER shown to its
-- owner, never to anybody else, never in any view. It is the FIRST sort key of
-- the draft, so the person who tried hardest and got nothing takes first pick.
-- It is a scheduling input, not a status, and it is written by trigger only.
alter table profiles add column if not exists starved           smallint not null default 0;
alter table profiles add column if not exists bio_status        bio_state_t not null default 'none';
alter table profiles add column if not exists bio_submitted_at  timestamptz;
alter table profiles add column if not exists bio_reviewed_by   uuid references profiles(id);
alter table profiles add column if not exists bio_reviewed_at   timestamptz;
alter table profiles add column if not exists terms_version     text;
alter table profiles add column if not exists terms_accepted_at timestamptz;
alter table profiles add column if not exists safety_lead       boolean not null default false;

-- organizer_safety. Admins always are; a named Safety Lead and their two
-- night deputies are flagged individually.
create or replace function is_safety() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.account_role = 'admin' or p.safety_lead
       from profiles p where p.id = auth.uid() and p.deleted_at is null),
    false)
$$;


do $$ begin
  alter table profiles add constraint solo_not_browsable
    check (not (wants_team = false and looking_for_team));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table profiles add constraint starved_sane check (starved between 0 and 1000);
exception when duplicate_object then null; end $$;

create index if not exists profiles_pool_idx on profiles (wants_team)
  where deleted_at is null and suspended_at is null and primary_role is not null;

-- events: the matching configuration, so constants are editable without a deploy.
alter table events add column if not exists challenges_frozen_at  timestamptz;
alter table events add column if not exists matching_opens_at     timestamptz;
-- ADVISORY ONLY. Displayed to attendees ("matching closes around 09:00").
-- What actually closes matching is an organiser pressing the button
-- (match_close_matching), because the opening ceremony WILL overrun and a
-- cron job cannot know that the mayor is still talking.
alter table events add column if not exists assign_deadline_at    timestamptz;
alter table events add column if not exists matching_closed_at    timestamptz;
alter table events add column if not exists switch_window_ends_at timestamptz;
alter table events add column if not exists target_team_size      smallint not null default 4;
alter table events add column if not exists min_team_size         smallint not null default 3;
alter table events add column if not exists max_team_size         smallint not null default 5;
alter table events add column if not exists min_bucket_size       smallint not null default 6;
alter table events add column if not exists max_open_links        smallint not null default 3;
alter table events add column if not exists max_inbound_links     smallint not null default 8;
alter table events add column if not exists request_ttl_hours     smallint not null default 48;
alter table events add column if not exists invite_ttl_hours      smallint not null default 12;
alter table events add column if not exists block_cap             smallint not null default 10;
-- Bios ship DISABLED. The matcher reads no free text, so this costs matching
-- exactly nothing. Flipped to true only if a named adult Safety Lead plus two
-- night deputies are confirmed in writing by T-14d.
alter table events add column if not exists bio_enabled           boolean not null default false;
alter table events add column if not exists late_join_enabled     boolean not null default true;
alter table events add column if not exists reserve_tables        int[] not null default '{}';
alter table events add column if not exists first_table_number    int not null default 1;
alter table events add column if not exists terms_version         text;

do $$ begin
  alter table events add constraint team_sizes_ordered
    check (min_team_size <= target_team_size and target_team_size <= max_team_size
           and min_team_size >= 2 and max_team_size <= 8);
exception when duplicate_object then null; end $$;

-- challenges: the capacity ceiling that stops one glamorous challenge eating
-- 41% of first choices, and a code that is readable in a log at 03:00.
alter table challenges add column if not exists code      text;
alter table challenges add column if not exists max_teams smallint;
alter table challenges add column if not exists state     text not null default 'draft';

do $$ begin
  alter table challenges add constraint challenge_state_valid
    check (state in ('draft','published','withdrawn'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table challenges add constraint challenge_max_teams_sane
    check (max_teams is null or max_teams > 0);
exception when duplicate_object then null; end $$;

create unique index if not exists challenges_code_idx on challenges (event_id, code)
  where code is not null;

-- blocks: the matcher asks "who is excluded from whom" constantly.
create index if not exists blocks_blocked_idx on blocks (blocked_id);

-- ═════════════════════════════════════════════════════════════════════════
-- TABLES
-- ═════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- challenge_prefs — exactly three ranked challenges, per person
-- ─────────────────────────────────────────────────────────────────────────
-- Three, not one and not seven. A one-deep list forces first-choice-only
-- bucketing and leaves every fallback rung in the algorithm undefined. A
-- seven-deep list over seven topics is a surprisingly rich profile of a
-- 16-year-old, and only the matcher ever needs even these three.

create table if not exists challenge_prefs (
  profile_id   uuid     not null references profiles(id)   on delete cascade,
  rank         smallint not null check (rank between 1 and 3),
  challenge_id uuid     not null references challenges(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (profile_id, rank),
  unique (profile_id, challenge_id)
);

create index if not exists challenge_prefs_challenge_idx on challenge_prefs (challenge_id, rank);

-- ─────────────────────────────────────────────────────────────────────────
-- teams
-- ─────────────────────────────────────────────────────────────────────────
-- `number` and `table_number` are assigned at publish and are IMMUTABLE
-- afterwards (trigger below). Renumbering an announced team is the cheapest
-- possible way to lose thirty teenagers in a corridor. A disbanded team's
-- number and table are retired for the rest of the event.

create table if not exists teams (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id) on delete cascade,
  number        int,
  table_number  int,
  challenge_id  uuid references challenges(id),
  working_lang  work_lang_t,
  name          text check (name is null or char_length(name) between 2 and 40),
  captain_id    uuid references profiles(id),
  state         team_state_t  not null default 'forming',
  origin        team_origin_t not null default 'self_formed',
  -- Captain opt-in, prompted once at 09:30. Onboarding a latecomer into a
  -- running project is genuinely hard; consent matters more than throughput.
  accepts_late  boolean not null default false,
  -- Organiser freeze. Auto-assign must not touch a locked team, at all.
  locked        boolean not null default false,
  locked_reason text,
  disbanded_at  timestamptz,
  disbanded_reason text check (disbanded_reason is null or disbanded_reason in
                    ('collapsed_below_min','split','organiser','safety')),
  created_by    uuid references profiles(id),
  created_at    timestamptz not null default now(),
  unique (event_id, number),
  unique (event_id, table_number)
);

create index if not exists teams_event_state_idx on teams (event_id, state)
  where state <> 'disbanded';
create index if not exists teams_bucket_idx on teams (event_id, challenge_id, working_lang)
  where state <> 'disbanded';

-- A team name is printed on a placard and on a roster wall in a room full of
-- 15-year-olds, so it is UGC and gets the same filter as a bio. Bound here
-- rather than in 020_moderation.sql because that file's version also reads
-- `new.pitch`, which this design deliberately does not have.
do $modteam$
begin
  if to_regprocedure('public.moderation_verdict(text)') is not null then
    execute $mt$
      create or replace function moderate_team_name() returns trigger
      language plpgsql security definer set search_path = public as $b$
      declare v record;
      begin
        if new.name is not null then
          select * into v from moderation_verdict(new.name);
          if v.action = 'block' then
            raise exception 'Please choose a different team name.'
              using errcode = 'check_violation';
          end if;
        end if;
        return new;
      end $b$;
    $mt$;
    execute 'drop trigger if exists teams_moderate on teams';
    execute 'create trigger teams_moderate before insert or update of name on teams
             for each row execute function moderate_team_name()';
  end if;
end
$modteam$;

-- ─────────────────────────────────────────────────────────────────────────
-- team_gaps — consent, recorded
-- ─────────────────────────────────────────────────────────────────────────
-- A team with NO team_gaps row is never a placement target for anybody: not a
-- request, not an invite, not auto-assign, not an organiser drag without a
-- logged forced override. Three friends who signed up together and did not
-- ask for a fourth will not welcome one, and one shy stranger dropped into
-- three friends is the single worst individual experience this event can
-- produce.

create table if not exists team_gaps (
  team_id     uuid     not null references teams(id) on delete cascade,
  role        role_tag not null,
  seats       smallint not null check (seats between 1 and 4),
  declared_by uuid     not null references profiles(id),
  declared_at timestamptz not null default now(),
  primary key (team_id, role)
);

-- ─────────────────────────────────────────────────────────────────────────
-- team_members
-- ─────────────────────────────────────────────────────────────────────────
-- Rows are NEVER deleted; departure sets left_at. The history is the audit
-- trail somebody needs at 22:00 when an attendee says "I was never on that
-- team". left_reason is a closed set, not free text, precisely so it cannot
-- become an unmoderated description of a named child inside a console.

create table if not exists team_members (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid       not null references teams(id)    on delete cascade,
  profile_id   uuid       not null references profiles(id) on delete cascade,
  role_in_team role_tag   not null,          -- printed on the table placard
  joined_via   join_via_t not null,
  joined_at    timestamptz not null default now(),
  left_at      timestamptz,
  left_reason  text check (left_reason is null or left_reason in
                 ('self','organiser','safety','split','no_show')),
  -- pinned = a push notification has already told this person where they sit.
  -- Moving a pinned person costs them a second "actually you're on Team 40
  -- now", which is strictly worse than a slightly suboptimal team — for
  -- exactly the nervous person this system exists to protect.
  pinned       boolean not null default false,
  notified_at  timestamptz,
  run_id       uuid                          -- provenance: which run seated them
);

-- Makes "person is on two teams" UNREPRESENTABLE. The accept/accept race is
-- dead at the storage layer, not in application logic that somebody will
-- forget to copy into the next RPC.
create unique index if not exists one_active_team_per_person
  on team_members (profile_id) where left_at is null;
create index if not exists team_members_team_idx on team_members (team_id) where left_at is null;
create index if not exists team_members_run_idx  on team_members (run_id);

-- ─────────────────────────────────────────────────────────────────────────
-- link_requests — Mechanic A and Mechanic B, one table
-- ─────────────────────────────────────────────────────────────────────────
-- One state machine, one expiry job, one RLS policy set, one visibility
-- projection, one SwiftUI component with the arrow reversed. This is the
-- largest single line-count saving in the design, and it removes an entire
-- class of "invites expire but requests don't" divergence. The only
-- asymmetries are the TTL and the precondition set, and both are parameters.
--
-- role_code is the ENTIRE payload. There is no message column and there never
-- will be: the invite body is a fixed localised string plus this one enum
-- value, rendered client-side, so zero attacker-controlled characters travel
-- between two strangers. It costs the product nothing.

create table if not exists link_requests (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references events(id)   on delete cascade,
  team_id     uuid not null references teams(id)    on delete cascade,
  profile_id  uuid not null references profiles(id) on delete cascade,
  direction   link_dir_t   not null,
  role_code   role_tag     not null,
  state       link_state_t not null default 'pending',
  created_at  timestamptz  not null default now(),
  -- Recorded so the organiser console can nudge a slow captain. NEVER
  -- revealed to the sender: "seen 6 hours ago, no reply" manufactures the
  -- exact rejection experience this whole design exists to engineer away.
  seen_at     timestamptz,
  expires_at  timestamptz  not null,
  resolved_at timestamptz,
  resolved_by uuid references profiles(id),
  created_by  uuid not null references profiles(id),
  -- Which matching window this belongs to. One approach per pair per window,
  -- in either direction.
  window_tag  text not null default 'main',
  check (state = 'pending' or resolved_at is not null)
);

create unique index if not exists one_live_link
  on link_requests (team_id, profile_id) where state = 'pending';
-- The precondition that stops a silent dismissal being answered with an
-- unlimited stream of fresh requests, which would defeat the entire point of
-- the dismissal being silent.
create unique index if not exists one_approach_per_pair_per_window
  on link_requests (team_id, profile_id, window_tag);
create index if not exists link_by_profile on link_requests (profile_id) where state = 'pending';
create index if not exists link_by_team    on link_requests (team_id)    where state = 'pending';
create index if not exists link_by_expiry  on link_requests (expires_at) where state = 'pending';

-- ─────────────────────────────────────────────────────────────────────────
-- safety_separations — organiser-imposed keep-apart, survives to next year
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists safety_separations (
  user_a     uuid not null references profiles(id) on delete cascade,
  user_b     uuid not null references profiles(id) on delete cascade,
  reason     text not null,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

-- The single source of truth for "these two may never share a team".
-- Normalised so a pair is always (least, greatest) and a lookup is one hit.
create or replace view match_exclusions as
  select least(b.blocker_id, b.blocked_id) as a,
         greatest(b.blocker_id, b.blocked_id) as b
    from blocks b
  union
  select s.user_a, s.user_b from safety_separations s;

-- ─────────────────────────────────────────────────────────────────────────
-- Run machinery
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists match_runs (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id) on delete cascade,
  mode          run_mode_t  not null,
  state         run_state_t not null default 'draft',
  -- Persisted, and reused BYTE FOR BYTE by publish. Every ORDER BY in the
  -- matcher terminates in md5(unit_id || salt); a preview that disagrees with
  -- its own publish destroys the only control that makes auto-assign safe to
  -- ship. The organiser console's "Re-run identical (same salt)" button diffs
  -- two runs row by row, and exists specifically to catch a tie-break
  -- somebody forgot.
  salt          text not null default replace(gen_random_uuid()::text,'-',''),
  snapshot_at   timestamptz not null default now(),
  roster_basis  text not null default 'checked_in'
                check (roster_basis in ('checked_in','registered')),
  params        jsonb not null default '{}'::jsonb,
  parent_run_id uuid references match_runs(id),
  created_by    uuid references profiles(id),
  metrics       jsonb,
  published_at  timestamptz,
  published_by  uuid references profiles(id),
  failed_reason text,
  created_at    timestamptz not null default now()
);

create index if not exists match_runs_event_idx on match_runs (event_id, created_at desc);

-- FROZEN INPUTS. Real tables, not temp tables, and that is deliberate: if
-- publish re-derives the pool from live data, the published result can
-- silently differ from the preview an organiser approved sixty seconds
-- earlier. That is the number-one production defect class in any
-- preview-then-publish design. Freezing the inputs makes "preview equals
-- publish" a property of the code rather than a hope.

create table if not exists run_pool (
  run_id         uuid not null references match_runs(id) on delete cascade,
  profile_id     uuid not null,
  unit_id        uuid not null,          -- singleton: unit_id = profile_id
  unit_size      smallint not null,
  primary_role   role_tag not null,
  secondary_role role_tag,
  experience     smallint not null,
  lang_class     lang_class_t not null,
  starved        smallint not null,
  pref1 uuid, pref2 uuid, pref3 uuid,
  from_team      uuid,
  was_pinned     boolean not null default false,
  primary key (run_id, profile_id)
);

create table if not exists run_seats (
  run_id      uuid not null references match_runs(id) on delete cascade,
  team_key    text not null,             -- 'E:<uuid>' existing, 'N:<bucket>:<ix>' new
  seat_index  smallint not null,
  wanted_role role_tag,
  is_new_team boolean not null,
  bucket_key  text not null,
  primary key (run_id, team_key, seat_index)
);

create table if not exists run_exclusions (
  run_id uuid not null references match_runs(id) on delete cascade,
  a uuid not null,
  b uuid not null,
  primary key (run_id, a, b)
);

-- OUTPUTS
create table if not exists run_placements (
  run_id           uuid not null references match_runs(id) on delete cascade,
  profile_id       uuid not null,
  team_id          uuid not null,        -- new teams: md5(salt || team_key)::uuid,
                                         -- so a re-run with the same salt mints
                                         -- the same id and the diff is empty
  team_key         text not null,
  bucket_key       text not null,
  seq              int  not null,        -- draft pick number, for the explanation
  proposed_role    role_tag not null,
  reason_code      text not null,
  flags            text[] not null default '{}',
  is_move          boolean not null default false,
  was_pinned       boolean not null default false,
  previous_team_id uuid,
  primary key (run_id, profile_id)
);

create index if not exists run_placements_team_idx on run_placements (run_id, team_id);

create table if not exists run_teams (
  run_id         uuid not null references match_runs(id) on delete cascade,
  team_id        uuid not null,
  team_key       text not null,
  bucket_key     text not null,
  challenge_id   uuid,
  working_lang   work_lang_t,
  size           smallint not null,
  is_new         boolean not null,
  table_number   int,
  has_build      boolean,
  has_nonbuild   boolean,
  distinct_roles smallint,
  exp_spread     int,
  flags          text[] not null default '{}',
  primary key (run_id, team_id)
);

-- Every row here BLOCKS PUBLISH until an organiser either seats that person
-- by hand or acknowledges the row with a written note. This is the whole
-- difference between "nobody unteamed, no exceptions" — a promise we cannot
-- keep — and "nobody unteamed, and the exceptions are named on a screen
-- before anything is published", which is one we can.
create table if not exists run_exceptions (
  run_id            uuid not null references match_runs(id) on delete cascade,
  profile_id        uuid not null,
  kind              text not null check (kind in
                      ('unseatable_exclusions','no_language_bucket',
                       'remainder_unseatable','beyond_preferences','merge_loop_cap')),
  detail            text,
  suggested_action  text,
  acknowledged_by   uuid references profiles(id),
  acknowledged_at   timestamptz,
  acknowledged_note text,
  primary key (run_id, profile_id, kind)
);

-- Survives the run. Powers the in-app "why am I on this team" line, which is
-- the answer when somebody walks up to an organiser at 09:05.
create table if not exists placement_trace (
  profile_id  uuid primary key references profiles(id) on delete cascade,
  team_id     uuid references teams(id) on delete set null,
  run_id      uuid references match_runs(id) on delete set null,
  reason_code text not null,
  reason_fi   text not null,
  reason_en   text not null,
  created_at  timestamptz not null default now()
);

-- Append-only. Every manual override, under a named organiser, with a
-- required reason.
create table if not exists organiser_actions (
  id             bigserial primary key,
  event_id       uuid references events(id) on delete cascade,
  actor          uuid not null references profiles(id),
  action         text not null,
  target_profile uuid references profiles(id),
  target_team    uuid references teams(id),
  payload        jsonb,
  reason         text not null,
  forced         boolean not null default false,
  at             timestamptz not null default now()
);

create index if not exists organiser_actions_at_idx on organiser_actions (event_id, at desc);

-- ═════════════════════════════════════════════════════════════════════════
-- INVARIANTS — triggers
-- ═════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Blocked pairs, layer 1: the database, which is the only layer worth
-- defending in an incident review
-- ─────────────────────────────────────────────────────────────────────────
-- This MUST be a DEFERRABLE AFTER CONSTRAINT trigger and not a BEFORE ROW
-- trigger, and that is a real bug being fixed rather than a style preference.
--
-- A BEFORE INSERT ... FOR EACH ROW trigger does not see rows inserted by the
-- SAME command: rows written by the current command carry the current cmin
-- and are invisible to the trigger's SELECT under that command's snapshot. So
--     insert into team_members select ... from run_placements
-- — the natural way to publish 34 teams — would happily commit a blocked pair
-- whenever BOTH members are inserted by that one statement, which is exactly
-- the case for two auto-assigned strangers. A deferred constraint trigger
-- fires at COMMIT, when every row is visible.

create or replace function forbid_excluded_teammate() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.left_at is not null then
    return new;                 -- somebody leaving can never create a violation
  end if;

  if exists (
    select 1
    from team_members tm
    join match_exclusions me
      on me.a = least(tm.profile_id, new.profile_id)
     and me.b = greatest(tm.profile_id, new.profile_id)
    where tm.team_id = new.team_id
      and tm.left_at is null
      and tm.profile_id <> new.profile_id
  ) then
    -- P0002 is caught by every RPC and rendered as the NEUTRAL string
    -- "That spot is no longer available." Never "you are blocked". Neither
    -- party ever learns that an exclusion exists.
    raise exception 'EXCLUSION_VIOLATION' using errcode = 'P0002';
  end if;
  return new;
end
$fn$;

drop trigger if exists tm_exclusion_guard on team_members;
create constraint trigger tm_exclusion_guard
  after insert or update on team_members
  deferrable initially deferred
  for each row execute function forbid_excluded_teammate();

-- The belt to that trigger's braces. publish_run() runs this as its last
-- statement before COMMIT and it must return zero rows. If it ever returns a
-- row the matcher has a bug, and we want to know that before 287 pushes go
-- out rather than after.
create or replace function assert_no_excluded_teammates(p_event uuid)
returns table (team_id uuid, profile_a uuid, profile_b uuid)
language sql stable security definer set search_path = public as $$
  select tm1.team_id, tm1.profile_id, tm2.profile_id
  from team_members tm1
  join team_members tm2
    on tm2.team_id = tm1.team_id and tm2.profile_id > tm1.profile_id
  join teams t on t.id = tm1.team_id
  join match_exclusions me
    on me.a = least(tm1.profile_id, tm2.profile_id)
   and me.b = greatest(tm1.profile_id, tm2.profile_id)
  where tm1.left_at is null and tm2.left_at is null
    and t.event_id = p_event
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Numbers and tables are immutable once announced
-- ─────────────────────────────────────────────────────────────────────────
create or replace function teams_guard_identity() returns trigger
language plpgsql as $fn$
begin
  if old.number is not null and new.number is distinct from old.number then
    raise exception 'TEAM_NUMBER_IMMUTABLE: team % is already announced as %',
      old.id, old.number;
  end if;
  -- table_number MAY change, but only through match_swap_tables(), which sets
  -- this GUC for the duration of its transaction. A broken socket or an
  -- inaccessible table is a real thing that happens at 09:40.
  if old.table_number is not null
     and new.table_number is distinct from old.table_number
     and coalesce(current_setting('stuhi.allow_table_move', true), 'off') <> 'on' then
    raise exception 'TABLE_NUMBER_IMMUTABLE: use match_swap_tables()';
  end if;
  return new;
end
$fn$;

drop trigger if exists teams_identity_guard on teams;
create trigger teams_identity_guard before update on teams
  for each row execute function teams_guard_identity();

-- ─────────────────────────────────────────────────────────────────────────
-- A browsable profile is a COMPLETE profile
-- ─────────────────────────────────────────────────────────────────────────
-- Enforced by trigger, not by the client: the anon key is public and a client
-- check is a suggestion. Every fallback rung in the algorithm assumes three
-- ranked challenges exist.
create or replace function match_profile_is_complete(p_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.primary_role is not null
       and p.skill_level  is not null
       and lang_class(p.languages) is not null
       and p.terms_accepted_at is not null
       and (select count(*) from challenge_prefs cp where cp.profile_id = p.id) = 3
    from profiles p where p.id = p_profile
  ), false)
$$;

create or replace function profiles_guard_browsable() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  -- Completeness MUST be evaluated against NEW, not by re-reading the row.
  -- This is a BEFORE trigger, so match_profile_is_complete(new.id) would read
  -- the row as it still is on disk and reject the very save that completes it
  -- — which is every first-time attendee, since the app writes the profile and
  -- the browsable flag in one PATCH. challenge_prefs is a different table and
  -- is not being written here, so reading it is safe.
  if new.looking_for_team and not (
        new.primary_role is not null
    and new.skill_level  is not null
    and lang_class(new.languages) is not null
    and new.terms_accepted_at is not null
    and (select count(*) from challenge_prefs cp where cp.profile_id = new.id) = 3
  ) then
    raise exception 'PROFILE_INCOMPLETE: finish your role, language, terms and three ranked challenges first'
      using errcode = 'P0003';
  end if;
  -- "I'm working solo this time" is a choice, not a failure state. Stamp when
  -- it was made, never nag, and let it be reversed at any time.
  if new.wants_team = false and old.wants_team then
    new.solo_opted_at := now();
  end if;
  return new;
end
$fn$;

drop trigger if exists profiles_browsable_guard on profiles;
create trigger profiles_browsable_guard before update on profiles
  for each row execute function profiles_guard_browsable();

-- Deleting a ranked challenge while browsable breaks the same invariant from
-- the other side. Deferred, so a client may legitimately rewrite all three
-- rows inside one transaction.
create or replace function prefs_guard_completeness() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare v_profile uuid := coalesce(old.profile_id, new.profile_id);
begin
  if exists (select 1 from profiles p where p.id = v_profile and p.looking_for_team)
     and not match_profile_is_complete(v_profile) then
    raise exception 'PROFILE_INCOMPLETE: you need exactly three ranked challenges'
      using errcode = 'P0003';
  end if;
  return null;
end
$fn$;

drop trigger if exists prefs_completeness_guard on challenge_prefs;
create constraint trigger prefs_completeness_guard
  after insert or update or delete on challenge_prefs
  deferrable initially deferred
  for each row execute function prefs_guard_completeness();

-- ─────────────────────────────────────────────────────────────────────────
-- The starvation counter. Written by TRIGGER ONLY, never by a client.
-- ─────────────────────────────────────────────────────────────────────────
-- Every closed-without-acceptance OUTBOUND link increments the sender's
-- counter, and the counter buys them first pick in the draft. That is the
-- mechanism that converts silence into information instead of into shame.
create or replace function links_touch_starved() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if old.state = 'pending' and new.state in ('dismissed','expired') then
    update profiles p set starved = least(p.starved + 1, 1000)
     where p.id = new.created_by;
  elsif old.state = 'pending' and new.state = 'accepted' then
    -- The debt is paid, whichever direction the link ran in.
    update profiles p set starved = 0 where p.id = new.profile_id;
  end if;
  return null;
end
$fn$;

drop trigger if exists links_starved_trigger on link_requests;
create trigger links_starved_trigger after update of state on link_requests
  for each row execute function links_touch_starved();

-- ─────────────────────────────────────────────────────────────────────────
-- Blocking is instant, silent, symmetric and total
-- ─────────────────────────────────────────────────────────────────────────
-- On a new block: kill every live link between the two parties silently (as
-- 'superseded', which is indistinguishable from a timeout), and if the
-- blocked person is a CURRENT TEAMMATE, write a safety_separation immediately
-- so every future automated action already respects it, then raise a
-- priority-1 organiser item. The team is NOT silently dissolved: splitting a
-- working team is a decision a human makes in a room, and the software's job
-- is to make the seating consequences instant and correct, not to make the
-- decision.
create or replace function blocks_after_insert() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare v_team uuid;
begin
  update link_requests l
     set state = 'superseded', resolved_at = now()
   where l.state = 'pending'
     and ( (l.profile_id = new.blocker_id and exists (
              select 1 from team_members tm where tm.team_id = l.team_id
                and tm.profile_id = new.blocked_id and tm.left_at is null))
        or (l.profile_id = new.blocked_id and exists (
              select 1 from team_members tm where tm.team_id = l.team_id
                and tm.profile_id = new.blocker_id and tm.left_at is null)) );

  select tm1.team_id into v_team
  from team_members tm1
  join team_members tm2 on tm2.team_id = tm1.team_id and tm2.left_at is null
  where tm1.profile_id = new.blocker_id and tm1.left_at is null
    and tm2.profile_id = new.blocked_id
  limit 1;

  if v_team is not null then
    insert into safety_separations (user_a, user_b, reason, created_by)
    values (least(new.blocker_id, new.blocked_id),
            greatest(new.blocker_id, new.blocked_id),
            'auto: block filed against a current teammate', null)
    on conflict do nothing;

    insert into organiser_actions (event_id, actor, action, target_profile, target_team,
                                   payload, reason, forced)
    select t.event_id, new.blocker_id, 'safety_desk_priority_1', new.blocked_id, v_team,
           jsonb_build_object('priority', 1),
           'block filed against a current teammate; a human must attend', false
      from teams t where t.id = v_team;
  end if;
  return null;
end
$fn$;

drop trigger if exists blocks_cascade_trigger on blocks;
create trigger blocks_cascade_trigger after insert on blocks
  for each row execute function blocks_after_insert();

-- Blocks are capped. Ten is not arbitrary: a person with b exclusions is
-- seatable in any bucket with more than b teams, because each counterpart
-- occupies at most one team. A cap of 10 keeps that feasibility bound true in
-- any bucket of 11 or more teams.
create or replace function blocks_guard_cap() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare v_cap smallint;
begin
  select max(e.block_cap) into v_cap from events e where e.published;
  if (select count(*) from blocks b where b.blocker_id = new.blocker_id)
       > coalesce(v_cap, 10) then
    raise exception 'BLOCK_CAP_REACHED' using errcode = 'P0004';
  end if;
  return null;
end
$fn$;

drop trigger if exists blocks_cap_trigger on blocks;
create constraint trigger blocks_cap_trigger after insert on blocks
  deferrable initially immediate
  for each row execute function blocks_guard_cap();

-- ═════════════════════════════════════════════════════════════════════════
-- RLS HELPERS
-- ═════════════════════════════════════════════════════════════════════════
-- All SECURITY DEFINER and owned by the migration role, so a policy on
-- team_members may consult team_members without recursing through its own
-- policy. That is the only reason these exist.

create or replace function match_is_team_member(p_team uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from team_members tm
    where tm.team_id = p_team and tm.profile_id = auth.uid() and tm.left_at is null)
$$;

create or replace function match_is_captain(p_team uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from teams t where t.id = p_team and t.captain_id = auth.uid())
$$;

create or replace function match_my_team() returns uuid
language sql stable security definer set search_path = public as $$
  select tm.team_id from team_members tm
   where tm.profile_id = auth.uid() and tm.left_at is null limit 1
$$;

-- Gate 2 of 3 on browsing people at all: you may look at a list of other
-- attendees only if you captain a team that has ACTUALLY DECLARED it is
-- missing somebody. There is no general "browse all attendees" surface
-- anywhere in this product; ~500 minors are not free to read each other's
-- free text.
create or replace function match_captains_team_with_gap() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from teams t
    join team_gaps g on g.team_id = t.id
    where t.captain_id = auth.uid()
      and t.state <> 'disbanded'
      and not t.locked
      and g.seats > 0)
$$;

-- Gate 3 of 3: the list is filtered to people whose primary_role is one of
-- the roles the viewer's own teams are actually missing.
create or replace function match_roles_needed_by(p_captain uuid) returns role_tag[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct g.role), '{}'::role_tag[])
  from teams t
  join team_gaps g on g.team_id = t.id
  where t.captain_id = p_captain and t.state <> 'disbanded'
    and not t.locked and g.seats > 0
$$;

create or replace function match_excluded_with(p_other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from match_exclusions me
    where me.a = least(auth.uid(), p_other) and me.b = greatest(auth.uid(), p_other))
$$;

-- ═════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═════════════════════════════════════════════════════════════════════════
-- Baseline: nothing in this file is readable merely because the row exists
-- and the caller happens to be logged in. Every attendee-facing read is gated
-- on holding a ticket to the same event, and the tables carrying other
-- people's personal data carry no attendee-facing read at all.

alter table challenge_prefs    enable row level security;
alter table teams              enable row level security;
alter table team_gaps          enable row level security;
alter table team_members       enable row level security;
alter table link_requests      enable row level security;
alter table safety_separations enable row level security;
alter table match_runs         enable row level security;
alter table run_pool           enable row level security;
alter table run_seats          enable row level security;
alter table run_exclusions     enable row level security;
alter table run_placements     enable row level security;
alter table run_teams          enable row level security;
alter table run_exceptions     enable row level security;
alter table placement_trace    enable row level security;
alter table organiser_actions  enable row level security;

-- challenge_prefs — your ranking is YOURS. Another attendee learning that you
-- ranked the sponsor's challenge last is nobody's business, and an aggregate
-- over this table is a popularity chart of sponsors.
drop policy if exists prefs_own on challenge_prefs;
create policy prefs_own on challenge_prefs
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

drop policy if exists prefs_admin_read on challenge_prefs;
create policy prefs_admin_read on challenge_prefs
  for select using (is_admin());

-- teams — visible to confirmed attendees of the same event. Team names are
-- UGC and pass the same moderation path as a bio.
drop policy if exists teams_attendee_read on teams;
create policy teams_attendee_read on teams
  for select using (state <> 'disbanded' and attends(event_id));

drop policy if exists teams_admin_all on teams;
create policy teams_admin_all on teams
  for all using (is_admin()) with check (is_admin());

-- A captain may edit only the cosmetic and consent fields of their own team.
-- number, table_number, locked and state are organiser property, and the
-- identity trigger above enforces the first two even against an admin.
drop policy if exists teams_captain_update on teams;
create policy teams_captain_update on teams
  for update using (captain_id = auth.uid() and not locked and state <> 'disbanded')
             with check (captain_id = auth.uid() and not locked);

-- team_gaps — readable by any confirmed attendee (it is the "we need a
-- designer" badge on a team card), writable only by that team's captain.
drop policy if exists gaps_attendee_read on team_gaps;
create policy gaps_attendee_read on team_gaps
  for select using (exists (
    select 1 from teams t where t.id = team_gaps.team_id
      and t.state <> 'disbanded' and attends(t.event_id)));

drop policy if exists gaps_captain_write on team_gaps;
create policy gaps_captain_write on team_gaps
  for all using (match_is_captain(team_id)) with check (match_is_captain(team_id));

drop policy if exists gaps_admin on team_gaps;
create policy gaps_admin on team_gaps
  for all using (is_admin()) with check (is_admin());

-- team_members — a roster is visible to the people ON that roster, and to
-- organisers. NOT to every attendee: "who is on team 14" across 500 people is
-- a directory of minors by another name. Team SIZE reaches other attendees
-- through team_cards, which exposes a count and nothing else.
drop policy if exists members_own_or_teammate on team_members;
create policy members_own_or_teammate on team_members
  for select using (profile_id = auth.uid() or match_is_team_member(team_id));

drop policy if exists members_staff_read on team_members;
create policy members_staff_read on team_members
  for select using (is_staff());

drop policy if exists members_admin_write on team_members;
create policy members_admin_write on team_members
  for all using (is_admin()) with check (is_admin());
-- Attendees NEVER insert or update team_members directly. Joining and leaving
-- go through the RPCs below, so quotas, TTLs, exclusion checks and the size
-- floor are enforced server-side and in exactly one place.

-- link_requests — the two parties, and nobody else, ever. Non-pending rows
-- are visible only to their own two parties, so NO query path anywhere can
-- compute a per-person rejection tally. Nothing exposes an aggregate over
-- this table to a third party; that would be the leaderboard Guideline 1.2
-- forbids, materialised by accident.
drop policy if exists links_parties_read on link_requests;
create policy links_parties_read on link_requests
  for select using (profile_id = auth.uid() or match_is_team_member(team_id));

drop policy if exists links_admin_read on link_requests;
create policy links_admin_read on link_requests
  for select using (is_admin());
-- Deliberately NO insert/update/delete policy: every transition is an RPC.

-- safety_separations — organizer_safety only. General organisers casually
-- browsing "who hates whom" among 16-year-olds is itself a harm.
drop policy if exists separations_safety_only on safety_separations;
create policy separations_safety_only on safety_separations
  for all using (is_safety()) with check (is_safety());

-- run_* — organiser read; the matcher writes as SECURITY DEFINER and the
-- service role bypasses RLS. run_exclusions is narrower than the rest: it is
-- literally the pair list, so it is organizer_safety only.
drop policy if exists runs_admin_read on match_runs;
create policy runs_admin_read on match_runs for select using (is_admin());
drop policy if exists run_pool_admin_read on run_pool;
create policy run_pool_admin_read on run_pool for select using (is_admin());
drop policy if exists run_seats_admin_read on run_seats;
create policy run_seats_admin_read on run_seats for select using (is_admin());
drop policy if exists run_excl_safety_read on run_exclusions;
create policy run_excl_safety_read on run_exclusions for select using (is_safety());
drop policy if exists run_place_admin_read on run_placements;
create policy run_place_admin_read on run_placements for select using (is_admin());
drop policy if exists run_teams_admin_read on run_teams;
create policy run_teams_admin_read on run_teams for select using (is_admin());
drop policy if exists run_exc_admin_read on run_exceptions;
create policy run_exc_admin_read on run_exceptions for select using (is_admin());
drop policy if exists run_exc_admin_ack on run_exceptions;
create policy run_exc_admin_ack on run_exceptions
  for update using (is_admin()) with check (is_admin());

-- placement_trace — the one policy that turns a reason code into an in-app
-- "why am I on this team" line. Readable by its own subject once the run that
-- produced it is published, and by organisers.
drop policy if exists trace_own_read on placement_trace;
create policy trace_own_read on placement_trace
  for select using (
    is_admin()
    or (profile_id = auth.uid()
        and exists (select 1 from match_runs r
                     where r.id = placement_trace.run_id and r.state = 'published')));

-- organiser_actions — append-only. No update policy, no delete policy, ever.
drop policy if exists actions_read on organiser_actions;
create policy actions_read on organiser_actions
  for select using (is_admin() or is_safety());
drop policy if exists actions_insert on organiser_actions;
create policy actions_insert on organiser_actions
  for insert with check ((is_admin() or is_safety()) and actor = auth.uid());

-- ═════════════════════════════════════════════════════════════════════════
-- VIEWS ATTENDEES MAY READ
-- ═════════════════════════════════════════════════════════════════════════
-- These run with the definer's rights (security_invoker is deliberately left
-- off) because they must aggregate rows the caller cannot select directly —
-- a team's size without its roster. Every one of them therefore carries its
-- own gate in the WHERE clause, and security_barrier stops a leaky operator
-- in a caller-supplied filter from seeing rows the gate excluded.

-- team_cards — what a person browsing teams sees. A count, not a roster.
create or replace view team_cards with (security_barrier = true) as
select t.id,
       t.event_id,
       t.number,
       t.table_number,
       t.challenge_id,
       t.working_lang,
       t.name,
       t.accepts_late,
       t.state,
       (select count(*) from team_members m
         where m.team_id = t.id and m.left_at is null)::int as size,
       coalesce((select array_agg(g.role order by g.role)
                   from team_gaps g where g.team_id = t.id and g.seats > 0),
                '{}'::role_tag[]) as needed_roles
from teams t
where t.state <> 'disbanded'
  and attends(t.event_id)
  -- Blocked pairs, layer 3: a team containing somebody you have blocked, or
  -- who has blocked you, simply does not appear. The neutral failure in
  -- layer 2 is then rarely even reached.
  and not exists (
    select 1 from team_members tm
    join match_exclusions me
      on me.a = least(tm.profile_id, auth.uid())
     and me.b = greatest(tm.profile_id, auth.uid())
    where tm.team_id = t.id and tm.left_at is null);

-- attendee_cards — the ONLY surface on which one attendee sees another.
-- Gated three ways simultaneously (holds a ticket + captains a team with a
-- declared gap + filtered to the missing roles), and the target must have set
-- looking_for_team themselves.
--
-- Note what is NOT here: no invite counter, no request counter, no `starved`,
-- no aggregate of any kind, no email, no legal name, no photo. A
-- client-readable "invites received" column is a per-person popularity metric
-- that anybody holding the public anon key could select across every
-- browsable person. That is the leaderboard Guideline 1.2 forbids.
--
-- The anti-neglect ORDERING that Mechanic B needs is computed inside
-- match_browse_people() below, which returns ids in order and never returns
-- the counter it sorted on.
create or replace view attendee_cards with (security_barrier = true) as
select p.id,
       p.display_name,
       p.primary_role,
       p.secondary_role,
       -- A BAND, never the raw number. Nothing a client can read may look like
       -- a score attached to a person.
       (case p.skill_level when 1 then 'first_time' when 2 then 'been_to_a_few'
                           else 'lots' end) as experience,
       lang_class(p.languages) as lang_class,
       (select cp.challenge_id from challenge_prefs cp
         where cp.profile_id = p.id and cp.rank = 1) as first_choice_challenge,
       -- Free text appears only when bios are enabled for the event AND this
       -- one has been through moderation.
       case when p.bio_status = 'approved'
             and exists (select 1 from events e where e.id = t.event_id and e.bio_enabled)
            then p.bio end as bio
from profiles p
join tickets t on t.profile_id = p.id and t.state <> 'void'
where p.looking_for_team
  and p.wants_team
  and p.deleted_at is null
  and p.suspended_at is null
  and p.id <> auth.uid()
  and attends(t.event_id)
  and match_captains_team_with_gap()
  and p.primary_role = any (match_roles_needed_by(auth.uid()))
  and not match_excluded_with(p.id)
  and not exists (select 1 from team_members tm
                   where tm.profile_id = p.id and tm.left_at is null);

-- my_links — the sender/recipient projection. THIS is where three distinct
-- terminal outcomes collapse into one byte-identical string. A dismissal, a
-- timeout and a supersession are indistinguishable to the sender, and that is
-- both the Guideline 1.2 requirement and simply kinder to a 16-year-old.
-- seen_at is not in this view. It is recorded and never revealed.
create or replace view my_links with (security_barrier = true) as
select l.id,
       l.team_id,
       l.profile_id,
       l.direction,
       l.role_code,
       l.created_at,
       l.expires_at,
       (case when l.profile_id = auth.uid() then 'person' else 'team' end) as my_side,
       (case
          when l.state = 'pending'   then 'pending'
          when l.state = 'accepted'  then 'accepted'
          when l.state = 'withdrawn' then 'withdrawn'
          else 'closed'                       -- dismissed | expired | superseded
        end) as outcome
from link_requests l
where l.profile_id = auth.uid() or match_is_team_member(l.team_id);

-- my_team — your own roster: first names and roles, which is exactly what the
-- placard prints. No emails, no legal names, no contact details. People swap
-- contacts in person, in a supervised room.
create or replace view my_team with (security_barrier = true) as
select t.id as team_id,
       t.number,
       t.table_number,
       t.challenge_id,
       t.working_lang,
       t.name,
       t.captain_id,
       m.profile_id,
       p.display_name,
       m.role_in_team,
       m.joined_via,
       m.joined_at,
       -- "table host", never "leader".
       (m.profile_id = t.captain_id) as is_table_host
from teams t
join team_members m on m.team_id = t.id and m.left_at is null
join profiles p on p.id = m.profile_id
where match_is_team_member(t.id);

-- The card for the OTHER side of one link. attendee_cards is filtered to the
-- roles a captain is currently missing, which is right for browsing and wrong
-- for an inbox: a pending request must still render after the gap it answered
-- was filled. Gated on being a party to that exact link, and nothing else.
create or replace function match_link_card(p_link uuid)
returns table (display_name text, primary_role role_tag, secondary_role role_tag,
               experience text, lang_class lang_class_t, first_choice_challenge uuid,
               bio text)
language sql stable security definer set search_path = public as $$
  select p.display_name, p.primary_role, p.secondary_role,
         (case p.skill_level when 1 then 'first_time' when 2 then 'been_to_a_few'
                             else 'lots' end),
         lang_class(p.languages),
         (select cp.challenge_id from challenge_prefs cp
           where cp.profile_id = p.id and cp.rank = 1),
         case when p.bio_status = 'approved'
               and exists (select 1 from events e where e.id = l.event_id and e.bio_enabled)
              then p.bio end
  from link_requests l
  join profiles p on p.id = l.profile_id
  where l.id = p_link
    and (l.profile_id = auth.uid() or match_is_team_member(l.team_id))
    and p.deleted_at is null and p.suspended_at is null
$$;

-- The one ordering of people in this product, and it ranks NEGLECT, not
-- people: somebody moves DOWN this list as they receive attention, so it
-- carries no quality signal and cannot be read as a score. The counters it
-- sorts on are never returned. This function gets its own paragraph in the
-- App Review notes, because it is the single thing a reviewer could mistake
-- for a ranking and the cheapest way to survive that is to explain it first.
create or replace function match_browse_people(p_limit int default 50)
returns table (profile_id uuid)
language sql stable security definer set search_path = public as $$
  select c.id
  from attendee_cards c
  order by
    (select count(*) from link_requests l
      where l.profile_id = c.id and l.direction = 'invite' and l.state = 'pending') asc,
    (select count(*) from link_requests l
      where l.profile_id = c.id and l.direction = 'request' and l.state = 'pending') desc,
    md5(coalesce(match_my_team()::text, '') || c.id::text) asc
  limit greatest(1, least(p_limit, 200))
$$;

-- ═════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═════════════════════════════════════════════════════════════════════════
-- Supabase grants broadly by default. Take it back, then hand out exactly
-- what the client needs and nothing else.

revoke all on match_exclusions from anon, authenticated;
revoke all on safety_separations from anon, authenticated;
revoke all on run_pool, run_seats, run_exclusions, run_placements, run_teams,
              run_exceptions, match_runs from anon;
revoke all on teams, team_gaps, team_members, link_requests, challenge_prefs from anon;

grant select on team_cards, attendee_cards, my_links, my_team to authenticated;
grant select, insert, update, delete on challenge_prefs to authenticated;
grant select on teams, team_gaps, team_members, link_requests to authenticated;
grant insert, update, delete on team_gaps to authenticated;
grant update on teams to authenticated;
grant select on match_runs, run_placements, run_teams, run_exceptions,
                run_pool, run_seats, placement_trace, organiser_actions to authenticated;
grant insert on organiser_actions to authenticated;
grant update on run_exceptions to authenticated;

-- ═════════════════════════════════════════════════════════════════════════
-- MECHANIC A + B — the link machine
-- ═════════════════════════════════════════════════════════════════════════
-- Every transition is one of these functions. There are no direct client
-- writes to link_requests or team_members, so quotas, TTLs, exclusion checks
-- and the visibility projection are enforced in exactly one place.
--
-- Every failure that could betray the existence of a block, a dismissal or
-- another person's state returns the SAME neutral shape,
--     {"ok": false, "reason": "unavailable"}
-- which the client renders as "That spot is no longer available."

create or replace function match_link_ttl(p_event uuid, p_dir link_dir_t)
returns timestamptz
language sql stable security definer set search_path = public as $$
  select least(
    now() + case
      -- Phase 10, the sanctioned switch window: the SAME link machine
      -- reopens for 40 minutes after publish with a 15-minute TTL. Zero new
      -- tables, zero new state machine, zero new UI. Documented algorithmic
      -- assignments always produce unmanaged switching; suppressing it does
      -- not work, scheduling it does.
      when e.switch_window_ends_at is not null and now() < e.switch_window_ends_at
        then interval '15 minutes'
      when p_dir = 'request' then make_interval(hours => e.request_ttl_hours)
      -- An invite is shorter because it occupies one of a minor's three
      -- inbound slots, and a slow captain must not be able to park a person
      -- for two days.
      else make_interval(hours => e.invite_ttl_hours)
    end,
    coalesce(e.switch_window_ends_at, e.matching_closed_at, 'infinity'::timestamptz))
  from events e where e.id = p_event
$$;

create or replace function match_send_link(
  p_team    uuid,
  p_dir     link_dir_t,
  p_role    role_tag,
  p_profile uuid default null            -- required for 'invite', ignored for 'request'
) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  v_me     uuid := auth.uid();
  v_target uuid;
  v_team   teams%rowtype;
  v_event  events%rowtype;
  v_size   int;
  v_window text;
  v_id     uuid;
  v_exp    timestamptz;
begin
  if v_me is null then raise exception 'not signed in'; end if;

  select * into v_team from teams where id = p_team;
  if not found then return jsonb_build_object('ok', false, 'reason', 'unavailable'); end if;
  select * into v_event from events where id = v_team.event_id;

  v_target := case when p_dir = 'request' then v_me else p_profile end;
  if v_target is null then return jsonb_build_object('ok', false, 'reason', 'unavailable'); end if;

  -- Which matching window are we in? A link sent during the 40-minute switch
  -- window belongs to a separate window, so somebody may approach the same
  -- team once before matching closed and once during the switch window, and
  -- no more than that.
  v_window := case when v_event.switch_window_ends_at is not null
                    and now() < v_event.switch_window_ends_at then 'switch' else 'main' end;

  if v_event.matching_closed_at is not null and v_window = 'main' then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;

  -- Sender authorisation.
  if p_dir = 'request' then
    if not attends(v_team.event_id) then
      return jsonb_build_object('ok', false, 'reason', 'unavailable'); end if;
  else
    if v_team.captain_id is distinct from v_me then
      return jsonb_build_object('ok', false, 'reason', 'unavailable'); end if;
    -- Gate 2/3 again, on the server: you may invite only while you have a gap.
    if not exists (select 1 from team_gaps g
                   where g.team_id = p_team and g.role = p_role and g.seats > 0) then
      return jsonb_build_object('ok', false, 'reason', 'unavailable'); end if;
  end if;

  -- The target must be a complete, willing, un-teamed attendee.
  if not exists (
      select 1 from profiles p
      where p.id = v_target and p.wants_team
        and p.deleted_at is null and p.suspended_at is null)
     or not match_profile_is_complete(v_target)
     or exists (select 1 from team_members tm
                 where tm.profile_id = v_target and tm.left_at is null) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;

  -- The team must be a legitimate placement target: not locked, not
  -- disbanded, not full, and it must have DECLARED the gap. A team with no
  -- team_gaps row is not a target for anybody, by any mechanic.
  select count(*) into v_size from team_members tm
    where tm.team_id = p_team and tm.left_at is null;
  if v_team.locked or v_team.state = 'disbanded' or v_size >= v_event.max_team_size
     or not exists (select 1 from team_gaps g
                    where g.team_id = p_team and g.role = p_role and g.seats > 0) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;

  -- Blocked pairs, layer 3: never surface, never send.
  if exists (
      select 1 from team_members tm
      join match_exclusions me
        on me.a = least(tm.profile_id, v_target) and me.b = greatest(tm.profile_id, v_target)
      where tm.team_id = p_team and tm.left_at is null) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;

  -- Quotas. Three open links each way. The team's inbound ceiling is a SPAM
  -- ceiling, not a quality signal, and it is never shown to anybody.
  if p_dir = 'request' then
    if (select count(*) from link_requests l
         where l.created_by = v_me and l.state = 'pending') >= v_event.max_open_links then
      return jsonb_build_object('ok', false, 'reason', 'quota_sender');
    end if;
    if (select count(*) from link_requests l
         where l.team_id = p_team and l.direction = 'request'
           and l.state = 'pending') >= v_event.max_inbound_links then
      return jsonb_build_object('ok', false, 'reason', 'unavailable');
    end if;
  else
    if (select count(*) from link_requests l
         where l.team_id = p_team and l.direction = 'invite'
           and l.state = 'pending') >= v_event.max_open_links then
      return jsonb_build_object('ok', false, 'reason', 'quota_sender');
    end if;
    if (select count(*) from link_requests l
         where l.profile_id = v_target and l.direction = 'invite'
           and l.state = 'pending') >= v_event.max_open_links then
      return jsonb_build_object('ok', false, 'reason', 'unavailable');
    end if;
  end if;

  -- ONE APPROACH PER PAIR PER WINDOW, in either direction.
  if exists (select 1 from link_requests l
             where l.team_id = p_team and l.profile_id = v_target
               and l.window_tag = v_window) then
    return jsonb_build_object('ok', false, 'reason', 'already_approached');
  end if;

  v_exp := match_link_ttl(v_team.event_id, p_dir);

  insert into link_requests (event_id, team_id, profile_id, direction, role_code,
                             expires_at, created_by, window_tag)
  values (v_team.event_id, p_team, v_target, p_dir, p_role, v_exp, v_me, v_window)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'link_id', v_id, 'expires_at', v_exp);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'already_approached');
end
$fn$;

-- Recorded, never revealed. seen_at exists so the organiser console can nudge
-- a slow captain, and for no other reason.
create or replace function match_mark_seen(p_link uuid) returns void
language plpgsql security definer set search_path = public as $fn$
begin
  update link_requests l set seen_at = coalesce(l.seen_at, now())
   where l.id = p_link and l.state = 'pending'
     and ( (l.direction = 'invite'  and l.profile_id = auth.uid())
        or (l.direction = 'request' and match_is_captain(l.team_id)) );
end
$fn$;

create or replace function match_accept_link(p_link uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  v_me    uuid := auth.uid();
  v_l     link_requests%rowtype;
  v_team  teams%rowtype;
  v_event events%rowtype;
  v_size  int;
  v_role  role_tag;
begin
  select * into v_l from link_requests where id = p_link for update;
  if not found or v_l.state <> 'pending' or v_l.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;

  -- Only the RECIPIENT accepts: a request is accepted by the captain, an
  -- invite by the person.
  if not ( (v_l.direction = 'request' and match_is_captain(v_l.team_id))
        or (v_l.direction = 'invite'  and v_l.profile_id = v_me) ) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;

  select * into v_team  from teams  where id = v_l.team_id;
  select * into v_event from events where id = v_l.event_id;
  select count(*) into v_size from team_members tm
    where tm.team_id = v_l.team_id and tm.left_at is null;

  if v_team.locked or v_team.state = 'disbanded' or v_size >= v_event.max_team_size then
    update link_requests set state = 'superseded', resolved_at = now() where id = p_link;
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;

  -- role_in_team: the declared gap if it is still free, otherwise their own
  -- primary role. This is what gets printed on the placard, and it has to be
  -- a job. "Nea — designer" is a job; a name alone is a guest.
  select case when exists (select 1 from team_members tm
                            where tm.team_id = v_l.team_id and tm.left_at is null
                              and tm.role_in_team = v_l.role_code)
              then p.primary_role else v_l.role_code end
    into v_role from profiles p where p.id = v_l.profile_id;

  begin
    insert into team_members (team_id, profile_id, role_in_team, joined_via)
    values (v_l.team_id, v_l.profile_id, v_role,
            (case when v_l.direction = 'request' then 'request' else 'invite' end)::join_via_t);

    -- Force the DEFERRED exclusion guard to fire HERE, inside this block, so
    -- it can be caught and answered neutrally. Left deferred it would fire at
    -- COMMIT, outside any handler, and the client would see a raw database
    -- error that leaks the existence of a block.
    set constraints tm_exclusion_guard immediate;
  exception
    when unique_violation then
      -- one_active_team_per_person. Two invites accepted in the same second:
      -- one wins, the other gets the neutral string.
      update link_requests set state = 'superseded', resolved_at = now() where id = p_link;
      return jsonb_build_object('ok', false, 'reason', 'unavailable');
    when sqlstate 'P0002' then
      update link_requests set state = 'superseded', resolved_at = now() where id = p_link;
      return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end;

  update link_requests
     set state = 'accepted', resolved_at = now(), resolved_by = v_me
   where id = p_link;

  -- Consume the declared seat.
  delete from team_gaps g
   where g.team_id = v_l.team_id and g.role = v_l.role_code and g.seats <= 1;
  update team_gaps g set seats = g.seats - 1
   where g.team_id = v_l.team_id and g.role = v_l.role_code;

  -- Every other live link involving the joiner is now moot, in both
  -- directions, and closes SILENTLY as 'superseded'.
  update link_requests l set state = 'superseded', resolved_at = now()
   where l.profile_id = v_l.profile_id and l.state = 'pending' and l.id <> p_link;

  -- If that filled the team, close its remaining inbound links too.
  if v_size + 1 >= v_event.max_team_size or not exists (
       select 1 from team_gaps g where g.team_id = v_l.team_id and g.seats > 0) then
    update link_requests l set state = 'superseded', resolved_at = now()
     where l.team_id = v_l.team_id and l.state = 'pending';
  end if;

  if v_team.state = 'forming' and v_size + 1 >= v_event.min_team_size then
    update teams set state = 'active' where id = v_l.team_id;
  end if;

  return jsonb_build_object('ok', true, 'team_id', v_l.team_id);
end
$fn$;

-- "Not right now" / "Not this one". One tap, silent: no notification, no
-- counter, no history the other party can ever read. The captain is protected
-- symmetrically — a dismissed invite reads to them exactly like a timed-out
-- one. Captains are 16 too.
create or replace function match_dismiss_link(p_link uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_l link_requests%rowtype;
begin
  select * into v_l from link_requests where id = p_link;
  if not found or v_l.state <> 'pending' then
    return jsonb_build_object('ok', true);        -- idempotent, and says nothing
  end if;
  if not ( (v_l.direction = 'request' and match_is_captain(v_l.team_id))
        or (v_l.direction = 'invite'  and v_l.profile_id = auth.uid()) ) then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end if;
  update link_requests
     set state = 'dismissed', resolved_at = now(), resolved_by = auth.uid()
   where id = p_link;
  return jsonb_build_object('ok', true);
end
$fn$;

create or replace function match_withdraw_link(p_link uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
begin
  -- Withdrawing returns the quota and does NOT increment starved: you chose
  -- to stop, you were not ignored.
  update link_requests l
     set state = 'withdrawn', resolved_at = now(), resolved_by = auth.uid()
   where l.id = p_link and l.state = 'pending' and l.created_by = auth.uid();
  return jsonb_build_object('ok', true);
end
$fn$;

-- Cron, every minute. Also called by match_close_matching().
create or replace function match_expire_links() returns int
language plpgsql security definer set search_path = public as $fn$
declare v_n int;
begin
  with done as (
    update link_requests l set state = 'expired', resolved_at = now()
     where l.state = 'pending' and l.expires_at <= now()
    returning 1 as one)
  select count(*) into v_n from done;
  return v_n;
end
$fn$;

-- THE BUTTON. Not a timestamp. The opening ceremony will overrun and a cron
-- job cannot know that the mayor is still talking. Five lines, and the
-- cheapest high-value decision in the whole design.
create or replace function match_close_matching(p_event uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_expired int;
begin
  if not is_admin() then raise exception 'organiser only'; end if;

  update events set matching_closed_at = now()
   where id = p_event and matching_closed_at is null;

  update link_requests l set expires_at = least(l.expires_at, now())
   where l.event_id = p_event and l.state = 'pending';

  v_expired := match_expire_links();   -- this is also what computes `starved`

  insert into organiser_actions (event_id, actor, action, reason)
  values (p_event, auth.uid(), 'close_matching', 'organiser closed the matching window');

  return jsonb_build_object('ok', true, 'expired', v_expired);
end
$fn$;

-- Create a team. The founder is its captain and its first member, and the
-- team starts with NO declared gaps: wanting a fourth person is an
-- affirmative act, not a default.
create or replace function match_create_team(
  p_event uuid, p_challenge uuid, p_lang work_lang_t, p_name text default null
) returns uuid
language plpgsql security definer set search_path = public as $fn$
declare v_id uuid; v_role role_tag;
begin
  if not attends(p_event) then raise exception 'ticket required'; end if;
  if exists (select 1 from team_members tm
              where tm.profile_id = auth.uid() and tm.left_at is null) then
    raise exception 'ALREADY_ON_A_TEAM' using errcode = 'P0008';
  end if;
  select p.primary_role into v_role from profiles p where p.id = auth.uid();
  if v_role is null then
    raise exception 'PROFILE_INCOMPLETE' using errcode = 'P0003';
  end if;

  insert into teams (event_id, challenge_id, working_lang, name, captain_id, origin)
  values (p_event, p_challenge, p_lang, p_name, auth.uid(), 'self_formed')
  returning id into v_id;

  insert into team_members (team_id, profile_id, role_in_team, joined_via)
  values (v_id, auth.uid(), v_role, 'founder');

  return v_id;
end
$fn$;

-- Leaving is GATED: you may leave only if your team stays at or above the
-- minimum. Otherwise it becomes an organiser item with three named options —
-- merge with another small team in the same challenge, absorb a late arrival,
-- or continue as a pair with a logged override. The system never
-- auto-dissolves a working team mid-event.
create or replace function match_leave_team(p_reason text default 'self') returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_team uuid; v_size int; v_min int; v_event uuid;
begin
  select tm.team_id into v_team from team_members tm
   where tm.profile_id = auth.uid() and tm.left_at is null;
  if v_team is null then return jsonb_build_object('ok', true); end if;

  select t.event_id, e.min_team_size into v_event, v_min
    from teams t join events e on e.id = t.event_id where t.id = v_team;
  select count(*) into v_size from team_members tm
   where tm.team_id = v_team and tm.left_at is null;

  if v_size - 1 < v_min and v_size > 1 then
    insert into organiser_actions (event_id, actor, action, target_profile, target_team,
                                   reason, forced)
    values (v_event, auth.uid(), 'departure_would_break_team', auth.uid(), v_team,
            'attendee asked to leave a team that would drop below the minimum', false);
    return jsonb_build_object('ok', false, 'reason', 'organiser_needed');
  end if;

  update team_members tm set left_at = now(), left_reason = p_reason
   where tm.team_id = v_team and tm.profile_id = auth.uid() and tm.left_at is null;

  -- A captainless team cannot exist: captaincy transfers to the
  -- earliest-joined remaining member.
  update teams t set captain_id = (
      select tm.profile_id from team_members tm
       where tm.team_id = v_team and tm.left_at is null
       order by tm.joined_at asc, tm.profile_id::text asc limit 1)
   where t.id = v_team and t.captain_id = auth.uid();

  update teams t set state = 'disbanded', disbanded_at = now(),
                     disbanded_reason = 'collapsed_below_min'
   where t.id = v_team
     and not exists (select 1 from team_members tm
                      where tm.team_id = v_team and tm.left_at is null);

  return jsonb_build_object('ok', true);
end
$fn$;

-- Called by account deletion so the seat is freed and the team's viability is
-- re-checked. 010_core's delete_my_account() should call this.
create or replace function match_release_seat(p_profile uuid) returns void
language plpgsql security definer set search_path = public as $fn$
begin
  update team_members tm set left_at = now(), left_reason = 'self'
   where tm.profile_id = p_profile and tm.left_at is null;
  update link_requests l set state = 'superseded', resolved_at = now()
   where l.state = 'pending' and (l.profile_id = p_profile or l.created_by = p_profile);
  update teams t set captain_id = (
      select tm.profile_id from team_members tm
       where tm.team_id = t.id and tm.left_at is null
       order by tm.joined_at asc, tm.profile_id::text asc limit 1)
   where t.captain_id = p_profile;
  delete from challenge_prefs cp where cp.profile_id = p_profile;
end
$fn$;

revoke all on function match_send_link(uuid, link_dir_t, role_tag, uuid) from public;
revoke all on function match_accept_link(uuid)   from public;
revoke all on function match_dismiss_link(uuid)  from public;
revoke all on function match_withdraw_link(uuid) from public;
revoke all on function match_mark_seen(uuid)     from public;
revoke all on function match_create_team(uuid, uuid, work_lang_t, text) from public;
revoke all on function match_leave_team(text)    from public;
revoke all on function match_browse_people(int)  from public;
revoke all on function match_link_card(uuid)     from public;
revoke all on function match_close_matching(uuid) from public;
revoke all on function match_expire_links()      from public;

grant execute on function match_send_link(uuid, link_dir_t, role_tag, uuid) to authenticated;
grant execute on function match_accept_link(uuid)   to authenticated;
grant execute on function match_dismiss_link(uuid)  to authenticated;
grant execute on function match_withdraw_link(uuid) to authenticated;
grant execute on function match_mark_seen(uuid)     to authenticated;
grant execute on function match_create_team(uuid, uuid, work_lang_t, text) to authenticated;
grant execute on function match_leave_team(text)    to authenticated;
grant execute on function match_browse_people(int)  to authenticated;
grant execute on function match_link_card(uuid)     to authenticated;
grant execute on function match_close_matching(uuid) to authenticated;

-- ═════════════════════════════════════════════════════════════════════════
-- MECHANIC C — the auto-assign safety net
-- ═════════════════════════════════════════════════════════════════════════
-- match_auto_assign() computes a complete proposed assignment and RETURNS it.
--
--   p_dry = true   compute and return, and WRITE NOTHING AT ALL — not even a
--                  match_runs row. This is the rehearsal path and the CI path.
--   p_dry = false  additionally freeze the inputs and the proposal into the
--                  run_* tables under p_run_id, state 'previewed'. It still
--                  does not touch teams or team_members: publishing is a
--                  separate, explicit, typed-confirmation act (publish_run).
--
-- DETERMINISTIC: identical (salt, snapshot) ⇒ identical output, byte for
-- byte, including which bucket dissolves and which side a bilingual lands on.
-- Every ORDER BY terminates in md5(unit_id || salt) or in a text cast of a
-- uuid. Postgres guarantees no ordering without a total order.
--
-- IDEMPOTENT: re-running with the same p_run_id rewrites that run's rows from
-- scratch; a published run refuses to be recomputed at all.
--
-- RESPECTS BLOCKED PAIRS: exclusions are snapshotted once, are hard rule (a)
-- of the pick predicate, and are re-asserted across the whole proposal before
-- publish. A pair is NEVER seated together to keep the coverage promise; the
-- ladder ends at a named exception and a human seating one person.
--
-- It reads NO free text — not bio, not team name, not display_name, not
-- full_name, not email. That is why a bio held in moderation costs matching
-- exactly nothing, and it is why bios can ship disabled.
--
-- One call per transaction: it builds ON COMMIT DROP temp tables.

create or replace function match_auto_assign(
  p_event   uuid,
  p_mode    run_mode_t default 'full',
  p_dry     boolean    default true,
  p_run_id  uuid       default null,
  p_salt    text       default null,
  p_only    uuid[]     default null,     -- mode 'single': restrict the pool
  p_basis   text       default null      -- 'checked_in' (default) | 'registered'
) returns table (
  run_id        uuid,
  bucket_key    text,
  team_key      text,
  team_id       uuid,
  is_new_team   boolean,
  team_size     int,
  challenge_id  uuid,
  working_lang  work_lang_t,
  seq           int,
  profile_id    uuid,
  proposed_role role_tag,
  reason_code   text,
  flags         text[]
)
language plpgsql security definer set search_path = public
as $ma$
#variable_conflict use_column
declare
  v_e      events%rowtype;
  v_run    uuid;
  v_salt   text;
  v_basis  text;
  v_state  run_state_t;
  v_tsize int; v_L int; v_umax int; v_MINB int;
  v_t      record;
  v_snap   timestamptz := now();
  v_rec    record;
  v_b      record;
  v_u      record;
  v_pm     record;
  v_unit   record;
  v_pick   uuid;
  v_usize  int;
  v_wanted role_tag;
  v_iter   int;
  v_pass   int;
  v_k int; v_q int; v_r int;
  v_seqno int; v_round int; v_pos int; v_base int; v_dir int; v_ix int; v_i int;
  v_progress boolean;
  v_n int; v_g int; v_m int; v_acc int;
  v_role   role_tag;
  v_reason text;
  v_target text;
  v_metrics jsonb;
begin
  select * into v_e from events e where e.id = p_event;
  if not found then
    raise exception 'MATCH_NO_EVENT: %', p_event using errcode = 'P0005';
  end if;
  v_tsize := v_e.target_team_size; v_L := v_e.min_team_size;
  v_umax := v_e.max_team_size;    v_MINB := v_e.min_bucket_size;

  -- Phase 0.1 — one run at a time, ever. Two organisers pressing the button
  -- at the same moment serialise here; the second then fails the staleness
  -- check in publish_run and is offered a re-run.
  perform pg_advisory_xact_lock(hashtext(p_event::text));

  if p_run_id is not null then
    select r.salt, r.state, r.roster_basis into v_salt, v_state, v_basis
      from match_runs r where r.id = p_run_id;
    if found and v_state = 'published' then
      raise exception 'MATCH_RUN_PUBLISHED: % is already published; start a new run', p_run_id
        using errcode = 'P0006';
    end if;
  end if;
  v_run   := coalesce(p_run_id, gen_random_uuid());
  v_salt  := coalesce(v_salt, p_salt, replace(gen_random_uuid()::text,'-',''));
  v_basis := coalesce(p_basis, v_basis,
                      case when p_mode = 'dry' then 'registered' else 'checked_in' end);

  -- ───────────────────────────────────────────────────────────────────────
  -- Phase 0.2 — snapshot. Every later phase reads ONLY these temp tables.
  -- ───────────────────────────────────────────────────────────────────────
  create temp table tmp_ma_teamsize on commit drop as
  select t.id as team_id, t.challenge_id, t.working_lang, t.locked, t.number,
         t.accepts_late, t.state,
         count(m.profile_id) filter (where m.left_at is null)::int as sz,
         coalesce(bool_or(m.pinned and m.left_at is null), false) as has_pinned
  from teams t
  left join team_members m on m.team_id = t.id
  where t.event_id = p_event and t.state <> 'disbanded'
  group by t.id, t.challenge_id, t.working_lang, t.locked, t.number, t.accepts_late, t.state;

  -- Phase 1.1/1.2 — triage. A team below the minimum is NON_VIABLE: it
  -- dissolves and its members re-enter the pool. Two exceptions, both
  -- deliberate: a LOCKED team is never touched, and in repair mode a PAIR
  -- that has already been notified and has been building for eight hours is
  -- not the same object as a pair at 09:00, so it is left alone and flagged.
  create temp table tmp_ma_nonviable on commit drop as
  select ts.team_id, ts.sz
  from tmp_ma_teamsize ts
  where not ts.locked
    and ts.sz < v_L
    and not (p_mode = 'repair' and ts.has_pinned and ts.sz = 2);

  -- The pool. `tickets.state = 'admitted'` is THE hard gate. A free event for
  -- 15-19 year olds should plan for a 20-50% no-show rate; assigning from the
  -- registration list guarantees half-empty teams, and check-in removes the
  -- no-show variable rather than estimating it.
  create temp table tmp_ma_person on commit drop as
  select p.id as profile_id,
         p.primary_role,
         p.secondary_role,
         coalesce(p.skill_level, 1)::int as expband,
         lang_class(p.languages) as lc,
         p.starved::int as starved,
         tm.team_id as from_team,
         coalesce(tm.pinned, false) as was_pinned,
         p.id as unit_id,               -- overwritten below for collapsed pairs
         null::text as bucket_key
  from profiles p
  join tickets tk on tk.profile_id = p.id and tk.event_id = p_event
  left join team_members tm on tm.profile_id = p.id and tm.left_at is null
  where p.deleted_at is null
    and p.suspended_at is null
    and p.wants_team
    and p.primary_role is not null
    and p.skill_level is not null
    and lang_class(p.languages) is not null
    and (case when v_basis = 'checked_in' then tk.state = 'admitted'
              else tk.state <> 'void' end)
    and (select count(*) from challenge_prefs cp where cp.profile_id = p.id) = 3
    and (tm.team_id is null or tm.team_id in (select n.team_id from tmp_ma_nonviable n))
    and (p_only is null or p.id = any (p_only))
    and (p_mode <> 'single' or p.wants_late_seat);

  -- Exclusions, snapshotted ONCE. A block filed at 09:02 cannot make the
  -- publish differ from the preview the organiser approved at 09:01.
  create temp table tmp_ma_excl on commit drop as
  select me.a, me.b from match_exclusions me;
  create index on tmp_ma_excl (a, b);

  -- Named exceptions. Every row here BLOCKS PUBLISH until an organiser either
  -- seats that person by hand or acknowledges it with a written note.
  create temp table tmp_ma_exc (
    profile_id       uuid not null,
    kind             text not null,
    detail           text,
    suggested_action text,
    primary key (profile_id, kind)
  ) on commit drop;

  -- Phase 1.2 — collapsed PAIRS are one unit. Two people who already chose
  -- each other and then lost their teammates are the case that actually
  -- occurs on the day, and they are worth twenty lines. There are NO
  -- user-declared pairs in v1: every ordering, capacity check and pick would
  -- become size-aware, and a mixed-language declared pair is unseatable in a
  -- language-partitioned bucket by construction.
  create temp table tmp_ma_pair on commit drop as
  select pp.from_team as team_id, min(pp.profile_id::text)::uuid as unit_id
  from tmp_ma_person pp
  join tmp_ma_nonviable n on n.team_id = pp.from_team
  group by pp.from_team
  having count(*) = 2
     -- fi_only + en_only in one unit is FORBIDDEN AT CREATION: such a unit is
     -- unseatable in any language bucket. The pair splits into singletons.
     and not (bool_or(pp.lc = 'fi_only') and bool_or(pp.lc = 'en_only'))
     -- and a unit never contains an exclusion.
     and not exists (
       select 1 from tmp_ma_person q1
       join tmp_ma_person q2 on q2.from_team = q1.from_team and q2.profile_id > q1.profile_id
       join tmp_ma_excl x on x.a = least(q1.profile_id, q2.profile_id)
                         and x.b = greatest(q1.profile_id, q2.profile_id)
       where q1.from_team = pp.from_team);

  update tmp_ma_person pp
     set unit_id = pr.unit_id
    from tmp_ma_pair pr
   where pr.team_id = pp.from_team;

  create temp table tmp_ma_unit on commit drop as
  select pp.unit_id,
         count(*)::int as unit_size,
         max(pp.starved)::int as starved,
         max(pp.expband)::int as expband,
         (case when bool_or(pp.lc = 'fi_only') then 'fi_only'
               when bool_or(pp.lc = 'en_only') then 'en_only'
               else 'both' end)::lang_class_t as lc,
         md5(pp.unit_id::text || v_salt) as h,
         null::uuid as pref1, null::uuid as pref2, null::uuid as pref3,
         1::int as cur_rank,
         null::text as bucket_key,
         null::text as move_reason,
         0::int as rarity_rank,
         null::int as seq,
         false as placed
  from tmp_ma_person pp
  group by pp.unit_id;

  create index on tmp_ma_unit (bucket_key);

  -- Unit preferences are a Borda sum over the unit's members (3/2/1 for ranks
  -- 1/2/3). For a singleton that is just their own ranking. A challenge the
  -- sponsor withdrew at 08:00 drops out here.
  create temp table tmp_ma_unitpref on commit drop as
  select pp.unit_id,
         cp.challenge_id,
         sum(4 - cp.rank)::int as borda,
         row_number() over (
           partition by pp.unit_id
           order by sum(4 - cp.rank) desc, min(c.ordinal), min(cp.challenge_id::text)
         )::int as prank
  from tmp_ma_person pp
  join challenge_prefs cp on cp.profile_id = pp.profile_id
  join challenges c on c.id = cp.challenge_id
  where c.state <> 'withdrawn'
  group by pp.unit_id, cp.challenge_id;

  update tmp_ma_unit u set
    pref1 = (select x.challenge_id from tmp_ma_unitpref x
              where x.unit_id = u.unit_id and x.prank = 1),
    pref2 = (select x.challenge_id from tmp_ma_unitpref x
              where x.unit_id = u.unit_id and x.prank = 2),
    pref3 = (select x.challenge_id from tmp_ma_unitpref x
              where x.unit_id = u.unit_id and x.prank = 3)
   where true;   -- whole-table recompute, explicit for the safeupdate guard

  -- ───────────────────────────────────────────────────────────────────────
  -- Phase 2 — bucketing: challenge × working language
  -- ───────────────────────────────────────────────────────────────────────
  -- Language is a PARTITION, not a tie-break. A tie-break fires only when
  -- everything else is equal, which is almost never; and a Finnish-only
  -- 16-year-old dealt onto an all-English table is a TOTAL failure — worse
  -- than any role duplicate, worse than a third-choice challenge. But note
  -- the asymmetry: the harm is the ISOLATION of one person, not mixing. So we
  -- partition on isolation only, and bilinguals are a deliberate flex pool
  -- that crosses the divide. Mixing still happens; isolation does not.
  create temp table tmp_ma_bucket (
    bucket_key   text primary key,
    challenge_id uuid not null,
    work_lang    work_lang_t not null,
    ordinal      int not null,
    n            int not null default 0,
    g            int not null default 0,
    m            int not null default 0,
    k            int not null default 0,
    dissolved    boolean not null default false,
    sized        boolean not null default false
  ) on commit drop;

  -- A bucket exists for a (challenge, language) if any monolingual unit of
  -- that language ranks that challenge first...
  insert into tmp_ma_bucket (bucket_key, challenge_id, work_lang, ordinal)
  select distinct u.pref1::text || ':' || (case when u.lc = 'fi_only' then 'fi' else 'en' end),
         u.pref1,
         (case when u.lc = 'fi_only' then 'fi' else 'en' end)::work_lang_t,
         coalesce(c.ordinal, 0)
  from tmp_ma_unit u
  join challenges c on c.id = u.pref1
  where u.lc <> 'both' and u.pref1 is not null
  on conflict do nothing;

  -- ...or an existing OPEN team already works in it...
  insert into tmp_ma_bucket (bucket_key, challenge_id, work_lang, ordinal)
  select distinct ts.challenge_id::text || ':' || ts.working_lang::text,
         ts.challenge_id, ts.working_lang, coalesce(c.ordinal, 0)
  from tmp_ma_teamsize ts
  join challenges c on c.id = ts.challenge_id
  where ts.challenge_id is not null and ts.working_lang is not null
    and not ts.locked and ts.sz >= v_L and ts.sz < v_umax
    and exists (select 1 from team_gaps g where g.team_id = ts.team_id and g.seats > 0)
  on conflict do nothing;

  -- ...or, if a challenge is ranked first ONLY by bilinguals, it still gets
  -- exactly one bucket. Default 'fi': every member of such a bucket speaks
  -- both, the event is in Finland, and a Finnish-working team can still talk
  -- to English-speaking mentors and judges through any of them.
  insert into tmp_ma_bucket (bucket_key, challenge_id, work_lang, ordinal)
  select distinct u.pref1::text || ':fi', u.pref1, 'fi'::work_lang_t, coalesce(c.ordinal, 0)
  from tmp_ma_unit u
  join challenges c on c.id = u.pref1
  where u.pref1 is not null
    and not exists (select 1 from tmp_ma_bucket b where b.challenge_id = u.pref1)
  on conflict do nothing;

  -- Place the monolinguals.
  update tmp_ma_unit u
     set bucket_key = u.pref1::text || ':'
                      || (case when u.lc = 'fi_only' then 'fi' else 'en' end)
   where u.lc <> 'both' and u.pref1 is not null;

  update tmp_ma_bucket b
     set n = coalesce((select sum(u.unit_size) from tmp_ma_unit u
                        where u.bucket_key = b.bucket_key), 0)
   where true;   -- whole-table recompute; explicit for the safeupdate guard

  -- ── Phase 2.3 — FLEX allocation ──────────────────────────────────────
  -- This runs BEFORE the merge, and that ordering is the entire point. If
  -- bilinguals sat in a holding pool while the merge dissolved undersized
  -- buckets, the rescue mechanism could never rescue: a challenge with 2
  -- English-only speakers and 40 bilinguals would dissolve its English side
  -- while 40 people who could have saved it did nothing. One block ordering,
  -- and it is the difference between a live mechanism and a dead one.
  for v_u in
    select u.unit_id, u.unit_size, u.pref1, u.pref2, u.pref3
    from tmp_ma_unit u
    where u.lc = 'both' and u.bucket_key is null
    order by u.starved desc, u.unit_size desc, u.expband desc, u.h
  loop
    -- deficit = (how far below the viable floor) * 1000 + (seats needed to
    -- round the bucket up to a whole multiple of the target size).
    select b.bucket_key,
           greatest(0, v_L - b.n) * 1000 + ((v_tsize - (b.n % v_tsize)) % v_tsize) as deficit
      into v_b
    from tmp_ma_bucket b
    where not b.dissolved
      and b.challenge_id in (v_u.pref1, v_u.pref2, v_u.pref3)
    order by (greatest(0, v_L - b.n) * 1000 + ((v_tsize - (b.n % v_tsize)) % v_tsize)) desc,
             b.n asc, b.ordinal asc, b.work_lang asc, b.bucket_key asc
    limit 1;

    if not found then
      continue;    -- no bucket in any of their three choices yet
    end if;

    if v_b.deficit = 0 then
      -- Nothing left to rescue: leftover FLEX units go to their
      -- highest-ranked challenge.
      select b.bucket_key into v_target
      from tmp_ma_bucket b
      join tmp_ma_unitpref up on up.challenge_id = b.challenge_id and up.unit_id = v_u.unit_id
      where not b.dissolved
      order by up.prank asc, b.n asc, b.ordinal asc, b.work_lang asc, b.bucket_key asc
      limit 1;
    else
      v_target := v_b.bucket_key;
    end if;

    if v_target is null then continue; end if;

    update tmp_ma_unit u
       set bucket_key = v_target,
           move_reason = case when v_b.deficit >= 1000 then 'bilingual_rescue'
                              else u.move_reason end
     where u.unit_id = v_u.unit_id;
    update tmp_ma_bucket b set n = b.n + v_u.unit_size where b.bucket_key = v_target;
  end loop;

  -- ── Phase 2.4 — capacity ceiling ─────────────────────────────────────
  -- One challenge drawing 41% of first choices is normal, not an anomaly.
  -- Spill the lowest-margin units to their next choice, and never move a
  -- rank-1 unit while a rank-3 unit is still sitting in the bucket.
  for v_rec in
    select c.id as challenge_id, c.max_teams
    from challenges c
    where c.event_id = p_event and c.max_teams is not null
    order by c.ordinal, c.id::text
  loop
    v_iter := 0;
    loop
      v_iter := v_iter + 1;
      exit when v_iter > 500;
      select coalesce(sum(b.n), 0) into v_n
        from tmp_ma_bucket b
       where b.challenge_id = v_rec.challenge_id and not b.dissolved;
      exit when v_n <= v_rec.max_teams * v_umax;

      select u.unit_id, u.unit_size, u.bucket_key, u.cur_rank, u.lc,
             (select up2.challenge_id from tmp_ma_unitpref up2
               where up2.unit_id = u.unit_id and up2.prank = u.cur_rank + 1) as next_challenge
        into v_u
      from tmp_ma_unit u
      join tmp_ma_bucket b on b.bucket_key = u.bucket_key
      where b.challenge_id = v_rec.challenge_id and not b.dissolved and u.cur_rank < 3
      order by u.cur_rank desc,
               (coalesce((select up1.borda from tmp_ma_unitpref up1
                           where up1.unit_id = u.unit_id and up1.prank = u.cur_rank), 0)
                - coalesce((select up2.borda from tmp_ma_unitpref up2
                             where up2.unit_id = u.unit_id and up2.prank = u.cur_rank + 1), 0)
               ) asc,
               u.unit_size asc, u.h
      limit 1;
      exit when not found or v_u.next_challenge is null;

      select b.bucket_key into v_target
      from tmp_ma_bucket b
      join tmp_ma_bucket src on src.bucket_key = v_u.bucket_key
      where b.challenge_id = v_u.next_challenge and not b.dissolved
        and (b.work_lang = src.work_lang or v_u.lc = 'both')
      order by (b.work_lang = src.work_lang) desc, b.n asc, b.ordinal asc, b.bucket_key asc
      limit 1;
      exit when v_target is null;

      update tmp_ma_bucket b set n = b.n - v_u.unit_size where b.bucket_key = v_u.bucket_key;
      update tmp_ma_bucket b set n = b.n + v_u.unit_size where b.bucket_key = v_target;
      update tmp_ma_unit u
         set bucket_key = v_target,
             cur_rank = u.cur_rank + 1,
             move_reason = 'challenge_over_capacity_moved_to_choice_' || (u.cur_rank + 1)::text
       where u.unit_id = v_u.unit_id;
    end loop;
  end loop;

  -- ── Phase 2.5 — undersized bucket merge ──────────────────────────────
  -- The bucket count strictly decreases every iteration, so this terminates
  -- on its own. The iteration cap is a seatbelt, not the termination
  -- argument, and when it fires it writes named exceptions rather than
  -- spinning or falling through silently.
  v_iter := 0;
  loop
    v_iter := v_iter + 1;
    if v_iter > (select count(*) + 1 from tmp_ma_bucket) then
      insert into tmp_ma_exc (profile_id, kind, detail, suggested_action)
      select pp.profile_id, 'merge_loop_cap',
             'the undersized-bucket merge hit its iteration cap',
             'Seat manually, or re-run with a smaller min_bucket_size'
      from tmp_ma_person pp
      join tmp_ma_unit u on u.unit_id = pp.unit_id
      join tmp_ma_bucket b on b.bucket_key = u.bucket_key
      where not b.dissolved and b.n < v_MINB
      on conflict do nothing;
      exit;
    end if;

    select b.bucket_key, b.work_lang, b.n into v_b
    from tmp_ma_bucket b
    where not b.dissolved and b.n > 0 and b.n < v_MINB
    order by b.n asc, b.ordinal asc, b.work_lang asc, b.bucket_key asc
    limit 1;
    exit when not found;

    -- If this is the last bucket standing there is nowhere to merge to, and a
    -- bucket of 4 still forms one perfectly good team. Leave it alone.
    exit when (select count(*) from tmp_ma_bucket b2
                where not b2.dissolved and b2.n > 0) <= 1;

    for v_u in
      select u.unit_id, u.unit_size, u.lc, u.cur_rank
      from tmp_ma_unit u where u.bucket_key = v_b.bucket_key
      order by u.h
    loop
      -- Next ranked challenge with the SAME working language...
      select b.bucket_key into v_target
      from tmp_ma_bucket b
      join tmp_ma_unitpref up on up.challenge_id = b.challenge_id and up.unit_id = v_u.unit_id
      where not b.dissolved and b.bucket_key <> v_b.bucket_key
        and (b.work_lang = v_b.work_lang or v_u.lc = 'both')
      order by (b.work_lang = v_b.work_lang) desc, up.prank asc, b.n desc,
               b.ordinal asc, b.bucket_key asc
      limit 1;

      if v_target is null then
        -- ...else the largest surviving bucket in their language...
        select b.bucket_key into v_target
        from tmp_ma_bucket b
        where not b.dissolved and b.bucket_key <> v_b.bucket_key
          and (b.work_lang = v_b.work_lang or v_u.lc = 'both')
        order by b.n desc, b.ordinal asc, b.bucket_key asc
        limit 1;
        if v_target is not null then
          update tmp_ma_unit u set move_reason = 'no_ranked_challenge_available'
           where u.unit_id = v_u.unit_id;
        end if;
      else
        update tmp_ma_unit u
           set move_reason = coalesce(u.move_reason,
                 'bucket_merged_moved_to_choice_' || least(u.cur_rank + 1, 3)::text),
               cur_rank = least(u.cur_rank + 1, 3)
         where u.unit_id = v_u.unit_id;
      end if;

      if v_target is null then
        -- ...else this is the lone-monolingual case, and it ends at a human.
        insert into tmp_ma_exc (profile_id, kind, detail, suggested_action)
        select pp.profile_id, 'no_language_bucket',
               'no surviving bucket in this attendee''s working language',
               'Seat manually, or pair with a bilingual team'
        from tmp_ma_person pp where pp.unit_id = v_u.unit_id
        on conflict do nothing;
        update tmp_ma_unit u set bucket_key = null where u.unit_id = v_u.unit_id;
      else
        update tmp_ma_unit u set bucket_key = v_target where u.unit_id = v_u.unit_id;
        update tmp_ma_bucket b set n = b.n + v_u.unit_size where b.bucket_key = v_target;
      end if;
    end loop;

    update tmp_ma_bucket b set dissolved = true, n = 0 where b.bucket_key = v_b.bucket_key;
  end loop;

  -- ───────────────────────────────────────────────────────────────────────
  -- Phase 3 — team count and sizes
  -- ───────────────────────────────────────────────────────────────────────

  create temp table tmp_ma_team (
    team_key      text primary key,
    bucket_key    text not null,
    existing_team uuid,
    is_new        boolean not null,
    cap           int not null,
    filled        int not null default 0,
    ord           int not null,
    work_lang     work_lang_t not null,
    target_size   int not null default 0
  ) on commit drop;

  create temp table tmp_ma_seat (
    team_key    text not null,
    seat_ix     int  not null,
    wanted_role role_tag,
    used        boolean not null default false,
    primary key (team_key, seat_ix)
  ) on commit drop;

  create temp table tmp_ma_tmember (
    team_key   text not null,
    profile_id uuid not null,
    role       role_tag not null,
    primary key (team_key, profile_id)
  ) on commit drop;

  create temp table tmp_ma_place (
    profile_id    uuid primary key,
    team_key      text not null,
    seq           int  not null,
    role          role_tag not null,
    reason_code   text not null,
    flags         text[] not null default '{}',
    is_move       boolean not null default false,
    was_pinned    boolean not null default false,
    previous_team uuid
  ) on commit drop;

  -- Existing teams that declared a gap, expanded one row per gap seat and
  -- capped at U - current size.
  create temp table tmp_ma_openteam on commit drop as
  select ts.team_id, ts.sz, ts.number, b.bucket_key, b.work_lang,
         least(sum(g.seats)::int, v_umax - ts.sz) as open_seats
  from tmp_ma_teamsize ts
  join team_gaps g on g.team_id = ts.team_id and g.seats > 0
  join tmp_ma_bucket b
    on b.challenge_id = ts.challenge_id and b.work_lang = ts.working_lang and not b.dissolved
  where not ts.locked and ts.sz >= v_L and ts.sz < v_umax
    and (p_mode <> 'single' or ts.accepts_late)
  group by ts.team_id, ts.sz, ts.number, b.bucket_key, b.work_lang;

  -- Two passes. Pass 1 only MOVES the 1-or-2-person remainders that cannot be
  -- rescued by holding back a gap seat; pass 2 does all the arithmetic and
  -- mints the teams. Doing both in one pass would size a bucket before the
  -- remainder that is about to arrive in it has arrived.
  for v_pass in 1..2 loop

    update tmp_ma_bucket b
       set n = coalesce((select sum(u.unit_size) from tmp_ma_unit u
                          where u.bucket_key = b.bucket_key), 0)
     where not b.dissolved;

    for v_b in
      select b.bucket_key, b.challenge_id, b.work_lang, b.n
      from tmp_ma_bucket b
      where not b.dissolved and b.n > 0 and not b.sized
      order by b.ordinal asc, b.work_lang asc, b.bucket_key asc
    loop
      v_n := v_b.n;
      select coalesce(sum(o.open_seats), 0)::int into v_g
        from tmp_ma_openteam o where o.bucket_key = v_b.bucket_key;

      -- 3.2 — SUBTRACT THE DECLARED GAP SEATS FIRST. Choosing k from n and
      -- then letting declared gaps eat the same people is what produces
      -- teams of two, and the size assertion below would pass long after the
      -- damage was done.
      v_g := least(v_g, v_n);          -- more gap seats than people is fine
      v_m := v_n - v_g;

      if v_m between 1 and 2 then
        if v_g >= (v_L - v_m) then
          -- 3.4(a) — hold back gap seats so a viable team of L can form.
          -- An unfilled declared gap is harmless. A team of 2 is the original
          -- failure wearing a hat.
          v_g := v_g - (v_L - v_m);
          v_m := v_L;
        elsif v_pass = 1 then
          -- 3.4(b) — one bounded retry into the next ranked challenge.
          for v_u in
            select u.unit_id, u.unit_size, u.lc, u.cur_rank
            from tmp_ma_unit u where u.bucket_key = v_b.bucket_key order by u.h
          loop
            select b2.bucket_key into v_target
            from tmp_ma_bucket b2
            join tmp_ma_unitpref up on up.challenge_id = b2.challenge_id
                                   and up.unit_id = v_u.unit_id
            where not b2.dissolved and b2.bucket_key <> v_b.bucket_key
              and (b2.work_lang = v_b.work_lang or v_u.lc = 'both')
            order by (b2.work_lang = v_b.work_lang) desc, up.prank asc, b2.n desc,
                     b2.ordinal asc, b2.bucket_key asc
            limit 1;
            if v_target is not null then
              update tmp_ma_unit u
                 set bucket_key = v_target,
                     cur_rank = least(u.cur_rank + 1, 3),
                     move_reason = 'remainder_moved_to_choice_'
                                   || least(u.cur_rank + 1, 3)::text
               where u.unit_id = v_u.unit_id;
            end if;
          end loop;
          continue;                     -- re-measured at the top of pass 2
        else
          -- 3.4(c) — a human seats one or two people. NEVER a team of 1 or 2.
          insert into tmp_ma_exc (profile_id, kind, detail, suggested_action)
          select pp.profile_id, 'remainder_unseatable',
                 'only ' || v_m::text || ' people left in this challenge/language bucket',
                 'Seat manually into an existing team, or with the late pool'
          from tmp_ma_person pp
          join tmp_ma_unit u on u.unit_id = pp.unit_id
          where u.bucket_key = v_b.bucket_key
          on conflict do nothing;
          update tmp_ma_unit u set bucket_key = null where u.bucket_key = v_b.bucket_key;
          update tmp_ma_bucket b set sized = true, n = 0 where b.bucket_key = v_b.bucket_key;
          continue;
        end if;
      end if;

      if v_pass = 1 then
        continue;                       -- pass 1 only moves; pass 2 builds
      end if;

      -- ── Seat list, Phase 4.1/4.3 ──────────────────────────────────────
      -- Existing-with-declared-gap first, widest gap first. Filling a gap of
      -- 2 before a gap of 1 is deliberate: putting TWO strangers into a
      -- two-seat gap together is a categorically different social experience
      -- from putting one stranger into three friends.
      v_acc := 0; v_ix := 0;
      for v_t in
        select o.team_id, o.sz, o.number, o.open_seats
        from tmp_ma_openteam o
        where o.bucket_key = v_b.bucket_key
        order by o.open_seats desc, o.number asc nulls last, o.team_id::text asc
      loop
        exit when v_acc >= v_g;
        v_k := least(v_t.open_seats, v_g - v_acc);
        insert into tmp_ma_team (team_key, bucket_key, existing_team, is_new, cap, ord,
                                 work_lang, target_size)
        values ('E:' || v_t.team_id::text, v_b.bucket_key, v_t.team_id, false, v_k, v_ix,
                v_b.work_lang, v_t.sz + v_k);

        insert into tmp_ma_seat (team_key, seat_ix, wanted_role)
        select 'E:' || v_t.team_id::text, x.rn - 1, x.role
        from (select g.role, row_number() over (order by g.role, s.i) as rn
              from team_gaps g, generate_series(1, g.seats) s(i)
              where g.team_id = v_t.team_id) x
        where x.rn <= v_k;

        -- The people already sitting there. The pick predicate needs their
        -- roles (for coverage) and their identities (for exclusions).
        insert into tmp_ma_tmember (team_key, profile_id, role)
        select 'E:' || v_t.team_id::text, tm.profile_id, tm.role_in_team
        from team_members tm
        where tm.team_id = v_t.team_id and tm.left_at is null
        on conflict do nothing;

        v_acc := v_acc + v_k;
        v_ix  := v_ix + 1;
      end loop;

      -- ── 3.5 — how many brand-new teams, and how big ──────────────────
      if v_m > 0 then
        v_k := match_clamp(round(v_m::numeric / v_tsize)::int,
                           ceil(v_m::numeric / v_umax)::int,
                           floor(v_m::numeric / v_L)::int);
        if v_k < 1 then v_k := 1; end if;

        -- Defensive: with the shipped config (L=3, T=4, U=5) the clamp
        -- interval is never empty and this never fires. It exists so a
        -- mis-set min/max (say 3 and 4, with m = 5) produces a NAMED
        -- exception rather than a team outside [L, U].
        if v_m > v_k * v_umax then
          insert into tmp_ma_exc (profile_id, kind, detail, suggested_action)
          select pp.profile_id, 'remainder_unseatable',
                 'bucket cannot be partitioned into teams within [' || v_L || ',' || v_umax || ']',
                 'Widen max_team_size, or seat manually'
          from tmp_ma_person pp
          join tmp_ma_unit u on u.unit_id = pp.unit_id
          where u.bucket_key = v_b.bucket_key
          on conflict do nothing;
          -- Named, and NOT dealt. Do not fall through into an assertion that
          -- would abort the whole run over one misconfigured bucket.
          update tmp_ma_unit u set bucket_key = null where u.bucket_key = v_b.bucket_key;
          update tmp_ma_bucket b set sized = true where b.bucket_key = v_b.bucket_key;
          continue;
        end if;

        v_q := v_m / v_k;
        v_r := v_m % v_k;
        for v_i in 1 .. v_k loop
          v_n := v_q + (case when v_i <= v_r then 1 else 0 end);
          -- ASSERT. Sizes 3, 4 and 5 only. Never 1, never 2, no leftover pile.
          if v_n < v_L or v_n > v_umax then
            raise exception 'MATCH_SIZE_ASSERT: bucket % produced a team of % (allowed %..%)',
              v_b.bucket_key, v_n, v_L, v_umax using errcode = 'P0007';
          end if;
          insert into tmp_ma_team (team_key, bucket_key, existing_team, is_new, cap, ord,
                                   work_lang, target_size)
          values ('N:' || v_b.bucket_key || ':' || v_i::text, v_b.bucket_key, null, true,
                  v_n, v_ix, v_b.work_lang, v_n);
          insert into tmp_ma_seat (team_key, seat_ix, wanted_role)
          select 'N:' || v_b.bucket_key || ':' || v_i::text, s.i - 1, null::role_tag
          from generate_series(1, v_n) s(i);
          v_ix := v_ix + 1;
        end loop;
      end if;

      update tmp_ma_bucket b set sized = true, g = v_g, m = v_m, k = v_ix
       where b.bucket_key = v_b.bucket_key;
    end loop;
  end loop;

  -- ───────────────────────────────────────────────────────────────────────
  -- Phase 5 — rarity and the draft order
  -- ───────────────────────────────────────────────────────────────────────
  -- role_rarity is PER BUCKET, after merging. Computing it globally places
  -- globally-scarce roles into buckets that do not need them: hardware may be
  -- 11-of-500 globally and the most common role inside the Robotics bucket.
  update tmp_ma_person pp set bucket_key = u.bucket_key
    from tmp_ma_unit u where u.unit_id = pp.unit_id;

  create temp table tmp_ma_rarity on commit drop as
  select pp.bucket_key,
         pp.primary_role,
         dense_rank() over (partition by pp.bucket_key
                            order by count(*) asc, role_ordinal(pp.primary_role) asc)::int as rr
  from tmp_ma_person pp
  where pp.bucket_key is not null
  group by pp.bucket_key, pp.primary_role;

  update tmp_ma_unit u
     set rarity_rank = coalesce((
           select min(r.rr) from tmp_ma_person pp
           join tmp_ma_rarity r on r.bucket_key = pp.bucket_key
                               and r.primary_role = pp.primary_role
           where pp.unit_id = u.unit_id), 99)
   where true;   -- whole-table recompute, explicit for the safeupdate guard

  -- 1. starved      — tried hardest, got nothing → FIRST PICK. This is how
  --                   the Aaltoes person is repaid, automatically.
  -- 2. unit_size    — pairs are harder to place, so place them early.
  -- 3. rarity_rank  — rarest primary role first. Because the queue is
  --                   rarity-ascending, round 1 of the snake deals the
  --                   scarcest role one-per-team before any team receives a
  --                   second of anything: "never double a role until every
  --                   team has one" is a CONSEQUENCE of the ordering, not a
  --                   rule anybody has to check, and it degrades gracefully.
  -- 4. experience   — strongest first within a rarity tier. Combined with the
  --                   snake this equalises mean experience across teams to
  --                   within about one band with no optimisation pass at all.
  -- 5. md5 hash     — the total order. Never omit this.
  update tmp_ma_unit u set seq = s.rn - 1
    from (select u2.unit_id,
                 (row_number() over (partition by u2.bucket_key
                    order by u2.starved desc, u2.unit_size desc, u2.rarity_rank asc,
                             u2.expband desc, u2.h asc))::int as rn
          from tmp_ma_unit u2 where u2.bucket_key is not null) s
   where s.unit_id = u.unit_id;

  -- ───────────────────────────────────────────────────────────────────────
  -- Phase 6 — the snake draft
  -- ───────────────────────────────────────────────────────────────────────
  -- Why a snake and not plain round-robin, in three properties and one line
  -- of arithmetic:
  --
  --  * Round 1 touches every team exactly once. Because the queue is
  --    rarity-ascending, the scarcest role is dealt one-per-team before any
  --    team receives a second of anything.
  --  * The snake cancels draft drift. Plain modulo gives team 1 picks
  --    1, k+1, 2k+1 — systematically the best of every round, with nothing
  --    noticing. The snake gives team 1 picks 1 and 2k, and team k picks k
  --    and k+1. With experience descending as the fourth sort key, mean
  --    experience equalises across teams with NO optimisation pass at all.
  --    This is the entire reason there is no exchange-repair phase.
  --  * It is explainable to a 16-year-old in one sentence: "it's a draft,
  --    like picking teams, and it snakes back so nobody gets all the first
  --    picks."
  for v_b in
    select b.bucket_key, b.challenge_id, b.work_lang
    from tmp_ma_bucket b
    where not b.dissolved and b.sized
    order by b.ordinal asc, b.work_lang asc, b.bucket_key asc
  loop
    select count(*) into v_k from tmp_ma_team t where t.bucket_key = v_b.bucket_key;
    continue when v_k = 0;

    v_seqno := 0;
    loop
      exit when (select count(*) from tmp_ma_unit u
                  where u.bucket_key = v_b.bucket_key and not u.placed) = 0;

      -- 6.1 — round, position, and the direction this round runs in.
      v_round := v_seqno / v_k;
      v_pos   := v_seqno % v_k;
      if v_round % 2 = 0 then v_base := v_pos;  v_dir := 1;
      else                    v_base := v_k - 1 - v_pos; v_dir := -1; end if;

      v_progress := false;

      for v_i in 0 .. v_k - 1 loop
        v_ix := ((v_base + v_dir * v_i) % v_k + v_k) % v_k;
        select t.team_key, t.bucket_key, t.cap, t.filled, t.work_lang, t.existing_team
          into v_t
        from tmp_ma_team t
        where t.bucket_key = v_b.bucket_key and t.ord = v_ix;
        continue when v_t.filled >= v_t.cap;

        v_wanted := (select s.wanted_role from tmp_ma_seat s
                      where s.team_key = v_t.team_key and not s.used
                      order by s.seat_ix asc limit 1);

        -- 6.2 — THE PICK PREDICATE.
        --   (a) HARD: no exclusion with any current or already-placed member
        --   (b) HARD: language compatible with the team's working language
        --   (c) the declared gap's role (primary, then secondary)
        --   (d) a role CLASS this team does not have yet
        --   (e) a primary role this team does not have yet
        --   (f) queue order
        -- (a) and (b) are filters; (c)-(e) are preferences applied in order,
        -- which is exactly "first candidate satisfying the highest-priority
        -- rule that any remaining candidate can satisfy". Fixing coverage
        -- HERE, at deal time, is what removes the need for a repair pass that
        -- reports it as a regret afterwards.
        v_pick := null;
        select u.unit_id, u.unit_size into v_pick, v_usize
        from tmp_ma_unit u
        where u.bucket_key = v_b.bucket_key
          and not u.placed
          and u.seq is not null
          and u.unit_size <= (v_t.cap - v_t.filled)
          and (u.lc = 'both'
               or (u.lc = 'fi_only' and v_t.work_lang = 'fi')
               or (u.lc = 'en_only' and v_t.work_lang = 'en'))
          and not exists (
            select 1
            from tmp_ma_person pm
            join tmp_ma_tmember tm on tm.team_key = v_t.team_key
            join tmp_ma_excl x on x.a = least(pm.profile_id, tm.profile_id)
                              and x.b = greatest(pm.profile_id, tm.profile_id)
            where pm.unit_id = u.unit_id)
        order by
          (case
            when v_wanted is not null and exists (
                   select 1 from tmp_ma_person pm
                    where pm.unit_id = u.unit_id and pm.primary_role = v_wanted) then 0
            when v_wanted is not null and exists (
                   select 1 from tmp_ma_person pm
                    where pm.unit_id = u.unit_id and pm.secondary_role = v_wanted) then 1
            when exists (
                   select 1 from tmp_ma_person pm
                    where pm.unit_id = u.unit_id
                      and not exists (select 1 from tmp_ma_tmember tm
                                       where tm.team_key = v_t.team_key
                                         and role_class(tm.role) = role_class(pm.primary_role))
                 ) then 2
            when exists (
                   select 1 from tmp_ma_person pm
                    where pm.unit_id = u.unit_id
                      and not exists (select 1 from tmp_ma_tmember tm
                                       where tm.team_key = v_t.team_key
                                         and tm.role = pm.primary_role)
                 ) then 3
            else 4 end) asc,
          u.seq asc
        limit 1;

        -- 6.3 — nobody in the queue can legally sit here (everyone left is
        -- excluded from this team, or speaks the wrong language). Leave the
        -- seat and move on; the stranded person is handled by the spill pass.
        continue when v_pick is null;

        select u.move_reason, u.rarity_rank into v_unit
          from tmp_ma_unit u where u.unit_id = v_pick;

        for v_pm in
          select pp.profile_id, pp.primary_role, pp.secondary_role, pp.from_team, pp.was_pinned
          from tmp_ma_person pp where pp.unit_id = v_pick
          order by pp.profile_id::text asc
        loop
          -- 6.4 — role_in_team: their own role if the team does not have it,
          -- else their secondary if that is free, else their own anyway.
          if not exists (select 1 from tmp_ma_tmember tm
                          where tm.team_key = v_t.team_key and tm.role = v_pm.primary_role) then
            v_role := v_pm.primary_role;
          elsif v_pm.secondary_role is not null
                and not exists (select 1 from tmp_ma_tmember tm
                                 where tm.team_key = v_t.team_key
                                   and tm.role = v_pm.secondary_role) then
            v_role := v_pm.secondary_role;
          else
            v_role := v_pm.primary_role;
          end if;

          v_reason := coalesce(
            v_unit.move_reason,
            case
              when v_wanted is not null
                   and (v_pm.primary_role = v_wanted or v_pm.secondary_role = v_wanted)
                then 'filled_declared_gap'
              when v_unit.rarity_rank = 1 then 'dealt_rarest_role'
              else 'dealt_general'
            end);

          insert into tmp_ma_tmember (team_key, profile_id, role)
          values (v_t.team_key, v_pm.profile_id, v_role)
          on conflict do nothing;

          insert into tmp_ma_place (profile_id, team_key, seq, role, reason_code,
                                    is_move, was_pinned, previous_team)
          values (v_pm.profile_id, v_t.team_key, v_seqno, v_role, v_reason,
                  v_pm.from_team is not null, v_pm.was_pinned, v_pm.from_team)
          on conflict do nothing;
        end loop;

        -- Consume the seats.
        update tmp_ma_seat s set used = true
         where s.team_key = v_t.team_key
           and s.seat_ix in (select s2.seat_ix from tmp_ma_seat s2
                              where s2.team_key = v_t.team_key and not s2.used
                              order by s2.seat_ix asc limit v_usize);
        update tmp_ma_team t set filled = t.filled + v_usize
         where t.team_key = v_t.team_key;
        update tmp_ma_unit u set placed = true where u.unit_id = v_pick;

        v_progress := true;
        exit;
      end loop;

      -- Nobody could be placed anywhere this round. Stop; the remainder is
      -- handled below rather than looping forever.
      exit when not v_progress;
      v_seqno := v_seqno + 1;
    end loop;
  end loop;

  -- ── 6.5 — one bounded spill for anyone the exclusions stranded ────────
  -- There is NO swap-repair pass. Expected violations at 500 people: 0-3. The
  -- ladder is: skip excluded teams at deal time (free, already in the
  -- predicate) → their next ranked challenge → a NAMED exception that blocks
  -- publish. That deletes the hardest test surface in the design, and the
  -- outcome is better: an organiser seats one person by hand in twenty
  -- seconds from a list the screen hands them. The pair is NEVER seated
  -- together to keep the coverage promise.
  for v_u in
    select u.unit_id, u.unit_size, u.lc, u.cur_rank
    from tmp_ma_unit u
    where not u.placed and u.bucket_key is not null
    order by u.h
  loop
    select t.team_key, t.work_lang into v_t
    from tmp_ma_team t
    join tmp_ma_bucket b on b.bucket_key = t.bucket_key
    join tmp_ma_unitpref up on up.challenge_id = b.challenge_id and up.unit_id = v_u.unit_id
    where (v_umax - (select count(*) from tmp_ma_tmember tm
                   where tm.team_key = t.team_key)) >= v_u.unit_size
      and (v_u.lc = 'both'
           or (v_u.lc = 'fi_only' and t.work_lang = 'fi')
           or (v_u.lc = 'en_only' and t.work_lang = 'en'))
      and not exists (
        select 1 from tmp_ma_person pm
        join tmp_ma_tmember tm on tm.team_key = t.team_key
        join tmp_ma_excl x on x.a = least(pm.profile_id, tm.profile_id)
                          and x.b = greatest(pm.profile_id, tm.profile_id)
        where pm.unit_id = v_u.unit_id)
    order by up.prank asc,
             (select count(*) from tmp_ma_tmember tm where tm.team_key = t.team_key) asc,
             t.team_key asc
    limit 1;

    if not found then
      insert into tmp_ma_exc (profile_id, kind, detail, suggested_action)
      select pp.profile_id, 'unseatable_exclusions',
             'excluded from, or language-incompatible with, every team in reach',
             'Seat manually; the exclusion guard will still refuse an illegal drop'
      from tmp_ma_person pp where pp.unit_id = v_u.unit_id
      on conflict do nothing;
      continue;
    end if;

    for v_pm in
      select pp.profile_id, pp.primary_role, pp.secondary_role, pp.from_team, pp.was_pinned
      from tmp_ma_person pp where pp.unit_id = v_u.unit_id
      order by pp.profile_id::text asc
    loop
      if not exists (select 1 from tmp_ma_tmember tm
                      where tm.team_key = v_t.team_key and tm.role = v_pm.primary_role) then
        v_role := v_pm.primary_role;
      elsif v_pm.secondary_role is not null
            and not exists (select 1 from tmp_ma_tmember tm
                             where tm.team_key = v_t.team_key
                               and tm.role = v_pm.secondary_role) then
        v_role := v_pm.secondary_role;
      else
        v_role := v_pm.primary_role;
      end if;

      insert into tmp_ma_tmember (team_key, profile_id, role)
      values (v_t.team_key, v_pm.profile_id, v_role) on conflict do nothing;

      insert into tmp_ma_place (profile_id, team_key, seq, role, reason_code,
                                is_move, was_pinned, previous_team)
      values (v_pm.profile_id, v_t.team_key, 9999, v_role,
              'blocked_moved_to_choice_' || least(v_u.cur_rank + 1, 3)::text,
              v_pm.from_team is not null, v_pm.was_pinned, v_pm.from_team)
      on conflict do nothing;
    end loop;

    update tmp_ma_unit u set placed = true where u.unit_id = v_u.unit_id;
    update tmp_ma_team t set filled = t.filled + v_u.unit_size
     where t.team_key = v_t.team_key;
  end loop;

  -- Anybody still unplaced with no bucket at all, and no exception yet.
  insert into tmp_ma_exc (profile_id, kind, detail, suggested_action)
  select pp.profile_id, 'beyond_preferences',
         'none of this attendee''s three ranked challenges survived bucketing',
         'Seat manually, or widen the challenge list'
  from tmp_ma_person pp
  join tmp_ma_unit u on u.unit_id = pp.unit_id
  where not u.placed
    and not exists (select 1 from tmp_ma_exc x where x.profile_id = pp.profile_id)
  on conflict do nothing;

  -- ───────────────────────────────────────────────────────────────────────
  -- Phase 8 — flags, reasons, metrics
  -- ───────────────────────────────────────────────────────────────────────
  -- lone_novice and solo_into_established_team are PREVIEW FLAGS, not
  -- constraints. Encoding either one as a hard constraint is precisely what
  -- forces a repair pass into existence.
  create temp table tmp_ma_final on commit drop as
  select tm.team_key, tm.profile_id, tm.role,
         coalesce(p.skill_level, 1)::int as expband,
         (pl.profile_id is not null) as placed_by_this_run
  from tmp_ma_tmember tm
  join profiles p on p.id = tm.profile_id
  left join tmp_ma_place pl on pl.profile_id = tm.profile_id;

  create temp table tmp_ma_teamout on commit drop as
  select t.team_key,
         t.bucket_key,
         b.challenge_id,
         t.work_lang,
         t.existing_team,
         t.is_new,
         (case when t.is_new then md5(v_salt || t.team_key)::uuid else t.existing_team end)
           as team_id,
         (select count(*) from tmp_ma_final f where f.team_key = t.team_key)::int as size,
         exists (select 1 from tmp_ma_final f
                  where f.team_key = t.team_key and role_class(f.role) = 'build') as has_build,
         exists (select 1 from tmp_ma_final f
                  where f.team_key = t.team_key and role_class(f.role) <> 'build') as has_nonbuild,
         (select count(distinct f.role) from tmp_ma_final f
           where f.team_key = t.team_key)::int as distinct_roles,
         coalesce((select max(f.expband) - min(f.expband) from tmp_ma_final f
                    where f.team_key = t.team_key), 0)::int as exp_spread
  from tmp_ma_team t
  join tmp_ma_bucket b on b.bucket_key = t.bucket_key;

  alter table tmp_ma_teamout add column flags text[] not null default '{}';

  update tmp_ma_teamout o set flags =
      (case when not o.has_build then array['no_builder'] else '{}'::text[] end)
    || (case when not exists (select 1 from tmp_ma_final f
                               where f.team_key = o.team_key and role_class(f.role) = 'voice')
             then array['no_communicator'] else '{}'::text[] end)
    || (case when o.distinct_roles < o.size then array['duplicate_role'] else '{}'::text[] end)
    -- Exactly one new arrival joining a team of three or more people who
    -- chose each other. Named at the top of the preview with "Move to a new
    -- team" / "Approve", because one shy stranger dropped into three friends
    -- is the worst individual experience this event can produce.
    || (case when (select count(*) from tmp_ma_final f
                    where f.team_key = o.team_key and f.placed_by_this_run) = 1
                  and (select count(*) from tmp_ma_final f
                        where f.team_key = o.team_key and not f.placed_by_this_run) >= 3
             then array['solo_into_established_team'] else '{}'::text[] end)
    -- Exactly one first-timer, and every other member at the top band, so
    -- there is nobody at the adjacent band for them to bridge to.
    || (case when (select count(*) from tmp_ma_final f
                    where f.team_key = o.team_key and f.expband = 1) = 1
                  and (select count(*) from tmp_ma_final f
                        where f.team_key = o.team_key and f.expband <> 3) = 1
                  and o.size >= 3
             then array['lone_novice'] else '{}'::text[] end)
    -- Only reachable when exclusions stranded somebody, which already wrote a
    -- named exception. Flagged as well so it is impossible to miss on screen.
    || (case when o.is_new and o.size > 0 and o.size < v_L
             then array['below_minimum'] else '{}'::text[] end)
   where true;   -- whole-table recompute, explicit for the safeupdate guard

  select jsonb_build_object(
    'mode',                p_mode,
    'roster_basis',        v_basis,
    'snapshot_at',         v_snap,
    'pool_people',         (select count(*) from tmp_ma_person),
    'placed',              (select count(*) from tmp_ma_place),
    'exceptions',          (select count(*) from tmp_ma_exc),
    'new_teams',           (select count(*) from tmp_ma_team where is_new),
    'existing_teams_filled',(select count(*) from tmp_ma_team where not is_new),
    'size_histogram',      (select coalesce(jsonb_object_agg(x.size::text, x.c), '{}'::jsonb)
                              from (select o.size, count(*) as c from tmp_ma_teamout o
                                    group by o.size) x),
    'teams_no_builder',    (select count(*) from tmp_ma_teamout o where not o.has_build),
    'teams_no_communicator',(select count(*) from tmp_ma_teamout o
                              where 'no_communicator' = any (o.flags)),
    'teams_duplicate_role',(select count(*) from tmp_ma_teamout o
                              where 'duplicate_role' = any (o.flags)),
    'first_choice_pct',    (select case when count(*) = 0 then 0
                             else round(100.0 * count(*) filter (
                               where u.cur_rank = 1) / count(*), 1) end
                             from tmp_ma_unit u where u.placed),
    'moves_of_notified',   (select count(*) from tmp_ma_place pl where pl.was_pinned),
    'constrained_by_exclusions',
                           (select count(*) from tmp_ma_place pl
                             where pl.reason_code like 'blocked_moved%'),
    'could_not_be_seated', (select count(*) from tmp_ma_exc)
  ) into v_metrics;

  -- ───────────────────────────────────────────────────────────────────────
  -- Persist, unless this is a dry run
  -- ───────────────────────────────────────────────────────────────────────
  if not p_dry then
    insert into match_runs (id, event_id, mode, state, salt, snapshot_at, roster_basis,
                            params, created_by, metrics)
    values (v_run, p_event, p_mode, 'previewed', v_salt, v_snap, v_basis,
            jsonb_build_object('target_team_size', v_tsize, 'min_team_size', v_L,
                               'max_team_size', v_umax, 'min_bucket_size', v_MINB),
            auth.uid(), v_metrics)
    on conflict (id) do update
      set state = 'previewed', metrics = excluded.metrics, snapshot_at = excluded.snapshot_at,
          params = excluded.params, mode = excluded.mode, roster_basis = excluded.roster_basis;

    -- Idempotence: a re-run of the same run_id replaces its frozen inputs and
    -- its proposal wholesale.
    delete from run_pool       where run_id = v_run;
    delete from run_seats      where run_id = v_run;
    delete from run_exclusions where run_id = v_run;
    delete from run_placements where run_id = v_run;
    delete from run_teams      where run_id = v_run;
    delete from run_exceptions where run_id = v_run;

    insert into run_pool (run_id, profile_id, unit_id, unit_size, primary_role,
                          secondary_role, experience, lang_class, starved,
                          pref1, pref2, pref3, from_team, was_pinned)
    select v_run, pp.profile_id, pp.unit_id, u.unit_size, pp.primary_role,
           pp.secondary_role, pp.expband, pp.lc, pp.starved,
           u.pref1, u.pref2, u.pref3, pp.from_team, pp.was_pinned
    from tmp_ma_person pp join tmp_ma_unit u on u.unit_id = pp.unit_id;

    insert into run_seats (run_id, team_key, seat_index, wanted_role, is_new_team, bucket_key)
    select v_run, s.team_key, s.seat_ix, s.wanted_role, t.is_new, t.bucket_key
    from tmp_ma_seat s join tmp_ma_team t on t.team_key = s.team_key;

    insert into run_exclusions (run_id, a, b)
    select distinct v_run, x.a, x.b
    from tmp_ma_excl x
    where exists (select 1 from tmp_ma_person pp where pp.profile_id = x.a)
       or exists (select 1 from tmp_ma_person pp where pp.profile_id = x.b);

    insert into run_placements (run_id, profile_id, team_id, team_key, bucket_key, seq,
                                proposed_role, reason_code, flags, is_move, was_pinned,
                                previous_team_id)
    select v_run, pl.profile_id, o.team_id, pl.team_key, o.bucket_key, pl.seq,
           pl.role, pl.reason_code, o.flags, pl.is_move, pl.was_pinned, pl.previous_team
    from tmp_ma_place pl join tmp_ma_teamout o on o.team_key = pl.team_key;

    insert into run_teams (run_id, team_id, team_key, bucket_key, challenge_id, working_lang,
                           size, is_new, has_build, has_nonbuild, distinct_roles, exp_spread,
                           flags)
    select v_run, o.team_id, o.team_key, o.bucket_key, o.challenge_id, o.work_lang,
           o.size, o.is_new, o.has_build, o.has_nonbuild, o.distinct_roles, o.exp_spread,
           o.flags
    from tmp_ma_teamout o
    where o.size > 0;          -- an empty shell never gets a number or a table

    insert into run_exceptions (run_id, profile_id, kind, detail, suggested_action)
    select v_run, x.profile_id, x.kind, x.detail, x.suggested_action from tmp_ma_exc x;
  end if;

  -- ───────────────────────────────────────────────────────────────────────
  -- The proposal
  -- ───────────────────────────────────────────────────────────────────────
  return query
  select v_run,
         o.bucket_key,
         pl.team_key,
         o.team_id,
         o.is_new,
         o.size,
         o.challenge_id,
         o.work_lang,
         pl.seq,
         pl.profile_id,
         pl.role,
         pl.reason_code,
         o.flags
  from tmp_ma_place pl
  join tmp_ma_teamout o on o.team_key = pl.team_key
  order by o.bucket_key asc, pl.team_key asc, pl.seq asc, pl.profile_id::text asc;
end
$ma$;

revoke all on function match_auto_assign(uuid, run_mode_t, boolean, uuid, text, uuid[], text)
  from public;
grant execute on function match_auto_assign(uuid, run_mode_t, boolean, uuid, text, uuid[], text)
  to authenticated;

-- ═════════════════════════════════════════════════════════════════════════
-- Phase 9 — publish
-- ═════════════════════════════════════════════════════════════════════════
-- Reads ONLY the frozen run_* tables. It never recomputes anything, so the
-- thing that gets published is provably the thing the organiser approved.

create or replace function publish_run(p_run uuid) returns jsonb
language plpgsql security definer set search_path = public
as $pr$
declare
  v_r      match_runs%rowtype;
  v_e      events%rowtype;
  v_t      record;
  v_p      record;
  v_num    int;
  v_tab    int;
  v_cap    uuid;
  v_teams  int := 0;
  v_people int := 0;
  v_moved  int := 0;
  v_bad    int;
  v_fi     text;
  v_en     text;
begin
  if not is_admin() then raise exception 'organiser only'; end if;

  select * into v_r from match_runs where id = p_run;
  if not found then raise exception 'MATCH_NO_RUN: %', p_run using errcode = 'P0005'; end if;
  if v_r.state = 'published' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if v_r.state <> 'previewed' then
    raise exception 'MATCH_RUN_NOT_PREVIEWED: state is %', v_r.state using errcode = 'P0009';
  end if;
  if v_r.mode = 'dry' then
    raise exception 'MATCH_DRY_RUN: a rehearsal run is never publishable' using errcode = 'P0009';
  end if;

  select * into v_e from events where id = v_r.event_id;
  perform pg_advisory_xact_lock(hashtext(v_r.event_id::text));

  -- Make the exclusion guard fire per row rather than at COMMIT, so a
  -- violation names the row that caused it instead of failing the whole
  -- transaction anonymously at the end.
  set constraints tm_exclusion_guard immediate;

  -- ── 9.1 STALENESS, narrowed to PROPOSAL-RELEVANT deltas ──────────────
  -- An any-write staleness rule makes this button unreachable at a live
  -- event: check-in is a continuous stream at 09:05 and the organiser would
  -- refuse-rerun forever. A plain new check-in does NOT refuse; those people
  -- are auto-enqueued for mode 'single' after publish, and the preview says
  -- so. What DOES refuse:

  -- (a) a new block or separation between two people proposed onto one team
  if exists (
    select 1 from run_placements p1
    join run_placements p2 on p2.run_id = p1.run_id and p2.team_id = p1.team_id
                          and p2.profile_id > p1.profile_id
    join match_exclusions me on me.a = least(p1.profile_id, p2.profile_id)
                            and me.b = greatest(p1.profile_id, p2.profile_id)
    where p1.run_id = p_run) then
    update match_runs set state = 'failed', failed_reason = 'stale_exclusion' where id = p_run;
    raise exception 'MATCH_STALE_EXCLUSION: a safety exclusion now touches this proposal; re-run'
      using errcode = 'P0010';
  end if;

  -- (b) membership changed on a team this proposal touches
  if exists (
    select 1 from team_members tm
    join run_teams rt on rt.team_id = tm.team_id and rt.run_id = p_run
    where tm.joined_at > v_r.snapshot_at or tm.left_at > v_r.snapshot_at) then
    raise exception 'MATCH_STALE_MEMBERSHIP: a team in this proposal changed since the snapshot; re-run'
      using errcode = 'P0010';
  end if;

  -- (c) a proposed team was locked, disbanded, or changed its declared gaps
  if exists (
    select 1 from teams t
    join run_teams rt on rt.team_id = t.id and rt.run_id = p_run
    where t.locked or t.state = 'disbanded') then
    raise exception 'MATCH_STALE_TEAM: a team in this proposal was locked or disbanded; re-run'
      using errcode = 'P0010';
  end if;
  if exists (
    select 1 from team_gaps g
    join run_teams rt on rt.team_id = g.team_id and rt.run_id = p_run
    where g.declared_at > v_r.snapshot_at) then
    raise exception 'MATCH_STALE_GAPS: declared gaps changed since the snapshot; re-run'
      using errcode = 'P0010';
  end if;

  -- ── 9.2 Every named exception blocks publish until it is acknowledged ──
  select count(*) into v_bad from run_exceptions x
   where x.run_id = p_run and x.acknowledged_by is null;
  if v_bad > 0 then
    raise exception 'MATCH_UNRESOLVED_EXCEPTIONS: % people could not be auto-seated; seat or acknowledge each one first', v_bad
      using errcode = 'P0011';
  end if;

  -- ── 9.3 Numbers and tables ────────────────────────────────────────────
  -- Existing teams keep their number and their table. ALWAYS.
  select coalesce(max(t.number), 0) into v_num from teams t where t.event_id = v_r.event_id;
  v_tab := v_e.first_table_number;

  for v_t in
    select rt.team_id, rt.team_key, rt.challenge_id, rt.working_lang, rt.bucket_key, rt.size
    from run_teams rt
    join challenges c on c.id = rt.challenge_id
    where rt.run_id = p_run and rt.is_new and rt.size > 0
    -- Keep same-challenge teams adjacent on the floor.
    order by c.ordinal asc, rt.working_lang asc, rt.team_key asc
  loop
    v_num := v_num + 1;

    loop
      exit when not exists (select 1 from teams t
                             where t.event_id = v_r.event_id and t.table_number = v_tab)
            -- reserve_tables are held back for late-formed teams; only the
            -- late/repair modes may take one.
            and (v_r.mode in ('single','repair') or not (v_tab = any (v_e.reserve_tables)));
      v_tab := v_tab + 1;
    end loop;

    -- Captain of an auto team = lowest seq in the team. Labelled in-app
    -- "table host", never "leader".
    select p.profile_id into v_cap
      from run_placements p
     where p.run_id = p_run and p.team_id = v_t.team_id
     order by p.seq asc, p.profile_id::text asc limit 1;

    insert into teams (id, event_id, number, table_number, challenge_id, working_lang,
                       captain_id, state, origin)
    values (v_t.team_id, v_r.event_id, v_num, v_tab, v_t.challenge_id, v_t.working_lang,
            v_cap, 'active', case when v_r.mode = 'single' then 'late_pool' else 'auto' end)
    on conflict (id) do nothing;

    update run_teams set table_number = v_tab where run_id = p_run and team_id = v_t.team_id;
    v_tab   := v_tab + 1;
    v_teams := v_teams + 1;
  end loop;

  -- ── 9.4 Memberships, ROW BY ROW ───────────────────────────────────────
  -- Row by row so each insert is its own command: the guard then sees every
  -- previously inserted row immediately and the error names the seat.
  for v_p in
    select p.profile_id, p.team_id, p.proposed_role, p.previous_team_id, p.reason_code, p.seq
    from run_placements p
    where p.run_id = p_run
    order by p.team_id::text asc, p.seq asc, p.profile_id::text asc
  loop
    if v_p.previous_team_id is not null and v_p.previous_team_id <> v_p.team_id then
      update team_members tm set left_at = now(), left_reason = 'organiser'
       where tm.profile_id = v_p.profile_id and tm.left_at is null;
      v_moved := v_moved + 1;
    end if;

    insert into team_members (team_id, profile_id, role_in_team, joined_via, run_id,
                              pinned, notified_at)
    values (v_p.team_id, v_p.profile_id, v_p.proposed_role,
            case when v_r.mode = 'single' then 'late' else 'auto' end, p_run,
            true, now())
    on conflict do nothing;

    v_people := v_people + 1;

    -- Consume the declared seat on an existing team.
    delete from team_gaps g
     where g.team_id = v_p.team_id and g.role = v_p.proposed_role and g.seats <= 1;
    update team_gaps g set seats = g.seats - 1
     where g.team_id = v_p.team_id and g.role = v_p.proposed_role;

    -- ── 9.6 The reason, in both languages, from the code ───────────────
    -- Rendered here rather than in the client so the wording is identical in
    -- the app, on the placard and in the organiser console.
    select case v_p.reason_code
             when 'bilingual_rescue' then
               'Puhut molempia kieliä, joten sinut sijoitettiin tiimiin, joka tarvitsi sinua.'
             when 'no_ranked_challenge_available' then
               'Valitsemiisi haasteisiin ei tullut tarpeeksi osallistujia, joten olet lähimmässä vaihtoehdossa.'
             when 'filled_declared_gap' then
               'Tiimi ilmoitti etsivänsä juuri sinun osaamistasi.'
             when 'dealt_rarest_role' then
               'Osaamisesi oli harvinaisinta tässä haasteessa, joten sait ensimmäisen vuoron.'
             else
               'Sinut sijoitettiin tiimiin, joka sopii ensimmäiseen haastevalintaasi.'
           end,
           case v_p.reason_code
             when 'bilingual_rescue' then
               'You speak both languages, so you were placed with a team that needed you.'
             when 'no_ranked_challenge_available' then
               'Not enough people picked your challenges, so you are on the closest one.'
             when 'filled_declared_gap' then
               'This team said they were looking for exactly your role.'
             when 'dealt_rarest_role' then
               'Your role was the rarest in this challenge, so you were picked first.'
             else
               'You were placed with a team matching your first-choice challenge.'
           end
      into v_fi, v_en;

    insert into placement_trace (profile_id, team_id, run_id, reason_code, reason_fi, reason_en)
    values (v_p.profile_id, v_p.team_id, p_run, v_p.reason_code, v_fi, v_en)
    on conflict (profile_id) do update
      set team_id = excluded.team_id, run_id = excluded.run_id,
          reason_code = excluded.reason_code, reason_fi = excluded.reason_fi,
          reason_en = excluded.reason_en, created_at = now();
  end loop;

  -- Teams emptied by this run (the NON_VIABLE ones whose members moved out)
  -- are retired. Their number and table are retired with them.
  update teams t set state = 'disbanded', disbanded_at = now(),
                     disbanded_reason = 'collapsed_below_min'
   where t.event_id = v_r.event_id and t.state <> 'disbanded'
     and not exists (select 1 from team_members tm
                      where tm.team_id = t.id and tm.left_at is null);

  update teams t set state = 'active'
   where t.id in (select rt.team_id from run_teams rt where rt.run_id = p_run)
     and t.state = 'forming';

  -- ── 9.5 The set assertion. MUST return zero rows. ─────────────────────
  select count(*) into v_bad from assert_no_excluded_teammates(v_r.event_id);
  if v_bad > 0 then
    raise exception 'EXCLUSION_VIOLATION_SET: % illegal pairs would be committed; the matcher has a bug', v_bad
      using errcode = 'P0002';
  end if;

  -- ── 9.7 The sanctioned switch window ──────────────────────────────────
  -- 40 minutes in which the same link machine reopens with a 15-minute TTL.
  -- The switch rate over this window is the single most honest quality metric
  -- this system produces: 3% means the deal was good, 25% means the
  -- parameters were wrong and next year we know it.
  update events set switch_window_ends_at = now() + interval '40 minutes'
   where id = v_r.event_id and v_r.mode = 'full';

  update match_runs
     set state = 'published', published_at = now(), published_by = auth.uid(),
         metrics = coalesce(metrics, '{}'::jsonb)
                   || jsonb_build_object('published_teams', v_teams,
                                         'published_people', v_people,
                                         'moved_people', v_moved)
   where id = p_run;

  insert into organiser_actions (event_id, actor, action, payload, reason)
  values (v_r.event_id, auth.uid(), 'publish_run',
          jsonb_build_object('run_id', p_run, 'teams', v_teams, 'people', v_people,
                             'moved', v_moved),
          'organiser published an auto-assign run');

  -- 9.8 The push payload carries NO personal data: no names, no counts, no
  -- scores. It transits Apple infrastructure outside the EU, and a
  -- teammate's name must not.
  return jsonb_build_object('ok', true, 'teams', v_teams, 'people', v_people,
                            'moved', v_moved, 'run_id', p_run);
end
$pr$;

-- ═════════════════════════════════════════════════════════════════════════
-- Organiser overrides
-- ═════════════════════════════════════════════════════════════════════════

-- Acknowledging an exception is what unblocks publish, and it is recorded
-- under a named organiser with a required note.
create or replace function match_ack_exception(p_run uuid, p_profile uuid, p_kind text,
                                               p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'organiser only'; end if;
  if coalesce(char_length(trim(p_note)), 0) < 3 then
    raise exception 'A note is required: say what you did about this person.';
  end if;
  update run_exceptions x
     set acknowledged_by = auth.uid(), acknowledged_at = now(), acknowledged_note = p_note
   where x.run_id = p_run and x.profile_id = p_profile and x.kind = p_kind;

  insert into organiser_actions (event_id, actor, action, target_profile, payload, reason)
  select r.event_id, auth.uid(), 'ack_exception', p_profile,
         jsonb_build_object('run_id', p_run, 'kind', p_kind), p_note
    from match_runs r where r.id = p_run;
  return jsonb_build_object('ok', true);
end
$fn$;

-- Runs the same checks as the algorithm. It MAY be forced past soft
-- constraints (role duplication, experience imbalance, size 6) with a
-- required reason. It MAY NOT be forced past match_exclusions — that is not a
-- policy, it is a database invariant, and the guard below will refuse.
create or replace function match_organiser_move(p_profile uuid, p_team uuid, p_reason text,
                                                p_forced boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_e events%rowtype; v_size int; v_role role_tag; v_event uuid;
begin
  if not is_admin() then raise exception 'organiser only'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then
    raise exception 'A reason is required.';
  end if;

  select t.event_id into v_event from teams t where t.id = p_team;
  select * into v_e from events where id = v_event;
  select count(*) into v_size from team_members tm
   where tm.team_id = p_team and tm.left_at is null;

  if v_size >= v_e.max_team_size and not p_forced then
    return jsonb_build_object('ok', false, 'reason', 'team_full');
  end if;

  select p.primary_role into v_role from profiles p where p.id = p_profile;

  begin
    update team_members tm set left_at = now(), left_reason = 'organiser'
     where tm.profile_id = p_profile and tm.left_at is null;
    insert into team_members (team_id, profile_id, role_in_team, joined_via)
    values (p_team, p_profile, v_role, 'organiser');
    set constraints tm_exclusion_guard immediate;
  exception when sqlstate 'P0002' then
    -- Never "you are blocked", not even to an organiser drag-and-drop.
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end;

  insert into organiser_actions (event_id, actor, action, target_profile, target_team,
                                 reason, forced)
  values (v_event, auth.uid(), 'move', p_profile, p_team, p_reason, p_forced);

  return jsonb_build_object('ok', true);
end
$fn$;

-- The walk-in at 13:40. Not a second algorithm: this is the ranking from
-- mode 'single', and BOTH sides get told. The captain's push says "Aino is
-- joining you as your designer - she just arrived", and that one sentence is
-- the difference between a teammate and an intruder.
create or replace function match_seat_late(p_event uuid, p_profile uuid)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_team uuid; v_role role_tag; v_lc lang_class_t; v_e events%rowtype;
begin
  if not is_admin() and not is_staff() then raise exception 'organiser only'; end if;
  select * into v_e from events where id = p_event;
  select p.primary_role, lang_class(p.languages) into v_role, v_lc
    from profiles p where p.id = p_profile;

  select t.id into v_team
  from teams t
  join challenge_prefs cp on cp.challenge_id = t.challenge_id and cp.profile_id = p_profile
  where t.event_id = p_event
    and t.state = 'active' and t.accepts_late and not t.locked
    and (select count(*) from team_members tm
          where tm.team_id = t.id and tm.left_at is null) < v_e.max_team_size
    and (v_lc = 'both' or (v_lc = 'fi_only' and t.working_lang = 'fi')
                       or (v_lc = 'en_only' and t.working_lang = 'en'))
    and not exists (
      select 1 from team_members tm
      join match_exclusions me on me.a = least(tm.profile_id, p_profile)
                              and me.b = greatest(tm.profile_id, p_profile)
      where tm.team_id = t.id and tm.left_at is null)
  order by
    -- a declared gap matching their role, then a team missing their class,
    -- then the smallest team, then the nearest table. Nearer the door is a
    -- genuinely kinder first walk.
    (exists (select 1 from team_gaps g where g.team_id = t.id and g.role = v_role)) desc,
    (not exists (select 1 from team_members tm
                  where tm.team_id = t.id and tm.left_at is null
                    and role_class(tm.role_in_team) = role_class(v_role))) desc,
    (select count(*) from team_members tm
      where tm.team_id = t.id and tm.left_at is null) asc,
    cp.rank asc, t.table_number asc, t.id::text asc
  limit 1;

  if v_team is null then
    return jsonb_build_object('ok', false, 'reason', 'late_pool');
  end if;

  begin
    insert into team_members (team_id, profile_id, role_in_team, joined_via, pinned, notified_at)
    values (v_team, p_profile, v_role, 'late', true, now());
    set constraints tm_exclusion_guard immediate;
  exception when sqlstate 'P0002' then
    return jsonb_build_object('ok', false, 'reason', 'unavailable');
  end;

  delete from team_gaps g
   where g.team_id = v_team and g.role = v_role and g.seats <= 1;
  update team_gaps g set seats = g.seats - 1
   where g.team_id = v_team and g.role = v_role;

  insert into organiser_actions (event_id, actor, action, target_profile, target_team, reason)
  values (p_event, auth.uid(), 'seat_late', p_profile, v_team, 'walk-in seated');

  return jsonb_build_object('ok', true, 'team_id', v_team);
end
$fn$;

-- A table is physically wrong: broken socket, not accessible. Swap the table
-- NUMBERS only. Memberships are untouched, both placards get reprinted.
create or replace function match_swap_tables(p_team_a uuid, p_team_b uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_a int; v_b int; v_event uuid;
begin
  if not is_admin() then raise exception 'organiser only'; end if;
  select t.table_number, t.event_id into v_a, v_event from teams t where t.id = p_team_a;
  select t.table_number into v_b from teams t where t.id = p_team_b;

  perform set_config('stuhi.allow_table_move', 'on', true);   -- transaction-local
  update teams set table_number = null   where id = p_team_a;
  update teams set table_number = v_a    where id = p_team_b;
  update teams set table_number = v_b    where id = p_team_a;
  perform set_config('stuhi.allow_table_move', 'off', true);

  insert into organiser_actions (event_id, actor, action, target_team, reason)
  values (v_event, auth.uid(), 'swap_tables', p_team_a, p_reason);
  return jsonb_build_object('ok', true);
end
$fn$;

create or replace function match_discard_run(p_run uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'organiser only'; end if;
  update match_runs set state = 'discarded' where id = p_run and state <> 'published';
  return jsonb_build_object('ok', true);
end
$fn$;

revoke all on function publish_run(uuid) from public;
revoke all on function match_ack_exception(uuid, uuid, text, text) from public;
revoke all on function match_organiser_move(uuid, uuid, text, boolean) from public;
revoke all on function match_seat_late(uuid, uuid) from public;
revoke all on function match_swap_tables(uuid, uuid, text) from public;
revoke all on function match_discard_run(uuid) from public;

grant execute on function publish_run(uuid) to authenticated;
grant execute on function match_ack_exception(uuid, uuid, text, text) to authenticated;
grant execute on function match_organiser_move(uuid, uuid, text, boolean) to authenticated;
grant execute on function match_seat_late(uuid, uuid) to authenticated;
grant execute on function match_swap_tables(uuid, uuid, text) to authenticated;
grant execute on function match_discard_run(uuid) to authenticated;

-- ═════════════════════════════════════════════════════════════════════════
-- The 03:00 runbook, in the schema so it is never lost
-- ═════════════════════════════════════════════════════════════════════════

-- Who has checked in, wants a team, and has no team?
create or replace view unteamed_attendees with (security_barrier = true) as
select p.id, p.display_name, p.primary_role, lang_class(p.languages) as lang_class
from profiles p
join tickets tk on tk.profile_id = p.id and tk.state = 'admitted'
where is_admin()
  and p.deleted_at is null and p.suspended_at is null and p.wants_team
  and not exists (select 1 from team_members tm
                   where tm.profile_id = p.id and tm.left_at is null);

-- Which teams are dying?
create or replace view teams_below_minimum with (security_barrier = true) as
select t.id, t.number, t.table_number, t.challenge_id,
       (select count(*) from team_members tm
         where tm.team_id = t.id and tm.left_at is null)::int as size
from teams t
join events e on e.id = t.event_id
where is_admin()
  and t.state = 'active'
  and (select count(*) from team_members tm
        where tm.team_id = t.id and tm.left_at is null) < e.min_team_size;

grant select on unteamed_attendees, teams_below_minimum to authenticated;

commit;

-- ═════════════════════════════════════════════════════════════════════════
-- ROLLBACK (commented; destroys all matching data)
-- ═════════════════════════════════════════════════════════════════════════
-- Run top to bottom. It leaves 010_core untouched apart from dropping the
-- columns this file added to profiles, events and challenges.
--
-- begin;
--
-- drop view if exists teams_below_minimum, unteamed_attendees, my_team,
--   my_links, attendee_cards, team_cards, match_exclusions cascade;
--
-- drop function if exists publish_run(uuid),
--   match_auto_assign(uuid, run_mode_t, boolean, uuid, text, uuid[], text),
--   match_discard_run(uuid), match_swap_tables(uuid, uuid, text),
--   match_seat_late(uuid, uuid), match_organiser_move(uuid, uuid, text, boolean),
--   match_ack_exception(uuid, uuid, text, text), match_release_seat(uuid),
--   match_leave_team(text), match_create_team(uuid, uuid, work_lang_t, text),
--   match_close_matching(uuid), match_expire_links(), match_withdraw_link(uuid),
--   match_dismiss_link(uuid), match_accept_link(uuid), match_mark_seen(uuid),
--   match_send_link(uuid, link_dir_t, role_tag, uuid), match_link_ttl(uuid, link_dir_t),
--   match_browse_people(int), match_link_card(uuid), match_excluded_with(uuid), match_roles_needed_by(uuid),
--   match_captains_team_with_gap(), match_my_team(), match_is_captain(uuid),
--   match_is_team_member(uuid), assert_no_excluded_teammates(uuid),
--   match_profile_is_complete(uuid), moderate_team_name(), blocks_guard_cap(),
--   blocks_after_insert(), links_touch_starved(), prefs_guard_completeness(),
--   profiles_guard_browsable(), teams_guard_identity(), forbid_excluded_teammate(),
--   is_safety(), match_clamp(int, int, int), lang_class(text[]), role_ordinal(role_tag),
--   role_class(role_tag) cascade;
--
-- drop table if exists organiser_actions, placement_trace, run_exceptions, run_teams,
--   run_placements, run_exclusions, run_seats, run_pool, match_runs,
--   safety_separations, link_requests, team_members, team_gaps, teams,
--   challenge_prefs cascade;
--
-- drop type if exists bio_state_t, run_state_t, run_mode_t, team_origin_t, team_state_t,
--   join_via_t, link_state_t, link_dir_t, work_lang_t, lang_class_t, role_class_t;
--
-- alter table profiles
--   drop column if exists wants_team, drop column if exists solo_opted_at,
--   drop column if exists wants_late_seat, drop column if exists starved,
--   drop column if exists bio_status, drop column if exists bio_submitted_at,
--   drop column if exists bio_reviewed_by, drop column if exists bio_reviewed_at,
--   drop column if exists terms_version, drop column if exists terms_accepted_at,
--   drop column if exists safety_lead;
--
-- alter table events
--   drop column if exists challenges_frozen_at, drop column if exists matching_opens_at,
--   drop column if exists assign_deadline_at, drop column if exists matching_closed_at,
--   drop column if exists switch_window_ends_at, drop column if exists target_team_size,
--   drop column if exists min_team_size, drop column if exists max_team_size,
--   drop column if exists min_bucket_size, drop column if exists max_open_links,
--   drop column if exists max_inbound_links, drop column if exists request_ttl_hours,
--   drop column if exists invite_ttl_hours, drop column if exists block_cap,
--   drop column if exists bio_enabled, drop column if exists late_join_enabled,
--   drop column if exists reserve_tables, drop column if exists first_table_number,
--   drop column if exists terms_version;
--
-- alter table challenges
--   drop column if exists code, drop column if exists max_teams, drop column if exists state;
--
-- commit;
