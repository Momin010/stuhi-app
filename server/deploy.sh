#!/usr/bin/env bash
# From the Mac: ship server/ + backend/ to Mark's box and bring the stack up.
#   ./server/deploy.sh
# Writes the app's URL + public anon key into ~/.stuhi-app/env for make-config.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=stuhi-api.porkkanat.com

ssh mark 'mkdir -p ~/stuhi-app && chmod 700 ~/stuhi-app'
# --exclude keeps the box's own secrets, tunnel creds and database untouched.
rsync -a --exclude .env --exclude volumes --exclude tunnel/creds.json \
  --exclude tunnel/config.yml --exclude .applied server backend mark:stuhi-app/
out=$(ssh mark 'bash ~/stuhi-app/server/setup.sh' | tee /dev/stderr)
anon=$(grep '^ANON_KEY=' <<<"$out" | cut -d= -f2-)

mkdir -p ~/.stuhi-app && chmod 700 ~/.stuhi-app
env=~/.stuhi-app/env
touch "$env" && chmod 600 "$env"
grep -v -e '^SUPABASE_URL=' -e '^SUPABASE_PUBLISHABLE_KEY=' "$env" > "$env.tmp" || true
printf 'SUPABASE_URL=https://%s\nSUPABASE_PUBLISHABLE_KEY=%s\n' "$HOST" "$anon" >> "$env.tmp"
mv "$env.tmp" "$env"
echo "==> ~/.stuhi-app/env now points at https://$HOST"
