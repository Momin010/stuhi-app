# Branches and releases

One app, one repo, three branches:

| Branch  | Who            | Ships? |
|---------|----------------|--------|
| `main`  | Momin merges   | every merge → TestFlight build |
| `momin` | Momin works    | no |
| `rene`  | Rene works     | no |

Work on your branch, open a pull request into `main`. Momin reads it and merges.
The merge starts `.github/workflows/testflight.yml`, and about 15 min later the build
shows up in TestFlight. Only pushes made by `Momin010` ship. Anyone else's push to
`main` builds nothing.

Keep your branch fresh: `git pull origin main` into it before you open a PR.

## App Store (major versions only)

TestFlight gets every merge. The App Store only gets a major version, done by hand:

1. In `ios/project.yml`, set `MARKETING_VERSION` to the new version (`"2.0"`), merge.
2. Wait for that build in TestFlight and test it.
3. https://appstoreconnect.apple.com/apps → STUHI → **+ Version** → same number →
   pick that build → release notes → **Submit for Review**.
4. Once that version is live, set `MARKETING_VERSION` to `"2.1"` right away. Apple
   refuses new TestFlight uploads for a version that has already been released.

## Backend

`server/` is the whole backend on Mark's box: Postgres, GoTrue, PostgREST, an nginx
gateway and its own Cloudflare tunnel at `https://stuhi-api.porkkanat.com`.
`./server/deploy.sh` ships `server/` + `backend/` and applies new `backend/*.sql`
files in filename order. A file that has been applied is never re-run, so change the
schema with a **new** numbered file, never by editing an old one.

## CI secrets (repo → Settings → Secrets → Actions)

`DIST_P12`, `DIST_P12_PASSWORD`: CI-only copy of the Apple Distribution cert ·
`PROVISION_PROFILE`: "STUHI App Store CI", expires with the cert on 21 Aug 2027 ·
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`: App Store Connect API key ·
`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`: the backend URL + public anon key.
