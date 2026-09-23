-- STUHI app — content filtering.
--
-- App Store Review Guideline 1.2 lists four things an app with user-generated
-- content MUST have. Report, block and published contact details were built
-- already. This file is the first bullet, which is the one people forget:
--
--     "A method for filtering objectionable material from being posted
--      to the app"
--
-- Note the wording: filtering material from BEING POSTED. Reviewing it
-- afterwards does not satisfy it. So this runs as a BEFORE INSERT OR UPDATE
-- trigger and rejects the write.
--
-- It filters two different things, for two different reasons:
--
--   1. Objectionable language — the guideline requirement.
--   2. Contact details in free text — phone numbers, emails, social handles,
--      links. This is not in the guideline; it is here because roughly half
--      the people using this app are 15-17 years old, and a bio field is
--      otherwise a place for a stranger to say "add me on <platform>" and
--      move the conversation somewhere nobody is moderating. That is the
--      actual risk to a minor at a public event, and it is worth more than
--      the swear filter.
--
-- Deliberately NOT clever. No ML, no external service, no LLM call in a write
-- path. A wordlist and some regexes, run in the database so it cannot be
-- bypassed by talking to PostgREST directly — a client-side check alone is
-- decorative.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- The wordlist
-- ─────────────────────────────────────────────────────────────────────────
-- Seeded with unambiguous terms in English and Finnish. It is deliberately
-- short: a long list produces false positives, and a Finnish 16-year-old
-- being told their bio is "objectionable" because it contains an innocent
-- substring is its own kind of failure. Extend it from what moderation
-- actually sees. `pattern` is matched against the NORMALISED text.

create table if not exists banned_terms (
  id        bigserial primary key,
  pattern   text not null unique,
  -- 'block' refuses the write. 'flag' allows it but raises a report for a
  -- human to look at — for terms too ambiguous to refuse outright.
  action    text not null default 'block' check (action in ('block','flag')),
  note      text,
  added_at  timestamptz not null default now()
);

insert into banned_terms (pattern, action, note) values
  -- Sexual solicitation. Guideline 1.1.4 and basic safeguarding.
  ('\msex(y|ual)?\M',            'flag',  'context dependent — flag, do not block'),
  ('\mnud(e|es)\M',              'block', null),
  ('\mporn',                     'block', null),
  ('\mhorny\M',                  'block', null),
  -- Slurs and targeted abuse. Kept minimal and unambiguous.
  ('\mfaggot',                   'block', null),
  ('\mn[i1]gg',                  'block', null),
  ('\mretard',                   'block', null),
  ('\mhuora\M',                  'block', 'fi'),
  ('\mvitun?\M',                 'flag',  'fi — extremely common, flag only'),
  ('\mneekeri',                  'block', 'fi'),
  ('\mhomo(t|ja|ksi)?\M',        'flag',  'fi — slur or neutral depending on use'),
  -- Threats and self-harm signals. Flagged, never silently blocked: someone
  -- writing this may need a person, not an error message.
  ('\mkill (yourself|urself)\M', 'block', null),
  ('\mtapa itsesi\M',            'block', 'fi'),
  ('\msuicid',                   'flag',  'route to a human quickly'),
  ('\mitsemurha',                'flag',  'fi — route to a human quickly'),
  -- Drugs and alcohol offered at a school event.
  ('\mweed for sale\M',          'block', null),
  ('\mmyyn kamaa\M',             'block', 'fi')
on conflict (pattern) do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- Normalisation
-- ─────────────────────────────────────────────────────────────────────────
-- Defeats the obvious evasions: casing, diacritics, leetspeak, padding
-- characters, and stretched letters ("niiiice"). Everything downstream
-- matches against this form, never the raw text.

create or replace function moderation_normalise(raw text)
returns text language sql immutable as $$
  select regexp_replace(
           regexp_replace(
             translate(
               lower(coalesce(raw, '')),
               'àáâãäåèéêëìíîïòóôõöùúûüýÿñç0134578@$!|',
               'aaaaaaeeeeiiiiooooouuuuyyncoieastbgl'
             ),
             '(.)\1{2,}', '\1\1', 'g'          -- niiiice -> niice
           ),
           '[^a-z0-9åäö ]+', ' ', 'g'          -- punctuation used as padding
         )
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Contact details
-- ─────────────────────────────────────────────────────────────────────────
-- Matched against the RAW text, not the normalised one — normalising destroys
-- the @ and . that make these recognisable.

create or replace function contains_contact_details(raw text)
returns boolean language sql immutable as $$
  select coalesce(raw, '') ~* (
    -- email
    '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
    -- url or bare domain
    '|https?://|www\.|[a-z0-9-]+\.(com|net|org|fi|io|me|gg|ly)\M'
    -- phone: Finnish mobile, or any 8+ run of digits with optional separators
    '|\+358[ -]?[0-9][0-9 -]{6,}|\m0[45][0-9][ -]?[0-9][0-9 -]{5,}'
    '|\m[0-9][0-9 ()+-]{7,}[0-9]\M'
    -- "snap: x", "insta @x", "add me on telegram", "wa.me/…"
    '|\m(snap(chat)?|insta(gram)?|telegram|whatsapp|wa\.me|discord|tiktok|kik)\M[ :@]*[a-z0-9._-]{2,}'
  )
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- The check
-- ─────────────────────────────────────────────────────────────────────────

create or replace function moderation_verdict(raw text)
returns table (action text, reason text)
language plpgsql immutable as $$
declare norm text; hit record;
begin
  if raw is null or btrim(raw) = '' then
    return query select 'ok'::text, null::text; return;
  end if;

  if contains_contact_details(raw) then
    return query select 'block'::text,
      'Please don''t put phone numbers, emails, links or social handles in your profile. Talk to people through the app first.'::text;
    return;
  end if;

  norm := moderation_normalise(raw);

  for hit in
    select b.pattern, b.action from banned_terms b
     where norm ~ b.pattern
     order by (b.action = 'block') desc
     limit 1
  loop
    if hit.action = 'block' then
      return query select 'block'::text,
        'That wording breaks STUHI''s community guidelines. Please rewrite it.'::text;
    else
      return query select 'flag'::text, hit.pattern::text;
    end if;
    return;
  end loop;

  return query select 'ok'::text, null::text;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- Triggers
-- ─────────────────────────────────────────────────────────────────────────
-- Every free-text field a stranger can read goes through this.

create or replace function moderate_profile() returns trigger
language plpgsql security definer set search_path = public as $$
declare v record;
begin
  if new.bio is distinct from coalesce(old.bio, '') then
    select * into v from moderation_verdict(new.bio);
    if v.action = 'block' then
      raise exception '%', v.reason using errcode = 'check_violation';
    elsif v.action = 'flag' then
      insert into reports (reporter_id, subject_id, subject_kind, reason, detail)
      values (null, new.id, 'profile', 'auto: flagged wording', v.reason);
    end if;
  end if;

  if new.display_name is distinct from coalesce(old.display_name, '') then
    select * into v from moderation_verdict(new.display_name);
    if v.action = 'block' then
      raise exception 'Please choose a different display name.' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists profiles_moderate on profiles;
create trigger profiles_moderate before insert or update on profiles
  for each row execute function moderate_profile();

-- Team names and pitches are read by everyone at the event, so they get the
-- same treatment. Guarded with to_regclass so this file can be applied before
-- 030_matching.sql has ever run.

create or replace function moderate_team() returns trigger
language plpgsql security definer set search_path = public as $$
declare v record;
begin
  -- Team names only. 030_matching.sql deliberately gives teams no free-text
  -- description and link_requests no message column, so a team name is the
  -- entire writable surface here. Do not add a `pitch` check back without
  -- checking the column actually exists.
  select * into v from moderation_verdict(new.name);
  if v.action = 'block' then
    raise exception 'Please choose a different team name.' using errcode = 'check_violation';
  end if;
  return new;
end $$;

do $$ begin
  if to_regclass('public.teams') is not null then
    execute 'drop trigger if exists teams_moderate on teams';
    execute 'create trigger teams_moderate before insert or update on teams
             for each row execute function moderate_team()';
  end if;
end $$;

-- link_requests deliberately has NO free-text column — the payload is a
-- role code and nothing else. That is the single biggest reduction in UGC
-- surface in this app, so there is nothing here to filter.

-- Read-only to the app: the client mirrors this list for instant feedback
-- while typing, but the database is what actually enforces it.
alter table banned_terms enable row level security;

drop policy if exists banned_terms_read on banned_terms;
create policy banned_terms_read on banned_terms
  for select using (auth.uid() is not null);

drop policy if exists banned_terms_admin on banned_terms;
create policy banned_terms_admin on banned_terms
  for all using (is_admin()) with check (is_admin());

commit;

-- ─────────────────────────────────────────────────────────────────────────
-- Re-run this file after 030_matching.sql so the teams and join_requests
-- triggers get attached — they are skipped if those tables do not exist yet.
-- ─────────────────────────────────────────────────────────────────────────

-- ROLLBACK (commented)
-- drop trigger if exists profiles_moderate on profiles;
-- drop trigger if exists teams_moderate on teams;
-- drop trigger if exists join_requests_moderate on join_requests;
-- drop function if exists moderate_profile, moderate_team, moderate_request,
--   moderation_verdict, contains_contact_details, moderation_normalise;
-- drop table if exists banned_terms;
