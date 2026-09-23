# Team matching

**Status:** decided. This is the specification we build. Alternatives that were seriously
considered and rejected are recorded in short "Rejected" notes so nobody re-opens them in
week six.

**Event:** STUHI X TAMPERE, 24–25 October 2026, Tampere University Hervanta Campus.
~500 registered attendees, `lukiolaiset` aged roughly 15–19, Finnish and English.

**Stack:** SwiftUI iOS client + a small organiser web console + self-hosted Supabase Postgres on Mark's box
(EU region) with Row Level Security. No ML, no LLM, no external solver, no third-party
matching service.

---

## The problem

Many attendees arrive alone. The organiser's own experience is the specification:

> At a previous Aaltoes hackathon he posted in a "looking for a team" Discord channel.
> Nobody ever replied. He spent the entire event alone.

Two things failed there, and they are different failures.

1. **The board was passive.** A post is not addressed to anybody, so nobody is responsible
   for answering it. Worse, silence is ambiguous: an ignored post and an unseen post look
   identical, so the person cannot tell whether to try again, and trying again feels like
   begging. Passive "post and hope" boards do not work and we will not build one.
2. **There was no backstop.** Even a good voluntary mechanic leaves a residue. If the
   residue is handled by "walk around the room and ask", the shy, the first-timers, the
   monolingual Finnish speakers and the non-coders are exactly the people who end up alone.

So the system has two halves and both are mandatory:

- **Voluntary, directed mechanics** (A and B below) that run from T−7d and let people and
  teams find each other on purpose, with every interaction addressed to a specific party
  who can accept it.
- **A safety net** (C) that runs once, on the morning of day one, over everyone who has
  physically checked in, and seats every remaining person in a real team of 3–5 at a real
  table. Nobody is left unteamed **by construction**, not by hope.

The guarantee we make, precisely worded, because we will be held to it:

> Every attendee who checks in, wants a team, and has completed a profile is either
> already in a team or is seated in one by the auto-assign run — except for a named,
> visible, single-digit set of people that safeguarding constraints make unseatable, whom
> the organiser seats by hand from a list the preview screen hands them.

We do not claim "nobody unteamed, no exceptions". We claim "nobody unteamed, and the
exceptions are named on a screen before anything is published." That is a promise we can
actually keep.

### What the safety net is *not*

Guaranteed placement is not guaranteed belonging. The algorithm can seat a shy 16-year-old
at a table where nobody speaks to them for six hours, and every metric in the preview will
report a flawless run. Three non-software requirements carry that, and they are load-bearing:

- **Table hosts.** One volunteer per ~6 tables who, at 10:00, says every name out loud and
  runs a 20-minute scripted icebreaker (name, role, one thing you want to learn this weekend).
- **Role on the placard.** Every printed table placard lists each member's first name *and
  their role in the team*. "Nea — designer" is a job. A name alone is a guest.
- **A judging rubric that reserves one of three prizes for idea/design/pitch**, with no
  working prototype required. Correct team composition does not fix the status of non-coders
  inside a team; a prize does. This is an organiser decision, not an algorithm output, and
  the algorithm must not be allowed to imply otherwise.

---

## What we will NOT build, and why

App Store Review Guideline 1.2 (User-Generated Content), verbatim, is the binding constraint.
Apps used primarily for

> "objectification of real people (e.g. hot-or-not voting)", "Chatroulette-style
> experiences, random or anonymous chat", or bullying

> "do not belong on the App Store and may be removed without notice".

Guideline 1.2 also **mandates**, for any app with UGC: a method for filtering objectionable
material, a mechanism to report offensive content with timely responses, the ability to block
abusive users, and published contact information so users can reach you.

Our attendees include minors. Finland's GDPR digital-consent age is 13, so 15-year-olds can
consent for themselves, but "legally permitted" is not the bar we are aiming at. The bar is:
would a reviewer, or a parent, look at this screen and see a place where a 15-year-old is
sorted, scored, or exposed to strangers? Everything below follows from that.

**Therefore, decided and closed:**

| Not building | Why |
|---|---|
| **A Tinder-style swipe deck of people.** No card stack, no left/right, no "next person". | Straight into "objectification of real people". This is the single most likely instant rejection for a team-matching app and there is no version of it we can make safe. |
| **Any score, percentage, rank, star or badge attached to a person.** No "92% match", no compatibility meter, no leaderboard, no "most invited". | Same clause. There is exactly one ordering of people anywhere in this product (§ Mechanic B, the anti-neglect sort) and it ranks *neglect*, not people — see the note there. |
| **A visible rejection state.** No "declined", no "rejected", no read receipt, no "seen 6 hours ago, no reply", no rejection counter, no history of who said no. | A dismissal and a timeout must be indistinguishable to the sender. Every terminal non-accepted state renders as one string. |
| **Open browsing of minors' free text by strangers.** | Browsing other people is gated three ways (§ Mechanic B). Bios ship **disabled** by default (§ Moderation). |
| **Direct messages between arbitrary strangers.** No DMs at any point before a team link exists; no free-text field on a request or an invite. | Removes the grooming-by-invite channel completely. An invite is a fixed localised string plus one enum value. It costs the product nothing. |
| **Photos, avatars, image upload of any kind.** | Image moderation is a product we cannot staff. There is no image anywhere in the attendee-visible surface. |
| **Location sharing.** | Table number is the only location, it is a number on a floor plan, and it is not a person's position. |
| **Public exposure of legal name or email to another attendee, ever, including teammates.** | Team cards show first name + last initial. People swap contacts in person, in a supervised room. |

**Rejected mechanisms** (algorithmic, not safety):

- **Gale–Shapley / deferred acceptance for team formation.** It buys *stability*, and
  stability is purchased with visible rejection: a team provisionally holds you and drops you
  when a better applicant appears. That is precisely what 1.2 forbids and precisely what the
  Aaltoes experience was. It also may not exist at all with a team *minimum* size of 3
  (hospitals/residents with lower quotas), and it cannot seat one walk-in at 13:40 without
  re-running the whole match and churning everybody. We use a draft, not a market.
- **DA for challenge allocation only.** Defensible, and genuinely strategy-proof — but it
  buys strategy-proofness over a *hackathon theme*, which nobody games, at the cost of a
  week of PL/pgSQL, a largest-remainder seat distribution and a dissolve-and-rerun outer
  loop. Bucket + capacity ceiling + a 3-deep ranked fallback gets ~90% of the preference
  outcome for ~5% of the code.
- **Leximin / anticlustering exchange repair passes.** Better output on paper. It is a
  second algorithm, with its own termination proof, its own determinism hazards and its own
  scoring function to tune, and it exists to undo draft drift, which the *snake* ordering
  already undoes in one line of arithmetic. A second algorithm you cannot debug at 03:00 is
  worse than a slightly worse assignment you can read off a screen.
- **A separate algorithm for late arrivals.** `assign_late` is the same size arithmetic with
  a pool of one. Twenty lines.
- **Bounded swap-repair for blocked pairs (200 probes).** Expected violations at 500 people:
  0–3. Replaced by: skip excluded teams at deal time (free — it is already in the pick
  predicate), then next-ranked challenge, then a named exception that blocks publish. Deletes
  the hardest test surface in the design.

---

## Data model

Postgres 15 / Supabase, schema `public`. Baseline:

```sql
revoke all on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
```

RLS is enabled on **every** table below. Attendees never touch a base table that carries
personal data; they read two views and write through `security definer` RPCs. Roles are JWT
claims: `attendee` (default), `organizer`, `organizer_checkin`, `organizer_safety`, plus the
service role for the matcher.

Single event. `events` is a one-row config table so constants are editable without a deploy.
Generalising to a second event is an `event_id` on eight tables and one migration; that is a
deliberate trade and it will cost a weekend in 2027.

### Enums and helpers

```sql
create type role_t        as enum ('design','frontend','backend','hardware','ai_ml','business','media');
create type role_class_t  as enum ('build','craft','voice');
create type exp_t         as enum ('first_time','been_to_a_few','lots');
create type lang_t        as enum ('fi_only','en_only','both');
create type work_lang_t   as enum ('fi','en');
create type presence_t    as enum ('registered','confirmed','checked_in','left_early','no_show','cancelled');
create type link_dir_t    as enum ('request','invite');
create type link_state_t  as enum ('pending','accepted','withdrawn','dismissed','expired','superseded');
create type join_via_t    as enum ('founder','invite','request','auto','organiser','late','split');
create type team_state_t  as enum ('forming','active','disbanded');
create type team_origin_t as enum ('self_formed','auto','late_pool','organiser');
create type run_mode_t    as enum ('dry','full','repair','single');
create type run_state_t   as enum ('draft','previewed','published','discarded','failed');
create type bio_state_t   as enum ('none','pending','approved','rejected','removed');

-- build  = frontend, backend, hardware, ai_ml
-- craft  = design, media
-- voice  = business
create or replace function role_class(r role_t) returns role_class_t
language sql immutable as $$
  select case r
    when 'frontend' then 'build' when 'backend'  then 'build'
    when 'hardware' then 'build' when 'ai_ml'    then 'build'
    when 'design'   then 'craft' when 'media'    then 'craft'
    else 'voice' end::role_class_t $$;

-- exp_t -> integer. Used ONLY inside the matcher. Never returned to any client,
-- never rendered as a number, never sortable in any UI surface.
create or replace function exp_ord(e exp_t) returns smallint
language sql immutable as $$
  select case e when 'first_time' then 0 when 'been_to_a_few' then 1 else 2 end::smallint $$;
```

**Why three role classes and not "one of each of the seven roles".** With seven roles and a
target team size of four, "one of each role" is unsatisfiable and has no defined failure
behaviour. Three classes at size 4 is satisfiable, checkable in one expression, and is the
thing that actually matters: a team needs somebody who builds, somebody who makes it look and
sound like something, and somebody who can stand up and say what it is. `voice` has only one
role in it, so the enforced constraint is `has build AND has non-build`; `voice` presence is a
preview metric, not a gate.

### Configuration

```sql
create table events (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  tz                    text not null default 'Europe/Helsinki',
  starts_at             timestamptz not null,          -- 2026-10-24 09:00 EEST
  ends_at               timestamptz not null,          -- 2026-10-25 18:00 EEST
  challenges_frozen_at  timestamptz,                   -- must be set and <= matching_opens_at
  matching_opens_at     timestamptz not null,          -- T-7d
  assign_deadline_at    timestamptz,                   -- ADVISORY ONLY. Displayed, not enforced.
  matching_closed_at    timestamptz,                   -- stamped when an organiser presses the button
  switch_window_ends_at timestamptz,                   -- set at publish: publish + 40 min
  target_team_size      smallint not null default 4 check (target_team_size between 3 and 5),
  min_team_size         smallint not null default 3,
  max_team_size         smallint not null default 5,
  min_bucket_size       smallint not null default 6,
  max_open_links        smallint not null default 3,   -- per person and per team, each direction
  request_ttl_hours     smallint not null default 48,
  invite_ttl_hours      smallint not null default 12,
  block_cap             smallint not null default 10,
  bio_enabled           boolean  not null default false,  -- see Moderation. Default OFF.
  late_join_enabled     boolean  not null default true,
  reserve_tables        int[]    not null default '{}',
  terms_version         text not null,
  check (min_team_size <= target_team_size and target_team_size <= max_team_size)
);
```

**Decision: the matching deadline is a button, not a timestamp.** `assign_deadline_at` is
shown to attendees ("matching closes around 09:00"). What actually closes matching is an
organiser pressing **Close matching**, which stamps `matching_closed_at`, expires every
pending link, and computes `starved`. The opening ceremony will overrun. A cron job cannot
know that the mayor is still talking. This is five lines and it is the cheapest high-value
decision in the document.

```sql
create table challenges (
  id           smallint primary key,        -- small ints: readable in a log at 03:00
  event_id     uuid not null references events(id) on delete cascade,
  code         text not null,               -- 'HEALTH'
  title_fi     text not null,
  title_en     text not null,
  brief_fi     text not null,
  brief_en     text not null,
  brief_url    text,
  max_teams    smallint,                    -- null = uncapped
  state        text not null default 'draft' check (state in ('draft','published','withdrawn')),
  sort_order   smallint not null,
  unique (event_id, code)
);
```

**Rule, enforced by trigger:** the challenge-ranking UI refuses to open until every challenge
row for the event is `published` and `events.challenges_frozen_at` is set, and no challenge
may be inserted, deleted or have its `code`/titles changed after that timestamp. Ranking a
list that is later added to is meaningless, and a hidden or late-announced challenge taxonomy
is the single largest documented driver of people abandoning their assigned team. If the
sponsor is late with a brief, ranking opens late. The software will not let us make this
mistake.

**RLS.** `events`, `challenges`: `select` to `anon` **and** `authenticated` where
`state = 'published'` — the schedule, the challenge list, the venue map, the privacy policy
and the safety/contact page must all work logged out (Guideline 5.1.1(v)); an App Review
reviewer must be able to reach our published contact information without an account. All
writes: `organizer`.

### Registration, check-in, and the PII boundary

```sql
create table registrations (
  id               uuid primary key default gen_random_uuid(),
  event_id         uuid not null references events(id) on delete cascade,
  profile_id       uuid references profiles(id) on delete set null,
  ticket_code_hash text not null,            -- sha256(code || pepper); pepper lives in Supabase Vault
  legal_name       text not null,            -- organiser-only
  contact_email    text not null,            -- organiser-only
  guardian_consent_ref text,                 -- reference to the registration-system artefact, u16 only
  age_band         text check (age_band in ('u16','16_17','18_plus')),
  presence         presence_t not null default 'registered',
  checked_in_at    timestamptz,
  checked_in_by    uuid references profiles(id),
  badge_no         text,
  left_early_at    timestamptz,
  unique (event_id, ticket_code_hash),
  unique (event_id, badge_no)
);
create index on registrations (event_id, checked_in_at);
```

The ticket code is **hashed**, and legal name, email, age band and consent reference live
here, not on `profiles`. Nothing an attendee's RPC touches ever reads this table. This is
deliberate segregation: the matcher, the browse view, the team card and every attendee-facing
RPC can be audited by confirming they do not name `registrations`.

`checked_in_at` is written **only** by `organizer_checkin` (a badge scan or a manual desk
override) and is the sole gate on auto-assign eligibility. A free event for 15–19-year-olds
should plan for a 20–50% no-show rate. Assigning from the registration list guarantees
half-empty teams; assigning from check-in removes the no-show variable rather than
estimating it. `age_band` gates exactly one thing (see Moderation) and is never exposed to
any attendee.

**RLS.** `select` own row only, and only the columns `presence`, `checked_in_at`, `badge_no`
via the `my_registration` view (so the app can show "checked in ✓"). All writes:
`organizer_checkin` / `organizer`. `legal_name`, `contact_email`, `guardian_consent_ref`,
`age_band`: `organizer` and `organizer_safety` only.

### People

```sql
create table profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  event_id         uuid not null references events(id),

  display_name     text not null check (char_length(display_name) between 2 and 32),  -- "Aino K."

  -- the entire matching payload. Fixed taxonomy. No free text is read by the algorithm.
  primary_role     role_t,
  secondary_role   role_t,
  experience       exp_t,
  languages        lang_t,

  -- intent
  wants_team       boolean not null default true,     -- false = "I'm working solo this time"
  solo_opted_at    timestamptz,
  looking_for_team boolean not null default false,    -- affirmative opt-in to being browsable
  wants_late_seat  boolean not null default true,     -- "if I arrive late, seat me anyway"

  -- UGC, disabled by default at event level
  bio              text check (bio is null or char_length(bio) between 12 and 180),
  bio_status       bio_state_t not null default 'none',
  bio_submitted_at timestamptz,
  bio_reviewed_by  uuid references profiles(id),
  bio_reviewed_at  timestamptz,

  starved          smallint not null default 0,       -- closed outbound links with zero acceptances
  terms_version    text,
  terms_accepted_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint secondary_differs  check (secondary_role is distinct from primary_role),
  constraint solo_not_browsable check (not (wants_team = false and looking_for_team)),
  constraint browsable_is_complete check (
    not looking_for_team
    or (primary_role is not null and experience is not null and languages is not null
        and terms_accepted_at is not null))
);
```

```sql
create table challenge_prefs (
  profile_id   uuid not null references profiles(id) on delete cascade,
  rank         smallint not null check (rank between 1 and 3),
  challenge_id smallint not null references challenges(id),
  primary key (profile_id, rank),
  unique (profile_id, challenge_id)
);
```

**Exactly three ranked challenges are required** before `looking_for_team` may be set true or
before the person enters the auto-assign pool — enforced by a trigger, not by the client. A
one-deep preference list is what forces first-choice-only bucketing, and every fallback rung
in the algorithm assumes three exist. Three, not seven: a full ranked list over seven topics
is a surprisingly rich profile of a person, and only the matcher ever needs even these.

**RLS.** No direct grants on `profiles`. Self read/write through the `me` view
(`id = auth.uid()`), which excludes `starved`. `starved` is written by trigger only, never by
a client, and is never displayed to anybody, including its owner — it is a scheduling input,
not a status. Other attendees reach profile data only through `attendee_cards`. Bios with
status other than `approved` are readable by the author and `organizer_safety` only.

### Teams

```sql
create table teams (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id),
  number        int,                         -- "Team 12". Assigned at publish. IMMUTABLE thereafter.
  table_number  int,                         -- physical table. IMMUTABLE once announced.
  challenge_id  smallint references challenges(id),
  working_lang  work_lang_t,
  name          text,                        -- optional, <=40 chars, SAME moderation trigger as bio
  captain_id    uuid references profiles(id),
  state         team_state_t not null default 'forming',
  origin        team_origin_t not null default 'self_formed',
  accepts_late  boolean not null default false,   -- captain opt-in, prompted at 09:30
  locked        boolean not null default false,   -- organiser freeze; auto-assign must not touch
  locked_reason text,
  disbanded_at  timestamptz,
  disbanded_reason text check (disbanded_reason in
                  ('collapsed_below_min','split','organiser','safety')),
  created_at    timestamptz not null default now(),
  unique (event_id, number),
  unique (event_id, table_number)
);

create table team_gaps (
  team_id     uuid not null references teams(id) on delete cascade,
  role        role_t not null,
  seats       smallint not null check (seats between 1 and 4),
  declared_by uuid not null references profiles(id),
  declared_at timestamptz not null default now(),
  primary key (team_id, role)
);

create table team_members (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references teams(id) on delete cascade,
  profile_id   uuid not null references profiles(id) on delete cascade,
  role_in_team role_t not null,              -- printed on the placard
  joined_via   join_via_t not null,
  joined_at    timestamptz not null default now(),
  left_at      timestamptz,
  left_reason  text check (left_reason in ('self','organiser','safety','split','no_show')),
  pinned       boolean not null default false,   -- true once a push has been sent about this seat
  notified_at  timestamptz,
  run_id       uuid                              -- provenance
);
create unique index one_active_team_per_person
  on team_members (profile_id) where left_at is null;
create index on team_members (team_id) where left_at is null;
```

Three load-bearing lines here:

1. **`one_active_team_per_person`.** A partial unique index makes "person is on two teams"
   unrepresentable. The accept/accept race is dead at the storage layer, not in application
   logic that somebody will forget to copy into the next RPC.
2. **`team_gaps` is consent, recorded.** A team with no `team_gaps` row is never a placement
   target for anybody — not a request, not an invite, not auto-assign, not the organiser's
   drag-and-drop without a logged forced override. Three friends who signed up together and
   did not ask for a fourth will not welcome one, and one shy stranger dropped into three
   friends is the single worst individual experience this event can produce.
3. **`left_reason` is an enum, not free text.** So is `disbanded_reason`. These fields
   describe named other attendees and would otherwise be an unmoderated UGC channel printed
   into an organiser console.

`team_members` rows are never deleted; departure sets `left_at`. The history is the audit
trail somebody needs at 22:00 when an attendee says "I was never on that team".

**Numbers and tables are immutable after publish.** A disbanded team's number and table are
retired for the rest of the event. Renumbering an announced team is the cheapest possible way
to lose thirty people in a corridor.

### The one link table

```sql
create table link_requests (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references events(id) on delete cascade,
  team_id     uuid not null references teams(id) on delete cascade,
  profile_id  uuid not null references profiles(id) on delete cascade,
  direction   link_dir_t not null,     -- 'request' = person -> team (A); 'invite' = team -> person (B)
  role_code   role_t not null,         -- the ENTIRE payload. No free text ever crosses.
  state       link_state_t not null default 'pending',
  created_at  timestamptz not null default now(),
  seen_at     timestamptz,             -- recorded; NEVER revealed to the sender
  expires_at  timestamptz not null,
  resolved_at timestamptz,
  resolved_by uuid references profiles(id),
  created_by  uuid not null references profiles(id)
);

create unique index one_live_link on link_requests (team_id, profile_id) where state = 'pending';
create index on link_requests (profile_id) where state = 'pending';
create index on link_requests (team_id)    where state = 'pending';
create index on link_requests (expires_at) where state = 'pending';
```

**Decision: Mechanic A and Mechanic B are one table, one state machine, one expiry cron, one
RLS policy set, one visibility projection, one SwiftUI component with the arrow reversed.**
This is the largest single line-count saving in the design and it removes an entire class of
"invites expire but requests don't" divergence. The only asymmetries are the TTL and the
precondition set, both of which are parameters.

**RLS.** `select` where `profile_id = auth.uid()` **or** `team_id` is a team the caller is
currently a member of. No `insert`/`update` grants at all — everything goes through
`security definer` RPCs so quotas, TTLs, exclusion checks and the visibility projection are
enforced server-side. Nothing anywhere exposes an aggregate over this table to a third party;
no query path can compute a per-person rejection tally, because non-pending rows are visible
only to their own two parties.

### Safety

```sql
create table blocks (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index on blocks (blocked_id);

create table safety_separations (      -- organiser-imposed keep-apart; survives to next year
  user_a     uuid not null references profiles(id) on delete cascade,
  user_b     uuid not null references profiles(id) on delete cascade,
  reason     text not null,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create view match_exclusions as
  select least(blocker_id, blocked_id) as a, greatest(blocker_id, blocked_id) as b from blocks
  union
  select user_a, user_b from safety_separations;
revoke all on match_exclusions from anon, authenticated;
```

**RLS.** `blocks`: read / insert / delete your own **outgoing** rows only
(`blocker_id = auth.uid()`). **No policy grants the blocked party any read.** Blocking is
invisible to its target by construction, not by UI discipline. `safety_separations`:
`organizer_safety` only. `match_exclusions` is reachable only by `security definer` functions
and by `organizer_safety` through a view that writes an `audit_log` row on every read.

```sql
create table reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references profiles(id) on delete set null,
  subject_id  uuid references profiles(id) on delete set null,
  subject_kind text not null check (subject_kind in ('profile','bio','team_name','conduct')),
  category    text not null check (category in
                ('harassment','sexual_content','hate_speech','threat',
                 'contact_solicitation','impersonation','spam','safety_concern')),
  details     text check (details is null or char_length(details) <= 500),
  state       text not null default 'open' check (state in ('open','actioned','dismissed')),
  created_at  timestamptz not null default now(),
  first_action_at timestamptz,          -- instruments the PUBLISHED SLA
  actioned_by uuid references profiles(id),
  action_note text
);

create table moderation_terms (
  term       text primary key,
  lang       text not null,
  severity   text not null check (severity in ('block','flag')),
  match_kind text not null default 'prefix' check (match_kind in ('exact','prefix','substring'))
);
create table moderation_allowlist (term text primary key);

create table moderation_attempts (     -- 90-day retention, see Moderation
  id         bigserial primary key,
  profile_id uuid references profiles(id) on delete cascade,
  field      text not null,
  matched_term text,                   -- the LEXICON term, not the user's sentence
  raw_hash   text not null,            -- sha256 of the rejected text, for repeat detection
  reason     text not null,
  created_at timestamptz not null default now()
);

create table audit_log (
  id bigserial primary key, actor_id uuid, action text not null,
  subject_id uuid, detail jsonb, created_at timestamptz not null default now()
);

create table account_deletions (id_hash text primary key, requested_at timestamptz not null default now());
create table safety_holds (
  id_hash text primary key, kind text not null, counterpart_hash text, reason text not null,
  expires_at timestamptz not null default now() + interval '24 months'
);
```

### Run machinery

```sql
create table match_runs (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id),
  mode          run_mode_t not null,
  state         run_state_t not null default 'draft',
  salt          text not null default encode(gen_random_bytes(16),'hex'),
  snapshot_at   timestamptz not null default now(),
  roster_basis  text not null default 'checked_in'
                check (roster_basis in ('checked_in','registered')),
  params        jsonb not null,          -- sizes, caps, churn budget, config snapshot
  parent_run_id uuid references match_runs(id),
  created_by    uuid not null references profiles(id),
  metrics       jsonb,
  published_at  timestamptz,
  published_by  uuid references profiles(id),
  failed_reason text
);

-- FROZEN INPUTS. Real tables, not temp tables. Preview and publish read ONLY these.
create table run_pool (
  run_id uuid not null references match_runs(id) on delete cascade,
  profile_id uuid not null,
  unit_id uuid not null,                  -- singletons: unit_id = profile_id
  unit_size smallint not null,
  primary_role role_t not null, secondary_role role_t,
  experience exp_t not null, languages lang_t not null,
  starved smallint not null,
  pref1 smallint, pref2 smallint, pref3 smallint,
  primary key (run_id, profile_id)
);
create table run_seats (
  run_id uuid not null references match_runs(id) on delete cascade,
  team_id uuid not null, seat_index smallint not null,
  wanted_role role_t, is_new_team boolean not null, bucket_key text,
  primary key (run_id, team_id, seat_index)
);
create table run_exclusions (
  run_id uuid not null references match_runs(id) on delete cascade,
  a uuid not null, b uuid not null, primary key (run_id, a, b)
);

-- OUTPUTS
create table run_placements (
  run_id uuid not null references match_runs(id) on delete cascade,
  profile_id uuid not null,
  team_id uuid not null,                  -- provisional id for new teams, minted at Phase 3
  bucket_key text not null,
  seq int not null,                       -- draft pick number, for the explanation
  proposed_role role_t not null,
  reason_code text not null,
  flags text[] not null default '{}',
  is_move boolean not null, was_pinned boolean not null, previous_team_id uuid,
  primary key (run_id, profile_id)
);
create table run_teams (
  run_id uuid not null references match_runs(id) on delete cascade,
  team_id uuid not null, challenge_id smallint, working_lang work_lang_t,
  size smallint not null, is_new boolean not null, table_number int,
  has_build boolean, has_nonbuild boolean, distinct_roles smallint,
  exp_spread int, rank_cost int, flags text[] not null default '{}',
  primary key (run_id, team_id)
);
create table run_exceptions (
  run_id uuid not null references match_runs(id) on delete cascade,
  profile_id uuid not null,
  kind text not null,                     -- 'unseatable_exclusions' | 'no_language_bucket'
                                          -- | 'remainder_unseatable' | 'beyond_preferences'
                                          -- | 'merge_loop_cap'
  detail text, suggested_action text,
  acknowledged_by uuid, acknowledged_note text,
  primary key (run_id, profile_id, kind)
);

create table placement_trace (            -- survives the run; powers "why am I here"
  profile_id uuid primary key references profiles(id) on delete cascade,
  team_id uuid, run_id uuid, reason_code text not null,
  reason_fi text not null, reason_en text not null,
  created_at timestamptz not null default now()
);

create table organiser_actions (          -- every manual override, append-only
  id bigserial primary key, event_id uuid, actor uuid not null, action text not null,
  target_profile uuid, target_team uuid, payload jsonb, reason text not null,
  forced boolean not null default false, at timestamptz not null default now()
);
```

**Decision: run inputs are persisted, not temp tables.** If `publish_run` re-derives the pool
from live data, the published result can silently differ from the preview the organiser
approved sixty seconds earlier — the number-one production defect class in any
preview-then-publish design. Freezing the inputs into real tables keyed by `run_id` makes
"preview equals publish" a property of the code, not a hope.

**RLS.** All `run_*`: `organizer` read, service role write. `placement_trace`: readable by
`organizer` **and** by its own `profile_id` after the run is published — this one policy is
what turns a reason code into an in-app "why am I on this team" line, and it is the answer
when somebody walks up to an organiser at 09:05. `organiser_actions`: append-only, readable
by `organizer` and `organizer_safety`.

### Views attendees may read

```sql
create view team_cards with (security_invoker = true) as
select t.id, t.number, t.table_number, t.challenge_id, t.working_lang, t.name,
       (select count(*) from team_members m where m.team_id = t.id and m.left_at is null) as size,
       coalesce((select array_agg(g.role order by g.role) from team_gaps g where g.team_id = t.id),
                '{}') as needed_roles,
       t.accepts_late
from teams t
where t.state <> 'disbanded'
  and is_confirmed_attendee(auth.uid());

create view attendee_cards with (security_invoker = true) as
select p.id, p.display_name, p.primary_role, p.secondary_role, p.experience, p.languages,
       (select challenge_id from challenge_prefs cp where cp.profile_id = p.id and cp.rank = 1)
         as first_choice_challenge,
       case when p.bio_status = 'approved' and (select bio_enabled from events limit 1)
            then p.bio end as bio
from profiles p
where p.looking_for_team
  and p.wants_team
  and current_stage() in ('S2','S3')
  and is_confirmed_attendee(auth.uid())
  and captains_a_team_with_a_gap(auth.uid())
  and p.primary_role = any (roles_needed_by_teams_captained_by(auth.uid()))
  and not exists (select 1 from match_exclusions me
                   where me.a = least(p.id, auth.uid()) and me.b = greatest(p.id, auth.uid()));
```

Note what `attendee_cards` **does not** contain: no invite counter, no request counter, no
`starved`, no aggregate of any kind. The anti-neglect ordering that Mechanic B needs is
computed inside a `security definer` RPC that returns an ordered list of ids and never returns
the counter it sorted on. A client-readable "invites received" column is a per-person
popularity metric that any attendee holding the public anon key could select across every
browsable person — that is exactly the leaderboard Guideline 1.2 forbids, materialised by
accident.

---

## Mechanic A — request to join

A person taps **Request to join** on a team card. The captain accepts, or silently does not.

**Preconditions**, all checked in `rpc_send_link(team_id, 'request', role)`:

- caller has `wants_team`, a complete profile, three ranked challenges, accepted terms;
- caller has no active team;
- target team is `forming` or `active`, not `locked`, not `disbanded`, `size < max_team_size`;
- target team has a `team_gaps` row for `role` with `seats > 0`;
- no `match_exclusions` pair between the caller and any current member;
- caller holds fewer than `max_open_links` (3) pending outbound links;
- the team holds fewer than 8 pending inbound links (spam ceiling, not a quality signal);
- **no terminal `link_requests` row already exists for this `(team_id, profile_id)` pair in
  the current matching window, in either direction.** One approach per pair per window. This
  precondition is the one that stops a dismissal being followed by an unlimited stream of
  fresh requests, which would defeat the entire point of a silent dismissal.

`expires_at = least(now() + 48 hours, events.matching_closed_at)`. If `matching_closed_at`
is still null, the second term is ignored and pressing **Close matching** expires the row.

### States

| State | Terminal | Meaning |
|---|---|---|
| `pending` | no | Live. Counts against both quotas. |
| `accepted` | yes | Person joined the team. |
| `withdrawn` | yes | The sender pulled it back. |
| `dismissed` | yes | The recipient tapped "Not right now". |
| `expired` | yes | TTL elapsed, or matching was closed. |
| `superseded` | yes | Auto-closed: the person joined some team, or the team filled / locked / disbanded, or an exclusion appeared. |

There is no reopen. You send a fresh row in a fresh window, or you do not.

### Transitions

| From → To | Trigger | Effects, all in one transaction |
|---|---|---|
| `∅ → pending` | `rpc_send_link` | Preconditions above. |
| `pending → accepted` | captain `rpc_accept_link` | Insert `team_members` (the exclusion guard may abort → neutral failure, see Blocked pairs); decrement `team_gaps.seats`, deleting the row at 0; set all the joiner's other pending links to `superseded`; if the team is now at `max_team_size`, supersede its remaining inbound links; reset the joiner's `starved` to 0. |
| `pending → dismissed` | captain "Not right now" | Nothing else. No notification. No counter. `starved` on the sender increments. |
| `pending → withdrawn` | sender | Quota returns. `starved` unchanged. |
| `pending → expired` | cron, or Close matching | `starved` on the sender increments. |
| `pending → superseded` | joiner joined elsewhere / team full / locked / disbanded / exclusion appeared | Silent. |

### What each party sees

| Actual state | Sender sees | Recipient sees |
|---|---|---|
| `pending` | "Sent — Team 14 · closes in 41 h", with Withdraw. Counts 1 of 3. | Inbox card: display name, primary and secondary role, experience band, first-choice challenge, approved bio if bios are enabled. Accept / Not right now. |
| `pending`, `seen_at` set | **still exactly "Sent"** | — |
| `accepted` | "You're on Team 14" + roster | roster updates |
| `dismissed` | **"This request is closed — your slot is free."** | card silently disappears |
| `expired` | **"This request is closed — your slot is free."** | card silently disappears |
| `superseded` | **"This request is closed — your slot is free."** | card silently disappears |
| `withdrawn` | "You withdrew this." | card silently disappears |

Three distinct terminal outcomes collapse to one byte-identical string. That is the
Guideline 1.2 requirement, and it is also just kinder to a 16-year-old.

**`seen_at` is recorded and never revealed.** The research finding that drives this whole
design is that an ignored request is indistinguishable from an unseen one, and that
ambiguity is the core defect of a passive board. The fix is to have the *system* resolve the
ambiguity — with a visible countdown and a guaranteed terminal state — not to hand a
teenager "seen 6 hours ago, no reply", which manufactures the exact rejection experience we
are engineering away. `seen_at` exists so the organiser console can nudge a slow captain.

### The `starved` counter

Every closed-without-acceptance outbound link increments `profiles.starved`. It is:

- never shown to its owner, never shown to anybody else, never included in any view;
- the **first** sort key in the auto-assign draft order.

The person who tried hardest and got nothing is the organiser at Aaltoes. This design pays
them back automatically: their expired requests buy them the first pick in the draft. That is
the mechanism that converts silence into information rather than into shame.

---

## Mechanic B — invite

A captain of a team with a declared gap taps **Invite** on a person card. Same table, same
state machine, `direction = 'invite'`. Differences:

- `expires_at = least(now() + 12 hours, matching_closed_at)`. Shorter, because a pending
  invite occupies one of a minor's three inbound slots and a slow captain must not be able to
  park a person for two days.
- A team holds at most 3 outstanding invites; a person receives at most 3 pending invites.
- `pending → superseded` additionally when the `team_gaps` row for `role_code` hits zero.
- **The invite body is a fixed localised string plus one enum value**, rendered client-side:
  *"Tiimi 14 etsii **suunnittelijaa**. Haluatko liittyä?"* / *"Team 14 needs a **Designer**.
  Want to join?"* Zero attacker-controlled characters travel between two strangers.
- Declining is one tap labelled **"Not this one"** and it is silent.
- **The captain is protected symmetrically.** A dismissed, expired or superseded invite
  renders to the captain as "This invitation is closed" with no distinction between "they
  said no" and "it timed out". Captains are 16 too.

### Who can browse whom

Browsing people is gated three ways simultaneously:

1. the viewer holds a confirmed ticket for the event, and
2. the viewer captains a team that has at least one open `team_gaps` row, and
3. the list is filtered to people whose `primary_role` is one of the roles that viewer's
   teams are actually missing.

and the target must have set `looking_for_team = true` themselves. There is no general
"browse all attendees" surface. ~500 minors are not free to read each other's free text.

**The one ordering of people in this product.** The filtered list is ordered by
`(pending_invites_received asc, pending_requests_sent desc, md5(viewer_team_id || profile_id))`.
People with zero invites surface first, to every captain independently. This is the
structural answer to the Aaltoes problem *inside the voluntary mechanics*, before the safety
net ever runs: the quiet person is at the top of everybody's list rather than the bottom.

It is legitimate under 1.2 because it ranks **neglect**, not people — a person moves *down*
the list as they receive attention, so the ordering carries no quality signal and cannot be
read as a score. The counters it sorts on are never returned to the client. **This ordering
gets an explicit paragraph in the App Review notes.** It is the one thing in the app that a
reviewer could mistake for a ranking, and the cheapest way to survive that is to explain it
before they ask.

---

## Mechanic C — auto-assign safety net

One PL/pgSQL function, `preview_assign(run_id, mode)`, plus a separate `publish_run(run_id)`.
Deterministic under a stored salt, explainable per person, and runnable in under a second on
500 people.

Modes: `dry` (rehearsal, may run on registrations, hard-labelled UNRELIABLE), `full` (the
09:00 run), `repair` (minimum-churn reconciliation later in the event), `single` (one walk-in).
There are four modes and there will not be a fifth.

### Inputs

```
EVENT   T = target_team_size = 4,  L = min_team_size = 3,  U = max_team_size = 5
        min_bucket_size = 6, challenges with max_teams
SALT    match_runs.salt — persisted, reused byte-for-byte by publish
POOL    profiles p joined to registrations r where
          r.presence = 'checked_in'                       <- THE hard gate
          AND p.wants_team
          AND p.primary_role IS NOT NULL AND p.experience IS NOT NULL
              AND p.languages IS NOT NULL
          AND 3 ranked challenges exist
          AND (no active team_members row
               OR their team is NON-VIABLE, see Phase 1)
SEATS   teams t where NOT t.locked AND t.state <> 'disbanded'
          AND EXISTS (team_gaps for t)
          AND active size < U
        expanded one row per declared gap seat
EXCL    match_exclusions, snapshotted ONCE at snapshot_at
PARAMS  churn_budget, merge_cap
```

Everything else in the database is invisible to this function. **In particular it never reads
`bio`, `name`, `display_name`, `legal_name` or any other free text.** That is why a bio held
for moderation costs matching exactly nothing, and it is why bios can ship disabled.

**Determinism rule, schema-wide and non-negotiable:** *every* `ORDER BY` inside the matcher
terminates in `md5(profile_id || salt)` or in `team_id` — including the choice of which
bucket to dissolve, which side receives a bilingual, and which team a tie-broken pick goes to.
Postgres guarantees no ordering without a total order, and a preview that disagrees with the
publish destroys the only control that makes this feature safe to ship. The organiser preview
carries a **Re-run identical (same salt)** button that diffs the two runs row by row; it
exists specifically to catch a tie-break somebody forgot.

### Algorithm

#### Phase 0 — snapshot and freeze

```
0.1  pg_advisory_xact_lock(hashtext(event_id::text))   -- one run at a time, ever
0.2  Copy pool, seats, exclusions, prefs into run_pool / run_seats / run_exclusions.
0.3  Stamp snapshot_at. Every later phase reads ONLY these three tables.
0.4  If a published run exists with published_at > snapshot_at -> abort STALE.
```

#### Phase 1 — triage existing teams, build units

```
1.1  Classify every non-disbanded team:
       LOCKED     : teams.locked                        -> capacity 0, members untouchable
       CLOSED     : active size >= L and no team_gaps    -> capacity 0, members untouchable
       OPEN       : has team_gaps and size < U           -> capacity = min(sum(gaps.seats), U - size)
       NON_VIABLE : active size < L                      -> 1.2
1.2  NON_VIABLE handling:
       size 0 -> disband, no unit.
       size 1 -> disband; the member is a unit of 1,  reason 'team_collapsed'.
       size 2 -> disband; the PAIR IS ONE UNIT OF 2,  reason 'team_collapsed_pair'.
       If any member is pinned and mode = 'repair' and size = 2:
         do NOT disband. Raise a preview flag 'team_non_viable' and leave them alone.
         A team of two that has been building for eight hours is not the same object
         as a team of two at 09:00.
1.3  Every other pool member is a unit of 1.
1.4  Unit attributes:
       size; role multiset;
       lang_class = fi_only if any member is fi_only and none is en_only
                    en_only if any member is en_only and none is fi_only
                    both    if every member is 'both'
                    (fi_only + en_only in one unit is FORBIDDEN AT CREATION, see below)
       prefs      = Borda sum over members (3/2/1 for ranks 1/2/3), ties by lowest hash
       starved    = max over members
       rarity     = min(role_rarity) over members, computed per bucket after merging
```

**Decided: units exist only for collapsed pairs.** No user-declared "place us together"
pairs in v1. Declared pairs are elegant and are a bug farm: every ordering, capacity check
and pick becomes size-aware, and a mixed-language pair is unseatable in a language-partitioned
bucket by construction. Collapsed pairs are the case that actually occurs on the day —
two people who already chose each other and lost their teammates — and they are worth the
twenty lines. If we ever add declared pairs, `rpc_declare_pair` must reject a pair whose
members do not share a working language.

#### Phase 2 — bucketing (challenge × working language)

```
2.1  lang_class per person: fi_only | en_only | both.
2.2  Provisionally bucket every fi_only and en_only unit into its rank-1 challenge:
       bucket_key = challenge_id || ':' || ('fi'|'en')
     Bilingual ('both') units go to a FLEX holding pool.
     If a challenge has zero en_only people, it has one bucket, work_lang 'fi'.
     If it has zero fi_only people, one bucket, work_lang 'en'.

2.3  FLEX ALLOCATION  -- runs BEFORE the merge, and this ordering is the whole point.
     Sort FLEX units by (starved desc, unit_size desc, rarity asc, md5(profile_id||salt)).
     Deal them, one at a time, to the bucket with the greatest deficit, where
       deficit(b) = max(0, L - population(b)) * 1000 + ((-population(b)) mod T)
     restricted to buckets in one of that unit's three ranked challenges.
     Stop when FLEX is exhausted or every deficit is zero.
     Leftover FLEX units go to the bucket of their highest-ranked challenge,
       tie-broken by (population asc, challenge.sort_order asc, work_lang asc).
     reason 'bilingual_rescue' whenever a FLEX unit was placed to lift a bucket to >= L
     or to smooth a remainder.

2.4  CAPACITY CEILING. For each challenge c with max_teams = M (not null):
     while total population across c's buckets > M * U:
       move the unit with the smallest Borda margin between its current challenge and
       its next ranked challenge (ties: smaller unit, then hash) into that next bucket.
       reason 'challenge_over_capacity_moved_to_choice_k'.
     Never move a rank-1 unit while a rank-3 unit remains in the bucket.

2.5  UNDERSIZED BUCKET MERGE. iter := 0.
     loop:
       iter := iter + 1
       if iter > merge_cap (= number of buckets + 1):
         write run_exceptions(kind='merge_loop_cap') for everyone still in an
         undersized bucket and BREAK. Never spin, never fall through silently.
       b := the bucket with population < min_bucket_size (6), chosen by
            (population asc, challenge.sort_order asc, work_lang asc)   <- total order
       if none: exit loop
       dissolve b. For each unit in b, in hash order, move it to the bucket of its
       next ranked challenge with the SAME work_lang, that is not itself dissolved.
       If its ranks are exhausted: move it to the largest surviving bucket with the
       same work_lang, reason 'no_ranked_challenge_available'.
       If NO bucket with that work_lang survives anywhere:
         write run_exceptions(kind='no_language_bucket', profile_id, suggested_action=
           'Seat manually, or pair with a bilingual team') and remove from the pool.
     Bucket count strictly decreases each iteration, so the loop terminates on its own;
     merge_cap is a seatbelt, not the termination argument.
```

**Why language is a partition and not a tie-break.** A tie-break fires only when everything
else is equal, which is almost never. A Finnish-only 16-year-old dealt onto an all-English
table is a *total* failure — worse than any role duplicate, worse than a third-choice
challenge. But note the asymmetry: the harm is the **isolation of one person**, not mixing.
So we partition on isolation only, and bilinguals are a deliberate flex pool that crosses the
divide, fixes remainders and gives a Finnish-working team somebody who can talk to
English-speaking mentors and judges. Mixing still happens; isolation does not.

**Why FLEX is allocated before the merge.** If bilinguals sit in a holding pool while the
merge dissolves undersized buckets, the rescue mechanism can never rescue: a challenge with
2 English-only speakers and 40 bilinguals dissolves its English side while 40 people who
could have saved it do nothing. One block ordering, and it is the difference between a live
mechanism and a dead one.

#### Phase 3 — team count and sizes

```
3.1  For each bucket b:  n_b = people in the bucket (units expanded)
                         g_b = declared-gap seats in OPEN existing teams in b
3.2  m_b = n_b - g_b        <- people who need brand-new teams. SUBTRACT FIRST.
3.3  if m_b = 0: no new teams in b. Proceed to Phase 4.
3.4  if m_b in {1, 2}:
       (a) Hold back (L - m_b) declared-gap seats in b -- leave those gaps UNFILLED --
           so m_b rises to L and one viable team of 3 can form. An unfilled declared
           gap is harmless; a team of 2 is the original failure wearing a hat.
       (b) else move those m_b people to their next ranked challenge bucket,
           reason 'remainder_moved_to_choice_k', and recompute that bucket.
           Bounded: one retry per person.
       (c) else write run_exceptions(kind='remainder_unseatable'). NEVER form a team
           of 1 or 2. A human seats one or two people.
3.5  k_b = clamp( round_half_up(m_b / T),  ceil(m_b / U),  floor(m_b / L) )
     q = m_b div k_b ;  r = m_b mod k_b
     -> r teams of size q+1, (k_b - r) teams of size q
     ASSERT every produced size is in [L, U].
3.6  Mint the new teams with provisional ids and bucket_key. Numbers and table numbers
     are allocated at PUBLISH, from the reserve pool if the run is after
     matching_closed_at. Existing teams keep their number and their table. Always.
```

The `m_b = n_b − g_b` subtraction in 3.2 and the `m_b < 3` guard in 3.4 are the two lines
that stop this phase producing a degenerate team. Choosing `k` from `n_b` and *then* letting
declared gaps eat the same people produces teams of two, and the assertion in 3.5 passes
before the damage happens.

#### Phase 4 — seat list

```
4.1  Expand each OPEN existing team in the bucket into one seat per declared gap seat,
     tagged wanted_role.
4.2  Expand each new team into (its size) untagged seats.
4.3  Order teams within the bucket:
       existing-with-declared-gap first, by (open_seats desc, team.number asc),
       then new teams by provisional index.
     Filling a gap of 2 before a gap of 1 is deliberate: putting TWO strangers into a
     two-seat gap together is a categorically different social experience from putting
     one stranger into three friends.
```

#### Phase 5 — the draft order

```
5.1  role_rarity(r) = count of people in THIS bucket, AFTER merging, with primary_role = r.
     Rarity is per bucket. Computing it globally places globally-scarce roles into
     buckets that do not need them: hardware may be 11-of-500 globally and the most
     common role inside the Robotics bucket.
     rarity_rank = dense_rank ascending by count, ties by role_t enum ordinal.

5.2  Queue Q, per bucket:
       row_number() over (partition by bucket_key order by
          starved              desc,   -- 1. tried hardest, got nothing -> first pick
          unit_size            desc,   -- 2. pairs are harder to place; place them early
          rarity_rank          asc,    -- 3. rarest primary role first
          exp_ord(experience)  desc,   -- 4. strongest first within a rarity tier
          md5(profile_id::text || salt) -- 5. total order. Never omit this.
       ) - 1 as seq
```

#### Phase 6 — the snake draft

```
6.1  For a bucket with k teams and size vector S[1..k]:
       round    := seq div k
       pos      := seq mod k
       base_ix  := (round even) ? pos : (k - 1 - pos)
     Visit teams from base_ix onward in that round's direction, skipping any team
     already at S[i]. The first team with a free seat is this pick's team.

6.2  PICK PREDICATE. For team i, scan the remaining queue in order and take the first
     candidate satisfying the highest-priority rule that any remaining candidate can
     satisfy:
       (a) HARD: no match_exclusions pair with any current or already-placed member of i
       (b) HARD: candidate's lang_class is compatible with i's working language
       (c) if seat has wanted_role: candidate's primary_role = wanted_role,
           else candidate's secondary_role = wanted_role
       (d) candidate's role_class is ABSENT from team i
       (e) candidate's primary_role is ABSENT from team i
       (f) queue order
     Rules (a) and (b) are filters. Rules (c)-(e) are preferences applied in order:
     take the first candidate satisfying (c); if none, the first satisfying (d);
     if none, the first satisfying (e); otherwise the head of the queue.

6.3  If NO candidate satisfies (a) and (b) -- i.e. every remaining person is excluded
     from this team or speaks the wrong language -- leave the seat and continue; the
     stranded person is handled at 6.5.

6.4  role_in_team := primary_role if the team does not already have it,
                     else secondary_role if free, else primary_role anyway.

6.5  Anyone still unplaced after the bucket is exhausted:
       -> try their next ranked challenge bucket, one retry, reason
          'blocked_moved_to_choice_k'
       -> else run_exceptions(kind='unseatable_exclusions', suggested_action=
          'Seat manually; excluded from N of M teams in this bucket')
     There is NO swap-repair pass. See "Blocked pairs".
```

**Why a snake and not plain round-robin.** Three properties in one line of arithmetic:

- **Round 1 touches every team exactly once.** Because the queue is rarity-ascending, the
  scarcest role is dealt one-per-team before any team receives a second of anything. The rule
  "never double a role until every team has one" does not need to be checked; it is a
  *consequence* of the ordering, and it degrades gracefully — 11 hardware people across 30
  teams gives 11 teams a hardware person, with no undefined behaviour, where the rule as
  originally stated had none.
- **The snake cancels draft drift.** Plain modulo gives team 1 picks 1, k+1, 2k+1 —
  systematically the best of every round, and the last team the worst of every round, with
  nothing noticing. The snake gives team 1 picks 1 and 2k, and team k picks k and k+1.
  Because the fourth sort key is experience descending, mean experience across teams
  equalises to within roughly one band with **no optimisation pass at all**. This is the
  entire reason we do not need an exchange-repair phase, and it is why one was rejected.
- **It is explainable to a 16-year-old in one sentence.** "It's a draft, like picking teams,
  and it snakes back so nobody gets all the first picks."

#### Phase 7 — churn control (modes `repair` and `single` only)

```
7.1  Every already-notified placement (team_members.pinned) enters the run PINNED into
     its current seat and is excluded from Phases 5 and 6.
7.2  A pinned person is unpinned only if their team is NON_VIABLE and cannot be topped
     up from the pool inside this run.
7.3  churn_budget default for mode 'repair' = the number of people in NON_VIABLE teams,
     NOT zero. (A default of zero fails the mode on precisely the case it exists for.)
     If |moves where was_pinned| > churn_budget, the run FAILS with a named reason.
     It does not silently reshuffle 200 teenagers.
7.4  The objective in repair mode is FEWEST MOVES, not best composition. A second
     "actually you're on Team 40 now" push is strictly worse than a slightly
     suboptimal team, for exactly the nervous person this system exists to protect.
```

#### Phase 8 — flags, reasons, metrics

```
8.1  One run_placements row per person with an enumerated reason_code. Complete list:
       dealt_rarest_role · dealt_general · filled_declared_gap ·
       starved_priority_placement (internal only, never shown) ·
       bilingual_rescue · bucket_merged_moved_to_choice_k ·
       challenge_over_capacity_moved_to_choice_k · remainder_moved_to_choice_k ·
       blocked_moved_to_choice_k (internal only) · no_ranked_challenge_available ·
       kept_with_collapsed_pair · pinned_unchanged · organiser_manual ·
       late_seat_open_team · late_pool_new_team
8.2  Team flags written to run_teams.flags:
       no_builder · no_communicator · duplicate_role ·
       solo_into_established_team   (exactly one member with joined_via='auto'
                                     joining a team with >= 3 self-formed members)
       lone_novice                  (exactly one member with experience='first_time'
                                     AND every other member is 'lots' -- nobody at the
                                     adjacent band to bridge to)
     lone_novice and solo_into_established_team are PREVIEW FLAGS, not constraints.
     Encoding either as a hard constraint is what forces a repair pass into existence.
8.3  Metrics into match_runs.metrics:
       % on 1st / 2nd / 3rd choice challenge; % placed beyond their preferences;
       % whose primary role is duplicated in their team;
       teams with no builder; teams with no communicator;
       team size histogram; per-role coverage min(count_in_bucket, k) out of k;
       count constrained by exclusions; count of exceptions;
       count of moves of already-notified people.
8.4  Reason strings rendered FI and EN at publish, from the code, e.g.
       "Olet Tiimi 12:ssa - poyta 12. Sina olet heidan laiteosaajansa,
        ja koko tiimi puhuu suomea."
```

#### Phase 9 — publish

```
9.1  Re-take the advisory lock. STALENESS CHECK, narrowed to PROPOSAL-RELEVANT deltas:
       refuse if, since snapshot_at, any of the following happened --
         - a new block or safety_separation touching two people proposed onto one team
         - any team_members insert/left_at change affecting a team in the proposal
         - any team lock, disband, or team_gaps change affecting a proposed team
       A plain new check-in does NOT refuse. Those people are auto-enqueued for
       mode 'single' after publish and the preview says so.
     (An any-write staleness rule makes the button unreachable at a live event: check-in
      is a continuous stream at 09:05 and the organiser would refuse-rerun forever.)
9.2  Assert zero run_exceptions rows and zero hard violations across the whole proposal.
     Refuse otherwise. Exceptions can be individually acknowledged with a note by a
     named organiser, which records an organiser_actions row.
9.3  Allocate teams.number sequentially; table_number from the venue map, keeping
     same-challenge teams adjacent. Existing numbers and tables are untouched.
9.4  Insert teams and team_members ROW BY ROW in a PL/pgSQL loop (see Blocked pairs for
     why row-by-row matters), inside one transaction.
9.5  End-of-transaction set assertion (see Blocked pairs). Must return zero rows.
9.6  Set pinned = true, notified_at = now() on every seat a push is about to reference.
     Write placement_trace. Set teams.state = 'active'.
9.7  Set events.switch_window_ends_at = now() + 40 minutes.
9.8  Enqueue pushes. Payload carries NO personal data:
       "You're on Team 12 - table 12."
       "You're their hardware person. Everyone on the team speaks Finnish."
     No names, no counts, no scores. The payload transits Apple infrastructure outside
     the EU; a teammate's name must not.
9.9  Generate the seating pack (see Organiser preview). Automatically, always.
9.10 match_runs.state = 'published'; the previous published run stays as history.
```

#### Phase 10 — the sanctioned switch window (publish → +40 minutes)

Documented algorithmic assignments always produce unmanaged switching. Suppressing it does
not work; scheduling it does. For 40 minutes after publish, **the same link machine reopens**
with two config changes:

- any team may declare `team_gaps` ("we'd take one more");
- link TTL drops to 15 minutes.

A person may make one switch, as a directed request that the destination captain accepts. The
move is refused if it would take either team outside `[L, U]`. At the hard close, a cron
expires everything pending and sets `teams.locked = true`; further changes route to the
organiser console.

Zero new tables, zero new state machine, zero new UI. And it produces the single most honest
quality metric this system has: **the switch rate is the scoreboard for the algorithm.** 3%
means the deal was good. 25% means the parameters were wrong and next year we know it.

#### Mode `single` — the walk-in at 13:40

Not a second algorithm. Same size arithmetic, pool of one:

```
S.1  Require registrations.presence = 'checked_in' and profiles.wants_late_seat.
S.2  Candidate seats: active teams where accepts_late, size < U,
     challenge_id in the person's three ranked challenges, no exclusion with any member,
     working language compatible.
S.3  Rank by: declared gap matching their primary_role desc, team lacks their role_class
     desc, size asc, late_joins_so_far asc, challenge rank asc, table_number asc, team_id.
     (Nearer the door is a genuinely kinder first walk.)
S.4  Organiser taps Seat. BOTH sides get a push. The captain's says
     "Aino is joining you as your designer - she just arrived."
     That one sentence is the difference between a teammate and an intruder.
S.5  No seat -> late pool. When the late pool holds L (3) people sharing a challenge,
     or 3 people at all after 14:00, form a NEW team of them at a reserve table,
     origin 'late_pool'. Three people who all arrived late have more in common with
     each other than any of them has with a team that has been building since 09:30.
S.6  Late pool still below 3 at 16:00 on day one -> organiser queue, and the standing
     instruction is that a human walks them to a table and introduces them by name.
```

`accepts_late` defaults **false** and is set by a captain tapping "we'll take one more",
prompted once at 09:30. Onboarding a latecomer into a running project is genuinely hard;
consent matters more than throughput.

### Tie-breaks and leftovers

Every place a choice could be arbitrary, stated once:

| Choice | Rule |
|---|---|
| Order within a bucket's draft queue | `starved desc, unit_size desc, rarity_rank asc, exp_ord desc, md5(profile_id‖salt)` |
| `rarity_rank` ties | role enum ordinal: design, frontend, backend, hardware, ai_ml, business, media |
| Which bucket to dissolve in the merge | `population asc, challenge.sort_order asc, work_lang asc` |
| Which bucket a FLEX unit fills | greatest `deficit`, then `population asc, challenge.sort_order asc, work_lang asc` |
| Which unit spills on a capacity ceiling | smallest Borda margin to next choice, then `unit_size asc`, then hash |
| Which team a snake pick lands on when the base index is full | next team in that round's direction |
| Which team an existing-gap seat belongs to in the order | `open_seats desc, team.number asc` |
| Team numbering at publish | `challenge.sort_order, work_lang, provisional index` |
| Captain of an auto team | lowest `seq` in the team, labelled in-app **"table host"**, never "leader" |

**Leftovers, exhaustively.** The size arithmetic in Phase 3 produces only sizes in `{3,4,5}`,
so "7 people left over" is not a case: a bucket of 7 is `k = clamp(2, 2, 2) = 2` → sizes 4
and 3. The only ways a person is not seated by the deal:

1. `m_b ∈ {1,2}` after gap subtraction → hold back gap seats (3.4a) → next-ranked challenge
   (3.4b) → named exception (3.4c).
2. Excluded from every team in the bucket → next-ranked challenge (6.5) → named exception.
3. No surviving bucket in their language (the lone monolingual case) → named exception
   `no_language_bucket`, with the suggestion "pair with a bilingual team".
4. Merge loop hit its seatbelt → named exception `merge_loop_cap`.

All four end in a named row on the preview that **blocks publish** until an organiser either
seats the person or acknowledges the exception with a note. There is no silent path.

### Worked example with real numbers

**The morning.** 500 registered. 388 checked in by 09:05 (77.6%). 6 have `wants_team = false`.
231 are already on 61 self-formed teams; 18 of those teams have declared gaps totalling 27
seats. That leaves **151 people in the pool** and 27 gap seats to fill.

Five challenges. After the language split, FLEX allocation and the merge, the buckets are:

| bucket | `n_b` | `g_b` | `m_b` | `k_b` | sizes |
|---|---|---|---|---|---|
| C1 Health : fi | 47 | 7 | 40 | `clamp(10, 8, 13) = 10` | 10 × 4 |
| C1 Health : en | 12 | 0 | 12 | `clamp(3, 3, 4) = 3` | 4, 4, 4 |
| C2 Climate : fi | 44 | 6 | 38 | `clamp(10, 8, 12) = 10` | 8 × 4, 2 × 3 |
| C3 Education : fi | 25 | 9 | 16 | `clamp(4, 4, 5) = 4` | 4, 4, 4, 4 |
| C4 Media : fi | 13 | 5 | 8 | `clamp(2, 2, 2) = 2` | 4, 4 |
| C4 Media : en | 11 | 0 | 11 | `clamp(3, 3, 3) = 3` | 4, 4, 3 |
| C5 Robotics : fi | 6 | 0 | 6 | `clamp(2, 2, 2) = 2` | 3, 3 |

Totals: 158 seats needed, 151 people + 7 held gap seats... in fact 151 people fill 27 gap
seats plus 131 new-team seats across 34 new teams. Sum of `m_b` = 40+12+38+16+8+11+6 = 131. ✅
Sum of `g_b` = 27. ✅ 131 + 27 = 158 ≠ 151 — so seven declared gaps go unfilled, which is
exactly correct and exactly what 3.4(a) does deliberately: an unfilled gap is harmless.

**Two buckets that had to be fixed before this table existed:**

- *C5 Robotics : en* had 2 people. FLEX (Phase 2.3) moved 4 bilinguals into it, giving 6 —
  but Robotics' English side then still sat below `min_bucket_size` in an earlier iteration,
  so it dissolved and those 6 landed in *C5 Robotics : fi* (all 6 speak Finnish or are
  bilingual). Reason string, in the app: *"Not enough people chose Robotics in English, so
  you're with the Finnish-working Robotics team."*
- *C2 Climate* drew 41% of first choices. `max_teams = 12` capped it; 9 people spilled to
  their second choice with reason `challenge_over_capacity_moved_to_choice_2`. The preview
  reports this in one sentence.

**One bucket, dealt in full: C4 Media : en, `m = 11`, `k = 3`, sizes `[4, 4, 3]`.**

Role counts inside this bucket: media 3, design 2, frontend 2, ai_ml 2, hardware 1,
business 1. So `rarity_rank`: hardware (count 1, ordinal 4) → 1; business (count 1,
ordinal 6) → 2; design (count 2, ordinal 1) → 3; frontend (count 2, ordinal 2) → 4;
ai_ml (count 2, ordinal 5) → 5; media (count 3) → 6.

Draft queue after the Phase 5 sort:

| seq | person | role | class | experience | note |
|---|---|---|---|---|---|
| 0 | Otto V. | frontend | build | first_time | `starved = 2` — three requests, all expired |
| 1 | Aino K. | hardware | build | lots | rarest role in the bucket |
| 2 | Sofia M. | business | voice | been_to_a_few | |
| 3 | Elias R. | design | craft | lots | |
| 4 | Nea L. | design | craft | first_time | |
| 5 | Väinö P. | frontend | build | been_to_a_few | |
| 6 | Iida S. | ai_ml | build | lots | |
| 7 | Leo T. | ai_ml | build | first_time | |
| 8 | Emil H. | media | craft | been_to_a_few | |
| 9 | Venla A. | media | craft | first_time | |
| 10 | Onni J. | media | craft | first_time | |

Snake, `k = 3`, with the Phase 6.2 pick predicate:

- **Round 0** (T1, T2, T3), all empty → heads: T1 ← Otto, T2 ← Aino, T3 ← Sofia.
- **Round 1** (T3, T2, T1, reversed):
  T3 holds `voice`; wants a missing class → head of queue is Elias (`craft`) → **T3 ← Elias**.
  T2 holds `build`; wants a missing class → Nea (`craft`) → **T2 ← Nea**.
  T1 holds `build`; Väinö, Iida, Leo are all `build` and are skipped by rule (d); Emil is
  `craft` → **T1 ← Emil**.
- **Round 2** (T1, T2, T3):
  T1 has `build + craft`; no `voice` remains, so rule (e): Väinö is a duplicate frontend and
  is skipped; Iida (ai_ml) is a new role → **T1 ← Iida**.
  T2 has `build + craft`; rule (e) → **T2 ← Väinö** (frontend, absent).
  T3 has `voice + craft` and needs a `build` → **T3 ← Leo** (ai_ml). T3 is now at its target
  size of 3 and closes.
- **Round 3** (T3, T2, T1, reversed): T3 is full and is skipped → **T2 ← Venla**, then
  **T1 ← Onni**.

| team | members | build | craft | voice | distinct roles |
|---|---|---|---|---|---|
| T1 (4) | Otto frontend, Emil media, Iida ai_ml, Onni media | ✅ 2 | ✅ 2 | ✗ | 3 |
| T2 (4) | Aino hardware, Nea design, Väinö frontend, Venla media | ✅ 2 | ✅ 2 | ✗ | 4 |
| T3 (3) | Sofia business, Elias design, Leo ai_ml | ✅ 1 | ✅ 1 | ✅ 1 | 3 |

Every team has a builder and a communicator. Experience is spread — each team has at least
one `lots` and at least one `first_time`, and no team trips `lone_novice`. The one blemish is
T1's two media people, and it is **forced, not a heuristic failure**: there are 3 media people
and only 3 teams, but T3 is capped at size 3 and giving T3 a media instead of Leo would leave
T3 with no builder at all. The draft's answer is the right one, and the preview will still
flag `duplicate_role` on T1 so a human can look.

Otto — the `starved` person, a first-timer whose three requests all expired unanswered — got
pick 0 and is on a team with an experienced AI person and two media people. His push reads:

> **You're on Team 12 — table 12.**
> You're their frontend developer. Everyone on the team speaks English.

**The metrics this run reports:**

- 1st choice challenge: 87% (131/151). 1st or 2nd: 97%. Beyond preferences: 0.
- Teams with no builder: 0. Teams with no communicator: 2 (named).
- Size histogram: 3 → 4 teams · 4 → 28 teams · 5 → 2 teams.
- Duplicate primary role somewhere in the team: 6 teams.
- `lone_novice`: 1 team (named). `solo_into_established_team`: 3 (named).
- Constrained by exclusions: 3. Could not be seated: **0**.
- Hall warning, printed in words: *"Only 11 hardware participants across 34 new teams —
  23 teams will have no hardware specialist. Consider announcing shared hardware mentors at
  the opening."*

---

## Blocked pairs

**Requirement.** No pair in `match_exclusions` may ever share a team, by any path: auto-assign,
request accept, invite accept, organiser drag-and-drop, late seating, repair re-run, or a
feature nobody has written yet.

### Layer 1 — the database, which is the only layer worth defending in an incident review

```sql
create or replace function forbid_excluded_teammate() returns trigger
language plpgsql security definer as $$
begin
  if exists (
    select 1 from team_members tm
    join match_exclusions me
      on me.a = least(tm.profile_id, new.profile_id)
     and me.b = greatest(tm.profile_id, new.profile_id)
    where tm.team_id = new.team_id and tm.left_at is null
  ) then
    raise exception 'EXCLUSION_VIOLATION' using errcode = 'P0002';
  end if;
  return new;
end $$;

create constraint trigger tm_exclusion_guard
  after insert or update of team_id, profile_id, left_at on team_members
  deferrable initially deferred
  for each row execute function forbid_excluded_teammate();
```

**This must be a deferrable `AFTER` constraint trigger, not a `BEFORE ROW` trigger, and this
is a real bug we are fixing, not a style preference.** A `BEFORE INSERT … FOR EACH ROW`
trigger does not see rows inserted by the *same* command: rows written by the current command
carry the current `cmin` and are invisible to the trigger's `SELECT` under that command's
snapshot. So `insert into team_members select … from run_placements` — the natural way to
publish 34 teams — will happily commit a blocked pair whenever **both** members are inserted
by that one statement, which is exactly the case for two auto-assigned strangers. A deferred
constraint trigger fires at commit, after every row is visible.

**Belt and braces:** `publish_run` additionally inserts row by row in a PL/pgSQL loop (so each
insert is its own command and the guard sees prior rows immediately, giving a useful error
location), and runs this set assertion as the last statement before `COMMIT`:

```sql
-- must return zero rows
select tm1.team_id, tm1.profile_id, tm2.profile_id
from team_members tm1
join team_members tm2
  on tm2.team_id = tm1.team_id and tm2.profile_id > tm1.profile_id
join match_exclusions me
  on me.a = least(tm1.profile_id, tm2.profile_id)
 and me.b = greatest(tm1.profile_id, tm2.profile_id)
where tm1.left_at is null and tm2.left_at is null;
```

An illegal team is now unrepresentable. It cannot be committed by auto-assign, by an accept,
by an organiser drag, or by somebody typing SQL at 03:00.

### Layer 2 — the RPCs

`rpc_accept_link`, `rpc_organiser_move` and `rpc_seat_late` catch `P0002` and return the
neutral outcome `{"ok": false, "reason": "unavailable"}`, which the client renders as
**"That spot is no longer available."** Never "you are blocked". The link row is set to
`superseded`. Neither party learns that a block exists.

### Layer 3 — the query layer

`attendee_cards`, `team_cards`, invite target lists and request target lists all filter
through `not exists (select 1 from match_exclusions …)`, so an excluded person simply never
appears and Layer 2's neutral failure is rarely reached.

### Inside the algorithm

`run_exclusions` is snapshotted once at Phase 0, so a block filed at 09:02 cannot make the
publish differ from the preview the organiser approved at 09:01. Exclusion is HARD rule (a)
of the Phase 6 pick predicate, and it is re-asserted across the whole proposal at Phase 9.2.

**There is no swap-repair pass.** Expected violations at 500 people: 0–3. The escalation
ladder is: skip excluded teams at deal time (free — already in the predicate) → the person's
next ranked challenge bucket → a named `run_exceptions` row that blocks publish. This deletes
roughly 80 lines and the hardest test surface in the design, and the outcome is better: an
organiser seats one person by hand in twenty seconds from a list the screen hands them.

**Feasibility bound.** A person with `b` exclusions is seatable in any bucket with more than
`b` teams, because each counterpart occupies at most one team. Blocks are capped at 10 per
user, so any bucket with ≥ 11 teams is safe by construction. The preview warns whenever
`max degree of any member of a bucket ≥ k_b` — the honest risk is a small bucket, e.g. three
teams on a niche challenge, where a person with three blocks can be genuinely unseatable and
the ladder ends at a human. That is the correct ending.

**Never** is the pair seated together to keep the coverage promise. The promise is delivered
by a human seating one person, and the preview tells them exactly who.

**What the preview may show.** *"3 placements were constrained by safety exclusions"* and
*"1 person could not be auto-seated — Aino K., needs manual placement."* It names **who needs
seating**, because the organiser must act. It never shows **who blocked whom**. Pair detail is
`organizer_safety` only, through a view that writes an `audit_log` row on every read. General
organisers casually browsing "who hates whom" among 16-year-olds is itself a harm.

### A block filed against a current teammate

The team is **not** silently dissolved. Instead, in one transaction:

1. a `safety_separations` row is written immediately, so every future automated action
   already respects it;
2. a priority-1 item appears on the Safety Desk queue with both names, the team and the table;
3. the blocker sees only: *"An organiser will come and talk to you — you don't have to say
   anything to them."*

Splitting a working team is a decision a human makes in a room, and the software's job is to
make the seating consequences instant and correct, not to make the decision.

---

## Moderation, reporting and blocking

Guideline 1.2 mandates four affordances for any UGC app. Here is each one, as a shipped
artefact rather than a promise.

### The UGC surface, minimised first

Three fields in the entire product: `display_name`, `bio`, `report.details`. Optionally
`teams.name`. No photos, no avatars, no DMs, no free text on a request or an invite, no
comments, no chat.

**Bios ship disabled.** `events.bio_enabled` defaults to `false`. The matcher reads no free
text, so a disabled bio costs matching *exactly nothing*. Turning bios on collapses or expands
the entire 1.2 surface, so it is a dated decision gate, not a config flag somebody flips on a
Tuesday:

> **If a named adult Safety Lead plus two deputies covering the night shift are not confirmed
> in writing by T−14d (10 October 2026), the event ships with `bio_enabled = false` and the
> UGC surface is display names only.**

If bios are enabled, `age_band = 'u16'` profiles still cannot author one. That is the only
thing `age_band` gates, and it is stated in the privacy policy so the field has a declared
purpose under 5.1.1(i).

### 1. Filter for objectionable material

A `BEFORE INSERT OR UPDATE` trigger on `profiles` (fields `display_name`, `bio`) and on
`teams` (field `name`). Two stages:

- **Structural rejects**, unconditional: any URL, email address, phone number, `@handle`,
  Snapchat/Instagram/Discord/Telegram pattern, bidi control characters, combining-mark
  ("zalgo") density above threshold, more than 2 consecutive identical characters, non-Latin
  script mixing beyond a whitelist.
- **Lexicon**, after Unicode NFKC normalisation, lowercasing, leet-substitution and
  whitespace stripping: `moderation_terms` matched by exact / prefix / substring, minus
  `moderation_allowlist` (Finnish has legitimate words that contain English profanity
  substrings; the allowlist exists for them). `severity = 'block'` → hard reject with a
  neutral message. `severity = 'flag'` → the field is stored with status `pending` and is
  invisible to everyone except its author and `organizer_safety`.

**The trigger is the only authority.** The Swift client mirrors the rules for instant
feedback, but the anon key is public and a client check is a suggestion.

Every rejection writes a `moderation_attempts` row storing the **matched lexicon term** and a
SHA-256 of the rejected text — never the child's sentence itself — with a **90-day retention
job**. The hash is enough for repeat-offender detection; the raw text is not ours to keep.

### 2. Report mechanism with timely responses

`rpc_report(subject_id, subject_kind, category, details)`. Eight enumerated categories.
Details capped at 500 characters and themselves passed through the filter. A reporter may
file at most 5 open reports per 24 hours.

**Auto-hide, so the SLA is never the only defence at 03:00:** a bio or team name is hidden
automatically at **2 distinct reporters**, or at **1 report** in the categories `threat`,
`sexual_content` or `hate_speech`. Hiding is instant and reversible; a human reviews after.

**Published SLA**, on the safety page and in the app: 24 hours normally, **60 minutes during
event hours**, immediate for threats. `reports.first_action_at` instruments it, and the Safety
Desk console is ordered by time-to-breach with priority-1 items pinned. A published SLA with
no work queue behind it is an unenforceable promise, and 1.2 is judged on the promise being
kept.

### 3. Block

One tap. **Silent, symmetric, reversible, capped at 10** (`events.block_cap`). The blocked
party is never notified and no RLS policy grants them any read of `blocks`. Blocking
immediately removes both parties from each other's browse lists and invite/request targets,
supersedes any live link between them, and makes them un-seatable together forever (see
Blocked pairs). Ten is not arbitrary: it is the number that keeps the feasibility bound true
in a bucket of 11+ teams.

### 4. Published contact information

Reachable **logged out**, from the app and from stuhi.org: the association's registered name,
Y-tunnus, Finnish postal address, a monitored `safety@` address, the SLA above, the Safety
Desk phone number (also printed on every badge), and a physical desk location on the venue map.

### Account deletion

Settings → Account → Delete, **two taps**, works for suspended accounts, and it:

- cascades per the retention table;
- transfers captaincy to the earliest-joined remaining member;
- frees the auto-assign seat and, post-publish, raises a team-viability check;
- leaves a hashed row in `safety_holds` so deletion cannot launder a ban.

Its absence is a flat 5.1.1(v) rejection. It is not optional and it is not a v2 item.

### Everything printed is UGC

If `teams.name` is enabled, it passes the same trigger as a bio, because it is printed on a
placard and on a roster wall in a room full of 15-year-olds. `left_reason` and
`disbanded_reason` are enums precisely so they cannot become free text describing a named
child inside an organiser console.

### App Review notes, shipped with the build

- A **ticketed demo account** with a populated event, a pre-existing team, a pending invite
  and a pending request. Without one the reviewer hits the ticket gate, sees an empty app,
  and rejects under 2.1. This is the single most likely rejection for this design.
- The verbatim paragraph: *"There is no swipe deck, no rating, no scoring, no match
  percentage, no compatibility meter and no leaderboard anywhere in this product. The only
  ordering of people is the team-building list, which is sorted by fewest invitations
  received, so that people who have been overlooked appear first. It ranks neglect, not
  people, and the counter it sorts on is never returned to any client."*
- A pointer to the logged-out safety and contact page.

---

## Edge cases

| Situation | What the system does |
|---|---|
| Passive board silence; sender cannot tell ignored from unseen | Explicit state machine, visible countdown, guaranteed terminal state, quota returns. `seen_at` recorded, never revealed. Expiry increments `starved`, which buys **first pick** in the draft. |
| 112 of 500 never show up | `presence = 'checked_in'` is a hard cohort filter. The no-show variable is eliminated, not estimated. |
| Registration-basis rehearsal run | Allowed as `mode = 'dry'`, `roster_basis = 'registered'`, with a full-width amber UNRELIABLE banner. |
| Opening ceremony overruns to 09:25 | Matching closes when an organiser presses **Close matching**, not on a timestamp. |
| Three friends do not want a fourth | No `team_gaps` row → they are not a placement target for any mechanic. |
| One stranger into a group of three | Allowed only into a declared gap, flagged `solo_into_established_team`, named at the top of the preview with **Move to a new team** / **Approve**. Two-seat gaps are filled before one-seat gaps. |
| A bucket has exactly 3 people | Bucket dissolves at `< 6`; those 3 descend to their next ranked challenge with the reason *"Not enough people picked Challenge 4, so you're on your second choice."* |
| A bucket has exactly 7 people | `k = clamp(2,2,2) = 2` → sizes 4 and 3. Not a special case. |
| 2 people left after declared gaps eat the bucket | 3.4(a) holds back a gap seat so a team of 3 forms; else next challenge; else named exception. **Never a team of 2.** |
| One challenge draws 41% of first choices | `challenges.max_teams` ceiling spills the lowest-margin units to their second choice, rank-1 people last. |
| Somebody ranked 3 challenges and all are full or dissolved | Largest surviving bucket in their language, reason `no_ranked_challenge_available`. Never silent. |
| A single Finnish-only attendee with no Finnish bucket anywhere | Named exception `no_language_bucket`, suggestion "pair with a bilingual team". Publish blocked until resolved. **The loop cannot spin.** |
| A challenge has 2 English-only speakers and 40 bilinguals | FLEX allocation runs **before** the merge and lifts the English side to viability. |
| Blocked pair proposed onto one team | Skipped at deal time → next challenge → named exception. Never seated together. Deferred constraint trigger + set assertion make it uncommittable. |
| A block lands on a current teammate at 15:20 | `safety_separations` written immediately, priority-1 Safety Desk item, team not dissolved, blocker told an organiser will come to them. |
| Person accepts two invites in the same second | `one_active_team_per_person` partial unique index. One wins, the other RPC returns "no longer available". |
| Captain deletes their account | Captaincy transfers to earliest-joined remaining member. A captainless team cannot exist. |
| Person deliberately wants to work alone | `wants_team = false`, framed as *"I'm working solo this time"*, removed from every pool, reversible, never nagged, never a failure state. |
| They flip it back at 11:00 | Triggers a `mode = 'single'` run. |
| A team implodes into 3+1 at 11:05 | `rpc_split_team`. Remainder ≥ 3 keeps its number and table. Leavers become a unit (if 2) or singles, land in the pool, and raise an organiser item. **No auto-placement mid-day** — an organiser reviews a proposal on screen. |
| Somebody leaves at 17:50 and the team drops to 2 | Departure is gated: you may leave only if your team stays ≥ 3. Otherwise it becomes an organiser item with three named options — merge with another small team in the same challenge (the system proposes the specific pair), absorb a late arrival, or continue as a pair with a logged override. **The system never auto-dissolves a working team mid-event.** |
| Sunday 08:30, four teams down to two | `mode = 'repair'`, `churn_budget` defaulting to the headcount of non-viable teams. Pinned people in healthy teams are untouched. Collapsed pairs move together. |
| Somebody would be moved twice by two repair runs | `pinned` prevents gratuitous moves but not a second genuine one. Repair optimises for fewest moves and the preview names everybody who moves before anything is sent. |
| Walk-in at 13:40 | `mode = 'single'`. Opt-in teams only. Both sides notified; the captain gets the arrival's name and role. |
| Three walk-ins at 15:00, no opt-in teams | Late pool forms a new team of them at a reserve table. |
| A sponsor withdraws a challenge at 08:00 | `challenges.state = 'withdrawn'`; affected teams re-bucket to their members' highest common alternative; a `repair` run is proposed with an honest, large churn number. |
| Two organisers press Publish at once | `pg_advisory_xact_lock` serialises them; the second fails the staleness check and is offered a re-run. |
| Continuous check-in during preview review | Staleness is proposal-relevant only. Plain new check-ins do not block publish; they are auto-enqueued for `mode = 'single'`. |
| The venue wifi dies at 09:00 | The seating pack PDF was generated at preview time and lives on the organiser's laptop. Placards, roster wall and a badge lookup sheet. The event runs off paper. |
| Push notifications never arrive / phone is dead | Four channels: in-app team screen (canonical), push, printed placard, printed roster wall. |
| Attendee arrives with no phone or a dead account | `rpc_seat_by_badge`: the desk creates a minimal profile in four taps — role, experience, language, three challenge ranks — **and records terms acceptance against it before it is matchable**. `u16` routes through the guardian-consent artefact already collected at registration. |
| A duplicate account | `ticket_code_hash` is unique per event; one ticket cannot produce two seated identities. The desk moves the ticket link and disbands the empty profile. |
| A table is physically wrong (accessibility, broken socket) | `rpc_swap_tables(a, b)` swaps `table_number` only. Memberships untouched, both placards reprinted. |
| Somebody re-requests a team that dismissed them | Refused. One approach per pair per matching window, in either direction. |
| A bio is `pending` at 09:00 | Irrelevant. The matcher reads no free text. |
| A captain sits on invites for two days | Invite TTL is 12 hours, so the person's slot returns. `seen_at` lets the console nudge slow captains. |
| Only 11 hardware people across 34 teams | The preview says so **in words, before the deal**, because that is the one problem an organiser can still fix at 08:55 by walking to a microphone. The algorithm does not pretend to solve it. |
| Exactly one first-timer among three veterans | Flagged `lone_novice` on the preview, named, with a one-tap move. Not a hard constraint — encoding it as one is what forces a repair pass into existence. |

---

## Organiser preview and manual override

One scrollable web page, `organizer` claim required, generated entirely from the frozen
`run_*` tables. **Worst things at the top.** Publish is a single button that stays disabled
while any gate is red.

**A. Run header.** Run id, mode, salt (short), `snapshot_at` with a live "taken 2m 14s ago"
counter, and the roster basis in plain language:

> Based on **388 checked-in** attendees. 500 registered. 112 have not checked in and are
> excluded. 6 chose to work solo. → **151 to place, 34 new teams.** Estimated runtime 0.4 s.

**B. Blocking gates.** Publish is disabled while either is non-zero:
- *N people could not be seated* — each **by name**, with the reason and a one-tap **Seat
  manually** picker that re-validates against the exclusion guard and refuses illegal drops.
- *N hard violations* — should always be zero; if it is not, the function has a bug and you
  want to know before publishing, not after.

Each exception can be individually acknowledged with a required note, which writes an
`organiser_actions` row under the organiser's name.

**C. The churn panel.** *"This run moves **4** people who have already been notified."* Then
those four by name, old team → new team, with the reason each move is unavoidable. If it says
200, the organiser stops and asks why. Showing this **before** anything is sent is the entire
point.

**D. Look-at-me rows.** Every `solo_into_established_team` (*"Aino K. is the only new member
joining Team 7, which is three friends. They asked for a designer."*), every `lone_novice`,
every person moved off their first-choice challenge grouped by cause with counts.

**E. Metrics, big and plain.** % on 1st / 2nd / 3rd choice · % whose primary role is
duplicated in their team · teams with no builder · teams with no communicator · **size
histogram** (3/4/5 as bars, because size variance is the fairness question an organiser will
be challenged on out loud) · experience spread · placements constrained by exclusions.

**F. Coverage warnings, in words.** *"Only 11 hardware participants across 34 new teams — 23
teams will have no hardware specialist. Consider announcing shared hardware mentors at the
opening."* This is the single most useful thing on the page, because it is the one problem
still fixable at 08:55.

**G. Worst ten teams**, ascending, expanded by default, each with the deficiency named in
words — *"Team 61 — no builder: two business, one media, one designer"* — the four members
with role and experience band, and the reason each is there. Inline **Move**, **Swap**,
**Split**, **Merge**.

**H. Full assignment table.** Searchable by name, badge, team, table, challenge, role. Every
row carries its `seq`, reason code and flags. CSV export. A permanent link to the `run_id`, so
"which run produced this?" always has an answer.

**I. Seating pack, generated automatically on every preview** — not behind a button somebody
has to think of at 08:58:
- table placards PDF: team number, table number, challenge, working language, first names
  **each with their role in the team**;
- a roster wall poster sorted alphabetically by first name;
- a check-in desk lookup sheet sorted by badge number;
- the CSV.

**J. Buttons.** `Re-run preview` (new salt) · `Re-run identical` (same salt, diffs the two
runs byte for byte — this is how we catch a forgotten tie-break) · `Compare two drafts`
(e.g. T=4 vs T=5) · `Publish`.

**K. Publish dialog.** *"This will notify 287 people, create 34 teams, and move 4 people who
were already told a different team. Type PUBLISH to continue."* Typed confirmation, because
the action is irreversible in the only way that matters: people read their phones.

### Manual override

`rpc_organiser_move(profile_id, to_team_id, reason)` runs the same checks as the algorithm.
It **may** be forced past soft constraints (role duplication, experience imbalance, size 6)
with a required reason, logged in `organiser_actions` with `forced = true`. It **may not** be
forced past `match_exclusions` — that is not a policy, it is a database invariant.

**Deliberately absent from this screen: who blocked whom.** Pair detail is `organizer_safety`
only, behind an audited view.

### The 03:00 runbook, on one laminated card

```sql
-- Who has no team?
select p.display_name, p.primary_role
from profiles p join registrations r on r.profile_id = p.id
where r.presence = 'checked_in' and p.wants_team
  and not exists (select 1 from team_members tm
                   where tm.profile_id = p.id and tm.left_at is null);

-- Which teams are dying?
select t.number, t.table_number, count(*) filter (where tm.left_at is null) as size
from teams t left join team_members tm on tm.team_id = t.id
where t.state = 'active' group by 1,2 having count(*) filter (where tm.left_at is null) < 3;

-- Fix it, minimally, then look, then publish.
select preview_assign(gen_random_uuid(), 'repair');
```

### Build order (63 days from 22 August)

| Days | Ship |
|---|---|
| 1–7 | Schema + RLS + `attendee_cards`/`team_cards` + a **500-profile seeder written before any UI** — the matcher will be run 200 times |
| 8–15 | `preview_assign` Phases 0–8 + `publish_run`, against seed data. CI asserts: sizes ∈ {3,4,5} for `m ∈ {3,4,5,6,7,9,10,11,13,23,50}` after gap subtraction; zero exclusion violations; identical output for identical salt |
| 16–25 | iOS: onboarding, role picker, 3-deep challenge ranking, team screen, browse, inbox, the one link component, block/report |
| 26–33 | Organiser web console: preview sections A–F + I, manual override, Safety Desk queue |
| 34–40 | **Check-in scanner** — its own interface, offline-tolerant, with a manual desk override. If check-in is not built and rehearsed, the algorithm has no cohort |
| 41–47 | APNs end to end: certificates, token registration, send worker, and one full round of "why did nobody get the push". Budget 3 days, not half a day; it is on the critical path for the 09:20 publish |
| 48–53 | `mode = 'single'`, late pool, switch window, repair mode, departure gating |
| 54–58 | **Full dress rehearsal with a stopwatch**: check in 500 seeded profiles → preview → publish → simulate 60 departures → repair run → print the pack |
| 59–63 | App Review submission, demo accounts, privacy policy FI/EN, buffer |

**Paper fallback, printed 23 October:** the seating pack from the last preview run, plus blank
team cards. If Supabase is down at 09:00 the organiser reads team numbers off a printout and
the event proceeds. The guarantee must not depend on the network.

---

## Open questions for Momin

1. **How many challenges?** This is a September decision and it dominates the quality of the
   whole run. With 500 people across **4–6** challenges the buckets are large and the merge
   loop almost never fires. With 10–12, several buckets dissolve and the "% on first choice"
   metric drops sharply. The challenge list is frozen before ranking opens, so this cannot be
   fixed in October. **Recommendation: 5, with `max_teams` set on all of them.**
2. **What are the `max_teams` ceilings?** They must be set before matching opens. If one
   challenge is obviously the glamorous one, cap it at roughly 30% of expected teams and let
   the spill go to second choices with an honest explanation.
3. **Language reality check at T−14d.** The Finnish/English partition is the right call if a
   meaningful number of attendees are monolingual in either direction. If registration data
   shows 85%+ bilingual, the partition costs more mixing than it buys in safety, and we should
   set every challenge to a single `en` bucket. Please pull the language distribution from
   registrations on 10 October and we decide then, from data.
4. **Is there a named adult Safety Lead with two deputies covering the night shift, in writing,
   by 10 October?** If yes, bios ship enabled. If no, `bio_enabled` stays false and the UGC
   surface is display names only. I need a yes or a no, not a probably — the whole moderation
   lexicon, review queue and bio state machine leave the build if the answer is no, at zero
   cost to team quality.
5. **Who is building and staffing the organiser web console?** It is roughly 35–40% of this
   build and none of it is the iOS app. If only the app ships, the event-day story fails.
   If nobody else is available, tell me now and we cut the console to sections A–C + I and
   drive everything else from `psql` and the printed pack.
6. **Check-in hardware.** How many scanners, on what devices, and what happens when the venue
   wifi is bad? Check-in is the hard gate for the entire guarantee, and a queue that is still
   40 people long at 09:00 produces 40 people the algorithm cannot see. Recommendation: open
   check-in at 08:00, two scanners minimum, and a manual override at the desk that sets
   `checked_in_at` without a network round trip.
7. **Table numbering and the venue map.** I need the real table list from Hervanta, including
   how many tables exist, which are accessible, and which we can hold back as
   `reserve_tables` for late-formed teams. Recommendation: reserve 4.
8. **Judging rubric.** Is one of three prizes reserved for best idea / design / pitch, with no
   working prototype required? This is the only mechanism that stops a correctly composed team
   sidelining its designer anyway, and it is a decision only you can make. The algorithm
   cannot carry it and this document should not be allowed to imply that it does.
9. **Target team size: 4 or 5?** Everything above is parameterised. 4 gives more teams and
   more first-choice satisfaction; 5 survives no-shows better and needs fewer mentors.
   Recommendation: 4, with `max_team_size = 5` so the switch window and late seating have
   somewhere to put people.
10. **What does an attendee under 16 see?** Currently: everything except authoring a bio. If
    the association's registration flow already collects guardian consent, say so and I will
    reference the artefact from `registrations.guardian_consent_ref` in the privacy policy.
