-- STUHI app — seed data.
--
-- Two jobs, and they matter for different reasons:
--
--   1. The real STUHI X TAMPERE event, so the app has genuine content.
--   2. Enough of it that App Review never sees an empty screen. A reviewer
--      may open this in September, weeks before the event, and Guideline 2.1
--      rejects submissions that look incomplete. An app showing "no events"
--      reads as broken, not as early.
--
-- Idempotent: safe to run repeatedly. Uniqueness is on natural keys
-- (slug, event+title) so re-running updates rather than duplicating.

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- The event
-- ─────────────────────────────────────────────────────────────────────────

insert into events (slug, name, tagline, venue, venue_address, starts_at, ends_at, published)
values (
  'stuhi-x-tampere-2026',
  'STUHI X TAMPERE',
  'Two days. One idea. Build it.',
  'Tampere University, Hervanta Campus',
  'Korkeakoulunkatu 1, 33720 Tampere',
  '2026-10-24 09:00:00+03',
  '2026-10-25 18:00:00+03',
  true
)
on conflict (slug) do update set
  name          = excluded.name,
  tagline       = excluded.tagline,
  venue         = excluded.venue,
  venue_address = excluded.venue_address,
  starts_at     = excluded.starts_at,
  ends_at       = excluded.ends_at,
  published     = excluded.published;

-- ─────────────────────────────────────────────────────────────────────────
-- Challenges
-- ─────────────────────────────────────────────────────────────────────────

with e as (select id from events where slug = 'stuhi-x-tampere-2026')
insert into challenges (event_id, ordinal, title, summary, body, partner, prize, published)
select e.id, v.ordinal, v.title, v.summary, v.body, v.partner, v.prize, true
from e, (values
  (1,
   'Get people moving',
   'Finnish teenagers sit more than any generation before them. Change that with something people actually want to open.',
   E'## The problem\n\nPhysical activity among 15–19 year olds in Finland has fallen every year for a decade. Most solutions are built by adults for adults.\n\n## What we want\n\nSomething a 16-year-old would open on a Tuesday without being told to. It can be an app, a device, a game, or something none of us thought of.\n\n## What good looks like\n\n- A real person tried it and came back the next day\n- It works without a subscription or a wearable\n- You can explain it in one sentence',
   null, null),
  (2,
   'Waste that pays for itself',
   'Turn something a Tampere business throws away into something worth money.',
   E'## The problem\n\nEvery café, workshop and campus building in Tampere throws away material with real value in it — heat, food, offcuts, packaging.\n\n## What we want\n\nA route from waste to value that a small business could actually adopt. Prototype the mechanism, not the pitch deck.\n\n## What good looks like\n\n- You talked to a real business during the weekend\n- The numbers roughly work\n- Someone would try it on Monday',
   null, null),
  (3,
   'Make the invisible visible',
   'Take data nobody looks at and turn it into something people cannot ignore.',
   E'## The problem\n\nAir quality, energy use, water, noise, queue times — the campus is full of measurements nobody sees.\n\n## What we want\n\nAn instrument, a screen, a sculpture, a service. Anything that turns a number into something a person feels.\n\n## What good looks like\n\n- It uses real data, not a mock-up\n- Someone walking past understands it in three seconds',
   null, null),
  (4,
   'Open challenge',
   'Build the thing you already wanted to build. Bring your own problem.',
   E'## The rules\n\nThere is one: it has to be built during the weekend.\n\nIf you arrive with an idea and it does not fit the other three challenges, this is your track. Judges look for the same things: does it work, did you make it here, and would anyone use it.',
   null, null)
) as v(ordinal, title, summary, body, partner, prize)
on conflict do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- Schedule
-- ─────────────────────────────────────────────────────────────────────────
-- The 'meal' rows are what the scanner claims against, so they must exist
-- before anyone can collect food.

with e as (select id from events where slug = 'stuhi-x-tampere-2026')
insert into schedule_items (event_id, starts_at, ends_at, title, detail, location, kind, for_audience, published)
select e.id, v.starts_at::timestamptz, v.ends_at::timestamptz, v.title, v.detail, v.location, v.kind, v.aud::audience, true
from e, (values
  -- Saturday
  ('2026-10-24 09:00+03', '2026-10-24 10:00+03', 'Doors and check-in',      'Have your pass ready on your phone.',        'Main entrance',   'session',  'public'),
  ('2026-10-24 10:00+03', '2026-10-24 10:45+03', 'Opening and challenges',  'What we are building and why.',              'Main hall',       'ceremony', 'public'),
  ('2026-10-24 10:45+03', '2026-10-24 11:30+03', 'Team forming',            'If you came alone, this is your slot.',      'Main hall',       'session',  'public'),
  ('2026-10-24 12:30+03', '2026-10-24 13:30+03', 'Lunch',                   'Vegetarian and vegan options.',              'Cafeteria',       'meal',     'public'),
  ('2026-10-24 15:00+03', '2026-10-24 15:30+03', 'Coffee',                   null,                                        'Atrium',          'break',    'public'),
  ('2026-10-24 18:00+03', '2026-10-24 19:00+03', 'Dinner',                  'Pizza. Lots of it.',                         'Cafeteria',       'meal',     'public'),
  ('2026-10-24 21:00+03', '2026-10-24 22:00+03', 'Mentor hours',            'Grab a mentor, ask anything.',               'Mentor corner',   'session',  'public'),
  -- Sunday
  ('2026-10-25 08:00+03', '2026-10-25 09:00+03', 'Breakfast',               null,                                         'Cafeteria',       'meal',     'public'),
  ('2026-10-25 12:30+03', '2026-10-25 13:30+03', 'Lunch',                   null,                                         'Cafeteria',       'meal',     'public'),
  ('2026-10-25 14:00+03', '2026-10-25 14:30+03', 'Submissions close',       'Everything must be submitted by 14:30.',     null,              'session',  'public'),
  ('2026-10-25 15:00+03', '2026-10-25 17:00+03', 'Demos',                   'Four minutes each.',                          'Main hall',       'session',  'public'),
  ('2026-10-25 17:00+03', '2026-10-25 18:00+03', 'Awards and closing',      null,                                          'Main hall',       'ceremony', 'public'),
  -- Monk-only
  ('2026-10-23 17:00+03', '2026-10-23 20:00+03', 'Venue build',             'Tables, signage, network. Bring gloves.',    'Main hall',       'session',  'monk'),
  ('2026-10-25 18:00+03', '2026-10-25 20:00+03', 'Teardown',                'Everyone stays until it is done.',            'Main hall',       'session',  'monk')
) as v(starts_at, ends_at, title, detail, location, kind, aud)
on conflict do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- Announcements
-- ─────────────────────────────────────────────────────────────────────────
-- Includes monk-only items, because the internal feed is a headline feature
-- and a reviewer signed in as the monk demo account needs to see it working.

with e as (select id from events where slug = 'stuhi-x-tampere-2026')
insert into announcements (event_id, title, body, for_audience, pinned, published)
select e.id, v.title, v.body, v.aud::audience, v.pinned, true
from e, (values
  ('Challenges are live',
   'All four challenges are now in the app. Read them before Saturday — the teams that start with a clear problem tend to finish with something that works.',
   'public', true),
  ('Bring your own laptop',
   'We have power, network and desks. We do not have spare laptops. Charger too.',
   'public', false),
  ('Coming alone? Good.',
   'About half of you are coming without a team. Fill in your profile in the Team tab and we will make sure you are on a team before the first session ends. Nobody works alone at this event.',
   'public', true),
  ('New: laser cutter in the workshop',
   'The workshop now has a laser cutter. Induction required before you use it — ask in the group chat and someone will run you through it.',
   'monk', false),
  ('Second room at Hervanta confirmed',
   'We have the second room for the whole weekend. That takes us from 380 to 500 seats, so we can open the last wave of tickets.',
   'monk', true),
  ('Equipment budget approved',
   'The equipment request went through. Order list is in the shared drive — add anything you need by the end of the month.',
   'monk', false)
) as v(title, body, aud, pinned)
on conflict do nothing;

commit;

-- ─────────────────────────────────────────────────────────────────────────
-- After running this, create the App Review demo accounts with
-- scripts/create-demo-accounts.sh. They are NOT created here, because their
-- passwords must not live in the repository.
-- ─────────────────────────────────────────────────────────────────────────
