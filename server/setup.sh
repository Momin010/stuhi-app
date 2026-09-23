#!/usr/bin/env bash
# Runs ON Mark's box, from ~/stuhi-app/server. Idempotent — safe to re-run.
#   first run: makes secrets, the tunnel and its DNS name, starts the stack,
#              applies every backend/*.sql
#   later runs: restarts changed containers, applies only new .sql files
# Normally started by deploy.sh on the Mac, not by hand.
set -euo pipefail
cd "$(dirname "$0")"
HOST="${PUBLIC_HOST:-stuhi-api.porkkanat.com}"
TUNNEL=stuhi-app

# ~/stuhi-app holds the database and every secret; other sudo users share this box.
chmod 700 ..

jwt() {  # jwt <secret> <role> — a 10-year HS256 key, same shape Supabase issues
  python3 - "$1" "$2" <<'PY'
import base64, hashlib, hmac, json, sys, time
b = lambda x: base64.urlsafe_b64encode(x).rstrip(b"=").decode()
now = int(time.time())
h = b(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
p = b(json.dumps({"role": sys.argv[2], "iss": "supabase", "iat": now, "exp": now + 10 * 365 * 86400}).encode())
print(f"{h}.{p}." + b(hmac.new(sys.argv[1].encode(), f"{h}.{p}".encode(), hashlib.sha256).digest()))
PY
}

if [[ ! -f .env ]]; then
  echo "==> generating secrets"
  secret=$(openssl rand -hex 32)
  umask 077
  cat > .env <<ENV
PUBLIC_HOST=$HOST
POSTGRES_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$secret
ANON_KEY=$(jwt "$secret" anon)
SERVICE_ROLE_KEY=$(jwt "$secret" service_role)
ENV
  umask 022
fi

if [[ ! -f tunnel/creds.json ]]; then
  echo "==> creating tunnel $TUNNEL -> $HOST"
  cloudflared tunnel list 2>/dev/null | grep -qw "$TUNNEL" || cloudflared tunnel create "$TUNNEL"
  id=$(cloudflared tunnel list 2>/dev/null | awk -v n="$TUNNEL" '$2==n {print $1}')
  cp ~/.cloudflared/"$id".json tunnel/creds.json
  chmod 644 tunnel/creds.json   # the container runs as uid 65532; ~/stuhi-app is 700
  cloudflared tunnel route dns "$TUNNEL" "$HOST"
  cat > tunnel/config.yml <<YML
tunnel: $id
credentials-file: /etc/cloudflared/creds.json
ingress:
  - hostname: $HOST
    service: http://gateway:80
  - service: http_status:404
YML
fi

echo "==> starting stack"
docker compose up -d --remove-orphans

echo -n "==> waiting for auth"
for _ in $(seq 60); do
  curl -fs http://127.0.0.1:8010/auth/v1/health >/dev/null && break
  echo -n .; sleep 2
done
curl -fs http://127.0.0.1:8010/auth/v1/health >/dev/null || { echo " auth never came up"; docker compose logs --tail 30 auth; exit 1; }
echo " up"

touch .applied
for f in ../backend/*.sql; do
  name=$(basename "$f")
  grep -qx "$name" .applied && continue
  echo "==> applying $name"
  docker compose exec -T db psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres < "$f"
  echo "$name" >> .applied
done
docker compose exec -T db psql -q -U postgres -d postgres -c "notify pgrst, 'reload schema'"

# Printed so deploy.sh can hand it to the app. Public by design — RLS is the lock.
echo "ANON_KEY=$(grep ^ANON_KEY= .env | cut -d= -f2-)"
