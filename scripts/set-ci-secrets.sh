#!/usr/bin/env bash
# Uploads the CI signing + backend secrets to GitHub Actions. Run once, and again
# when the cert or profile is renewed (next: 21 Aug 2027).
#   ./scripts/set-ci-secrets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source ~/.stuhi-app/env
source ~/.appstoreconnect/stuhi.env
SIGN=~/.stuhi-signing

base64 -i "$SIGN/ci-dist.p12" | gh secret set DIST_P12
gh secret set DIST_P12_PASSWORD < "$SIGN/ci-dist.p12.pass"
base64 -i "$SIGN/stuhi-app-store.mobileprovision" | gh secret set PROVISION_PROFILE
printf %s "$ASC_KEY_ID" | gh secret set ASC_KEY_ID
printf %s "$ASC_ISSUER_ID" | gh secret set ASC_ISSUER_ID
gh secret set ASC_KEY_P8 < ~/.appstoreconnect/private_keys/AuthKey_"$ASC_KEY_ID".p8
printf %s "$SUPABASE_URL" | gh secret set SUPABASE_URL
printf %s "$SUPABASE_PUBLISHABLE_KEY" | gh secret set SUPABASE_PUBLISHABLE_KEY
gh secret list
