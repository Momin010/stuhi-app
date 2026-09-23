#!/usr/bin/env bash
#
# Creates the two App Review demo accounts and prints their passwords ONCE.
#
# Guideline 2.1(a): "include demo account info (and turn on your back-end
# service!) if your app includes a login". A reviewer who cannot get in
# rejects the app, and a rejection costs days.
#
# Two accounts, not one, because this app has two faces and a reviewer must
# be able to see both:
#     reviewer@stuhi.org        → member  (attendee experience + a pass)
#     reviewer.monk@stuhi.org   → monk    (internal updates feed)
#
# The passwords are generated here and deliberately NOT stored in the repo.
# Put them in App Store Connect → App Review Information, and in a password
# manager. To rotate: delete the two rows from auth.users on the box, re-run.
#
# Runs against the self-hosted stack on Mark's box over ssh — the service key
# never leaves the server.
#     ./scripts/create-demo-accounts.sh
#
set -euo pipefail

gen_password() {
  # 24 chars, no ambiguous glyphs — a reviewer may have to type this by hand.
  LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 24
}

create_user() {
  local body
  body="$(python3 -c 'import json,sys; print(json.dumps({
        "email": sys.argv[1],
        "password": sys.argv[2],
        "email_confirm": True,
        "user_metadata": {"full_name": sys.argv[3]}
      }))' "$1" "$3" "$2")"
  # shellcheck disable=SC2016
  ssh mark 'cd ~/stuhi-app/server && k=$(grep ^SERVICE_ROLE_KEY= .env | cut -d= -f2-) &&
    curl -sS -X POST http://127.0.0.1:8010/auth/v1/admin/users \
      -H "Authorization: Bearer $k" -H "Content-Type: application/json" --data-binary @-' <<<"$body"
}

run_sql() {
  ssh mark 'cd ~/stuhi-app/server && docker compose exec -T db psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres' <<<"$1"
}

MEMBER_PW="$(gen_password)"
MONK_PW="$(gen_password)"

echo "→ creating reviewer@stuhi.org (member)"
create_user "reviewer@stuhi.org" "App Reviewer" "$MEMBER_PW" | head -c 200; echo

echo "→ creating reviewer.monk@stuhi.org (monk)"
create_user "reviewer.monk@stuhi.org" "App Reviewer (Monk)" "$MONK_PW" | head -c 200; echo

echo "→ granting the monk role and issuing passes"
run_sql "
  update profiles set account_role = 'monk'
   where lower(email) = 'reviewer.monk@stuhi.org';

  -- Both reviewers need a pass, or the Pass tab and the team matching (which
  -- is gated on holding a ticket) look empty and broken to them.
  insert into tickets (event_id, profile_id)
  select e.id, p.id
    from events e, profiles p
   where e.slug = 'stuhi-x-tampere-2026'
     and lower(p.email) in ('reviewer@stuhi.org','reviewer.monk@stuhi.org')
  on conflict (event_id, profile_id) do nothing;
"

cat <<EOF

────────────────────────────────────────────────────────────────
  Shown once. Copy these into App Store Connect now.

  Member reviewer
    email     reviewer@stuhi.org
    password  ${MEMBER_PW}

  Monk reviewer
    email     reviewer.monk@stuhi.org
    password  ${MONK_PW}

  App Store Connect → your app → App Review Information →
  "Sign-in required" → put the MEMBER account in the fields, and
  put the MONK account in the Notes for Review text.
────────────────────────────────────────────────────────────────
EOF
