# Shipping STUHI to Apple

Written 22 Aug 2026 against the live App Review Guidelines, fetched and quoted
the same day. Everything here is specific to this app. Where a rule is quoted it
is quoted verbatim with its number; where something is a judgement call it says
so and gives a confidence.

The sibling document at `/Users/mominaldahdouh/stuhi-finance/docs/APPSTORE.md` is
still correct **for that app**. Roughly half of it transfers here unchanged
(signing, toolchain, upload mechanics) and roughly half is actively wrong here
(distribution strategy, the 5.1.1(v) exemption, the privacy manifest contents).
Every place the two diverge is called out below.

**63 days to the event.** The hackathon is 24–25 October 2026 and it does not
move. A rejection cycle costs about a week end to end. That single fact is what
justifies the paranoia in this document: everything here is cheaper than one
avoidable round trip.

---

## Which door: public App Store listing, and why (vs the finance app)

**Submit for a normal public App Store listing.** Keep a warm TestFlight external
public link as an operational fallback so the event cannot fail on Apple's
calendar. Confidence: high (~85%).

This is a deliberate reversal of the finance app's conclusion, and the reversal is
correct because the fact that drove that conclusion has inverted.

Finance chose TestFlight, and possibly TestFlight forever, because it is *"an
internal tool with a fixed, known user list … Ten users, and no intention of ever
having more"* with no sign-up at all. That made Guideline 3.2 a live threat: a
reviewer signs in, can see nothing, and concludes the app is not for the general
public.

Every premise is false here:

| | STUHI Finance | STUHI (this app) |
|---|---|---|
| Users | ten known colleagues | ~500 external attendees plus the public |
| Sign-up | none — admin creates accounts | **open public sign-up, any email** |
| 3.2 risk | real, and the reason for TestFlight | **gone** — a reviewer signs up freely and gets the real app |
| 5.1.1(v) account deletion | exempt, argued in Review Notes | **mandatory, in-app** |
| 1.2 UGC | not applicable | **fully applicable, all four bullets** |
| Age rating | trivial | 13+, set manually, Social Media descriptor |
| Category | Finance | Education (primary), Social Networking (secondary) |
| Devices | iPhone + iPad | **iPhone only** |
| Backend | hosted Supabase EU — the free project was paused and the app went dead | self-hosted on Mark's box (`server/`), own tunnel at `stuhi-api.porkkanat.com`. Risk: the box must stay up for the whole review window |

So the threat model swaps: 3.2 walks out, and 1.2, 5.1.1(v), 5.1.1(viii) and the
age rating walk in. Those are the price of the public door and they must be paid
before submission or the door does not open.

### Why not TestFlight as the primary channel

Guideline 2.2, verbatim:

> "Demos, betas, and trial versions of your app don't belong on the App Store –
> use TestFlight instead. Any app submitted for beta distribution via TestFlight
> should be intended for public distribution and should comply with the App Review
> Guidelines."

TestFlight is a staging area for something headed to public distribution, not a
permanent home for a public product. Beyond that:

- **The 90-day build expiry is an event-day landmine.** A build uploaded 20 July
  expires 18 October — six days before the event, with 500 phones. Survivable,
  but a failure mode a public listing simply does not have.
- **Two-app onboarding at 500-person scale.** Install TestFlight, accept an
  invite, install STUHI. Every attendee lost in that funnel is a person at the
  door without a QR code.
- **It reads as beta** — orange dot on the home screen, beta chrome. Wrong signal
  for an association's public front door aimed at 16-year-olds and their schools.

### Why not unlisted distribution

Apple's unlisted-app page names our exact use case (*"conference attendees"*), and
we are rejecting it anyway, for five reasons:

1. **It contradicts the positioning.** The whole 4.2 defence is that this is a
   public association app with ongoing life. Requesting unlisted distribution
   tells Apple in writing that it is for a limited audience at one event.
2. **It costs more time, not less.** Verbatim: *"Before you request unlisted app
   distribution, your app must either already be on the App Store or be ready for
   final distribution and submitted to App Review."* Unlisted is the entire
   public-listing workload **plus** a separately human-processed request.
3. **It is close to a one-way door.** Verbatim: *"Your app's distribution method
   will change to Unlisted App in the Pricing and Availability section of the app
   record, and will apply to any future versions of the app."* Approval
   reclassifies the record, not the submission.
4. **It kills discovery.** *"Unlisted apps don't appear in any App Store
   categories, recommendations, charts, search results, or other listings."* A
   student who hears "get the STUHI app" and searches finds nothing.
5. **It defeats the post-October plan** (see Traps, below), which depends on the
   app accumulating visible public life.

Unlisted becomes right only if we take a 4.2 or 3.2 rejection whose reasoning is
fundamentally "this is for a closed audience" and it survives one appeal. Then we
pivot — which is why the timeline must not have spent its slack by then.

### The fallback, kept warm

| Channel | Role |
|---|---|
| **Public App Store listing** | Primary. What the Luma confirmation email, stuhi.org, the posters and the school outreach link to. |
| **TestFlight external public link** | Standing fallback, alive throughout. If the listing is in a rejection loop on 1 October, this is how 500 people get the app on 24 October. Also how the core team dogfoods every build. |

Rules for keeping it genuinely warm: create the external group and public link
**now**, not in October. Test Information (feedback email, what to test) and the
beta app description are required before an external group can receive anything,
and the **first build must clear Beta App Review** before the public link works at
all. Discovering that on 1 October is exactly the failure this fallback exists to
prevent. Upload the designated fallback build in the **first week of October** so
its 90-day clock expires in January.

Limits, confirmed: 10,000 external testers, 100 internal (each needs an App Store
Connect role), 30 devices per tester. And note 2.2's *"apps using TestFlight
cannot be distributed to testers in exchange for compensation of any kind"* — do
not tie a prize or a free meal to installing the beta.

### One architectural rule that outranks the distribution question

**Everything that can change during the event must be server-driven from
Supabase.** Schedule, challenges, announcements, meal windows, team assignments,
feature flags. A binary update is a minimum 24-hour round trip through App Review
*that can be rejected*, and there is no version of 24–25 October in which we want
Apple in the loop. If a session moves at 09:40 on Saturday, that is a database
write.

Caveat from 2.3.1(a): *"Don't include any hidden, dormant, or undocumented
features in your app."* A remote config that hides or degrades features the
reviewer already saw is fine. A flag that **unlocks** functionality not present at
review is a 2.3.1 violation. **Keep the kill-switch subtractive.**

---

## Signing, team and bundle id

Unchanged from the finance app, and the lesson there cost an identifier.

| Team | Name | What it is |
|---|---|---|
| `Q485H7YK66` | Nuorten startup- ja innovaatioyhdistys ry | **STUHI's paid Organization account — use this one** |
| `DQ54FKG6B4` | Momin Aldahdouh | Momin's free personal team. Profiles expire in **7 days**, never gets an Apple Distribution certificate, cannot reach TestFlight or the App Store |

`ios/project.yml` must set `DEVELOPMENT_TEAM: Q485H7YK66` **before any build runs
on any device.** The tell-tale if it ever regresses: decode a profile with
`security cms -D -i <file>.mobileprovision | plutil -p -` and read
`ExpirationDate` — one week means the personal team, one year means the paid one.

**Bundle identifier: `org.stuhi.app`, and it must be claimed under `Q485H7YK66`
today.** `org.stuhi.finance` was lost permanently because an early development
build auto-registered it to the *personal* team, App IDs are globally unique
across all of Apple, and a personal team's App IDs cannot be deleted from the
developer portal:

```
An App ID with Identifier 'org.stuhi.finance' is not available.
```

Same Mac, same two teams, same trap. Claim `org.stuhi.app` under the org team
before anything touches a device. Pre-agree the fallback: `org.stuhi.community`.

**Signing certificate.** `Apple Distribution: Nuorten startup- ja
innovaatioyhdistys ry (Q485H7YK66)`, valid to 21 Aug 2027, already installed. The
private key lives at `~/.stuhi-signing/stuhi-distribution.key` and is not in any
repo. **Back that folder up.** Lose it and the certificate is dead paper.

Sanity check any time: `security find-identity -v -p codesigning` must list an
`Apple Distribution:` line, not just `Apple Development:`.

**Toolchain.** From 28 April 2026, App Store Connect only accepts builds made with
Xcode 26 or later against the iOS 26 SDK. This Mac has 26.5. Deployment target
stays iOS 17. Note the implication the finance doc raised: building against the
iOS 26 SDK applies Liquid Glass to native UI by default, so **check the look on a
real device before taking screenshots**.

**Push capability must be on the App ID before the first distribution build.**
Retrofitting means regenerating provisioning profiles mid-timeline.

**APNs auth key.** Certificates, Identifiers & Profiles → Keys → enable Apple Push
Notifications service. Three facts that are commonly got wrong:

- **One key serves every app on the team.** It is not per-app. Finance and STUHI
  can share one.
- **The same key serves both development and production.** There is no "sandbox
  key".
- **There is a hard cap of two APNs auth keys per account.** The second exists for
  rotation. Do not burn both experimenting. The `.p8` is downloadable exactly
  once and is not recoverable.

**Build numbering.** `CURRENT_PROJECT_VERSION` must go up on every upload — App
Store Connect refuses a build number it has seen. `MARKETING_VERSION` only changes
when the human-visible version changes. Copy `upload.sh` and
`testflight-status.sh` from the finance repo rather than rewriting them; they
already handle this, and `testflight-status.sh` already encodes the hard-won fact
that **attaching a build to an external group submits it for Beta App Review by
itself** (an explicit `POST /v1/betaAppReviewSubmissions` afterwards fails with
`INVALID_QC_STATE`).

`ITSAppUsesNonExemptEncryption: NO` — HTTPS/TLS only, which is exempt. This stops
App Store Connect asking the export-compliance question on every upload, including
TestFlight uploads. It stays true only while the app performs no crypto of its
own; **the QR signing happens server-side**, so it does.

---

## The rejection reasons we are closing, one by one

### 1. Guideline 1.2 — User-Generated Content

> "Apps with user-generated content present particular challenges, ranging from
> intellectual property infringement to anonymous bullying. To prevent abuse, apps
> with user-generated content or social networking services must include:
> - A method for filtering objectionable material from being posted to the app
> - A mechanism to report offensive content and timely responses to concerns
> - The ability to block abusive users from the service
> - Published contact information so users can easily reach you
>
> Apps with user-generated content or services that end up being used primarily
> for pornographic content, Chatroulette-style experiences, random or anonymous
> chat, objectification of real people (e.g. "hot-or-not" voting), making physical
> threats, or bullying do not belong on the App Store and may be removed without
> notice. …
>
> It is your responsibility to remove content that violates this guideline, your
> terms of service, or your community standards."

And the second rule that governs the *design* rather than the content:

> "**1.1.1** Defamatory, discriminatory, or mean-spirited content, including
> references or commentary about religion, race, sexual orientation, gender,
> national/ethnic origin, or other targeted groups, particularly if the app is
> likely to humiliate, intimidate, or harm a targeted individual or group."

There is no version of this app that escapes 1.2 short of dropping bios and team
names, which is not the app. The UGC inventory is: **display name, bio, team name,
team description, free text on a join request or invite (if it ships), the note on
a report**. Not UGC: role tags, declared missing role, challenges, schedule, QR
tokens, check-ins, and — by decision — the monk feed.

**All four bullets, as a checklist:**

- [ ] **Filter on post, server-side.** A Postgres `BEFORE INSERT OR UPDATE`
      trigger on `profiles.bio`, `profiles.display_name`, `teams.name`,
      `teams.description`, `join_requests.message`. The client check is what Apple
      sees; the trigger is what makes it real, since anyone with the anon key and
      `curl` writes past the client.
- [ ] **Normalise before matching**: lowercase, strip diacritics, collapse repeats
      (`niiiiice`), map leetspeak (`3`→`e`, `1`/`!`→`i`, `0`→`o`, `@`→`a`), strip
      zero-width and combining characters. Naive `contains()` on a raw string is
      trivially bypassed and reviewers do try `f*ck`-style variants.
- [ ] **English and Finnish** slurs, sexual content and threats. Deliberately
      **not** ordinary Finnish swearing (`perkele`) — false positives on normal
      speech make the app feel broken and teach users to route around it.
- [ ] **Wordlists and regexes, not an LLM.** 5.1.2(i) now names third-party AI
      explicitly (see §10) and routing minors' bios through Groq would need its
      own consent gate and privacy-policy line. Not in 63 days.
- [ ] **Strip contact information** from all free text: emails, phone numbers,
      `@handle` patterns for Instagram / Snapchat / Telegram / Discord. Highest-
      value single rule in this document — it closes off-platform contact of
      minors, which is the harm 1.2 exists to prevent. **URLs are split**: allow
      them in `teams.description` against a small allowlist (github.com,
      gitlab.com, figma.com), strip them from `profiles.bio` and any request
      message. Blanket URL removal makes the app hostile to the thing it is for.
- [ ] **Length caps**: bio ≤ 280, team description ≤ 500, display name ≤ 40,
      report note ≤ 200, request message ≤ 140 if it ships at all.
- [ ] **Reject with a clear message.** Do not silently mangle.
- [ ] **Report action two taps from every UGC surface** — profile detail overflow
      (`ellipsis.circle`), team detail overflow, incoming request row (swipe *and*
      overflow), and `.contextMenu` on any list row showing a bio snippet.
      Nothing in the guidelines specifies placement, but a report buried in
      Settings is a common cause of 1.2 rejections. Treat two-taps as the design
      target, not as a published rule.
- [ ] **Report sheet**: fixed reason picker (Harassment or bullying / Sexual
      content / Hate speech or slurs / Threat or violence / Spam or scam /
      Impersonation / Something else), optional 200-char note, explicit
      confirmation. Queue locally and confirm even on network failure — a silently
      failing report is worse than none.
- [ ] **`reports` table carries `reporter_id` and `content_ref`.** Required by DSA
      Art. 16, which applies to all hosting providers regardless of size (see
      Traps).
- [ ] **Report insert fires a database webhook** emailing `moderation@stuhi.org`
      and pushing to the organisers' channel.
- [ ] **Block offered everywhere Report is** — same overflow menu. Reviewers look
      for them together.
- [ ] **Block is immediate and local-first**: hide optimistically, then write. No
      spinner while a harasser is on screen.
- [ ] **Block effects enforced server-side in the query**, never on the device:
      blocked user absent from the blocker's lists; cannot send a join request or
      invite to the blocker or to a team the blocker is in; any pending request
      between them is cancelled; **the blocked user is not told** (silent, or you
      have built a retaliation trigger). Implement as
      `blocks(blocker_id, blocked_id, created_at)` plus a view/RPC excluding rows
      where a block exists in either direction. Client-side filtering leaves the
      blocked user's data on the blocker's device.
- [ ] **Symmetric invisibility — this is STUHI's choice, not Apple's rule.**
      Apple's requirement is one-directional. We go symmetric because 500
      teenagers share one building for 48 hours. The cost is that a malicious user
      could block half the cohort to become invisible, so: **cap at 20 blocks**,
      and blocked users stay visible and reportable to moderators regardless.
- [ ] **Settings → Blocked People**, with Unblock.
- [ ] **Published contact information in the app**: Settings → About → Contact
      STUHI, showing `moderation@stuhi.org` ("Report a problem or a person"),
      `support@stuhi.org` ("Help with the app"), and "Nuorten startup- ja
      innovaatioyhdistys ry" with the registered address and register number.
      **Both mailboxes must exist and be read before submission.**
- [ ] **Self-removal of own content.** The second-round 1.2 rejection asks for
      *"a mechanism for users to immediately remove posts."* Concretely: clear
      your own bio; edit or delete your team's description if you own it; withdraw
      a sent join request. All immediate, all in-app.
- [ ] **`visible boolean not null default true`** on every UGC row, reads through
      a view or RPC filtering on it. This is the take-down mechanism.
- [ ] **`profiles.banned_at timestamptz`**; sign-in refuses when set and all that
      user's content is hidden. This is the eject-the-user mechanism.
- [ ] **A named moderator rota with 24-hour coverage** from go-live to 1 November,
      staffed by **adults from the core team, not attendees**, written down. If
      Apple ever asks for "a plan to improve your compliance", that document is
      the answer.
- [ ] **Moderator actions logged**: `status`, `resolved_by`, `resolved_at`,
      `action_taken`. A Supabase Studio saved query is acceptable tooling — App
      Review never sees it, so spend zero binary days on a console.

**The rejection-letter question, stated honestly.** App Review's 1.2 rejection
boilerplate asks for five things: an EULA with a no-tolerance clause, filtering,
flagging, blocking, and acting on reports within 24 hours. That letter is real and
well attested. But **grep of the live guidelines returns zero hits for "EULA" and
zero for "24 hours"**. Build to it — it is cheap — but never write "Apple requires
X" in an internal document where X exists only in the rejection letter.
Corroboration for the boilerplate clusters in 2017–2020; treat it as a strong
prior about reviewer behaviour, not a citable rule.

**The custom EULA.** Apple's standard Licensed Application EULA contains exactly
one relevant line, in section (d) External Services: *"You agree not to use the
External Services to harass, abuse, stalk, threaten or defame any person or
entity."* That is a disclaimer about Apple-provided external services. It names no
enforcement and does not bind users of STUHI's backend. So:

- [ ] Host custom terms at `https://stuhi.org/terms`, **Finnish and English**,
      plain language, containing a no-tolerance clause, the 13+ minimum, that
      posted content is visible to other attendees, how to report, how to block,
      how to delete your account, the moderation address, and how long reports
      take.
- [ ] **Select Custom License Agreement** in App Store Connect → App Information →
      License Agreement, and paste it. Leaving Apple's standard EULA in place
      while claiming a no-tolerance clause in Review Notes contradicts yourself in
      the two places a reviewer looks.
- [ ] At sign-up, **before** the account is created: an **unticked** checkbox — "I
      have read and agree to the STUHI Terms of Use and Privacy Policy" — with
      both as tappable links. Continue disabled until ticked. *Pre-ticked is a
      GDPR problem (Art. 4(11) read with* Planet49*, CJEU C-673/17), not an Apple
      5.6 problem — 5.6 is about purchases and data extraction. Cite the right
      authority.*
- [ ] Persist `accepted_terms_version` and `accepted_terms_at`. Bump on change,
      re-prompt with a blocking sheet.
- [ ] A permanent one-line reminder above the bio field: "Your bio is visible to
      other attendees. No contact details, no offensive language." Not a
      dismissible alert. **Highest-yield UI in the whole stack**, because it
      prevents the post rather than cleaning it up.

**Design rules that keep us off 1.2's prohibited list** — every one of these is a
decision already taken and must not be quietly undone:

- Browse **teams**, not people, by default. Individuals appear inside a team, and
  in a "looking for a team" list visible **only to users who are themselves
  unteamed and verified**. Reciprocity: you can only be seen by people equally
  exposed.
- **Signing up does not grant access to people.** Two states: *signed-up* and
  *verified attendee*. Verification comes from matching the imported roster. An
  unverified account sees challenges, schedule, org info and its own profile, and
  a card reading "Team matching opens when your registration is confirmed." That
  is a complete app for the public, so 4.2/4.3 stay satisfied while the directory
  of minors stays closed to the world. **This rule also does double duty in EU
  law** — see Traps.
- Team matching is **additionally gated on the event window**, opened by an
  organiser flag and closed after 25 October. Not a permanent public directory of
  teenagers.
- **No user-uploaded profile photos in v1.** Generated monogram avatars from the
  roster name. Removes image moderation (a word list cannot do it), photos of
  minors, `NSPhotoLibraryUsageDescription`, a privacy-manifest data type, and the
  single largest thing that makes the browse screen read as a dating app.
  Non-negotiable for 63 days.
- **No ordering that implies rank.** Sort by role-need match, then recency, then a
  per-viewer stable shuffle. Never "most requested" or "profile completeness".
- **No counters of social success.** No "12 people want to join", no view counts,
  no "3 invites received". A "0 people want to join your team" counter is what
  1.1.1 means by *likely to humiliate a targeted individual*, applied to a
  16-year-old.
- **No like, skip, favourite, star or swipe anywhere.** The only actions on a
  person or team: View, Request to join / Invite, Report, Block. A left/right
  swipe on a person card must not exist even if it does something innocuous.
- **No filtering or free-text search on anything about the person.** Filter on
  role needed and challenge. Never age, school, gender, or search over bios.
- **Requests strictly directed.** A join request visible only to that team's
  members; an invite only to its recipient. Nothing broadcast.
- **Rate-limit requests server-side**: one pending per user per team, max 3
  outgoing pending, 24-hour cooldown after a decline, hard cap of 2 attempts per
  team. Without this, "request to join" is a harassment channel.
- **Declining is silent and needs no reason.** No "tell them why" field — that is
  a bullying channel with a UI around it.
- **Auto-assign never surfaces a ranking.** "You've been placed on Team 12." No
  score, no compatibility percentage, no who-was-picked-over-you.
- **The bio is optional.** 5.1.1(iii) and 5.1.1(x) both point this way. A
  16-year-old who does not want to write a public paragraph about themselves must
  still be placeable on a team; role tags alone are enough for matching.
- **No in-app messaging in v1.** See Traps for the full argument — it is the
  hardest 1.2 obligation, not the easiest, and it is cut.

### 2. Guideline 2.1 — App Completeness

> "**2.1 (a)** Submissions to App Review, including apps you make available for
> pre-order, should be final versions with all necessary metadata and fully
> functional URLs included; placeholder text, empty websites, and other temporary
> content should be scrubbed before submission. Make sure your app has been tested
> on-device for bugs and stability before you submit it, and include demo account
> info (and turn on your back-end service!) if your app includes a login. If you
> are unable to provide a demo account due to legal or security obligations, you
> may include a built-in demo mode in lieu of a demo account **with prior approval
> by Apple**. Ensure the demo mode exhibits your app's full features and
> functionality. We will reject incomplete app bundles and binaries that crash or
> exhibit obvious technical problems."

**Apple publishes the base rate and it is the most important number in this
document: *"On average, over 40% of unresolved issues are related to guideline
2.1: App Completeness."*** Content readiness is the schedule driver, not code
readiness, and not 4.2.

Note the demo-mode clause needs *prior approval by Apple*. We can trivially
provide demo accounts, so the demo-account path is the only one open. Do not plan
around a demo mode.

- [ ] **Every challenge fully written.** No "Challenge 1 / Challenge 2", no lorem.
- [ ] **Every schedule row real.** If the final schedule is not settled by 12
      September, ship a truthful provisional agenda with real sessions labelled
      "Provisional". **Never "TBA".**
- [ ] **Monk feed populated** with several genuine association posts.
- [ ] **Demo dataset populated** — plausible teams and bios so the matching UI is
      not an empty state.
- [ ] **`stuhi.org/terms`, `/privacy` and `/support` live and reachable from
      outside Finland.** A 404 is a 2.1 rejection: *"All links in your app must be
      functional. A link to user support with up-to-date contact information and a
      link to your privacy policy is required for all apps."*
- [ ] **Backend live throughout the review window.** It is a named bullet in
      Apple's Before You Submit list, not an inference.
- [ ] **A cold sign-up completes end to end from a network outside Finland.**
      Decide now whether Supabase email confirmation is on; if it is, ship
      pre-confirmed demo accounts and say so in Review Notes. *A reviewer creating
      an account and then waiting for a confirmation email they cannot access is a
      silent, guaranteed rejection.*
- [ ] **Password reset tested.** Reviewers hit it more often than expected.
- [ ] **Move off Supabase's built-in SMTP.** It is rate-limited and not for
      production. Real provider, SPF and DKIM on stuhi.org.
- [ ] **The scanner must never show a black rectangle.** Camera denied, no camera,
      or no code to point at must all produce a styled explanatory state, plus an
      **"Enter code manually"** field. This is both the 2.1 fix and a genuine
      operational feature for 25 October — cracked screen, dead phone, glare.
- [ ] **A sample QR the reviewer can actually scan on one device**: an in-app
      "Demo: show a sample attendee QR" affordance on the staff account, plus a
      live image at a URL cited in Review Notes.
- [ ] **Test on-device, not just the simulator.** Remote push does not work in the
      Simulator in a way you can trust.

### 3. Guideline 2.3 — Accurate Metadata

> "**2.3.1 (a)** Don't include any hidden, dormant, or undocumented features in
> your app; your app's functionality should be clear to end users and App Review.
> All new features, functionality, and product changes must be described with
> specificity in the Notes for Review section of App Store Connect (**generic
> descriptions will be rejected**) and accessible for review."

> "**2.3.3** Screenshots should show the app in use, and not merely the title art,
> login page, or splash screen."

> "**2.3.6** Answer the age rating questions in App Store Connect honestly so that
> your app aligns properly with parental controls. If your app is mis-rated,
> customers might be surprised by what they get, or it could trigger an inquiry
> from government regulators."

> "**2.3.7** … App names must be limited to 30 characters. Metadata such as app
> names, subtitles, screenshots, and previews should not include prices, terms, or
> descriptions that are not specific to the metadata type."

> "**2.3.8** Metadata should be appropriate for all audiences, so make sure your
> app and in-app purchase icons, screenshots, and previews adhere to a 4+ age
> rating even if your app is rated higher. … Use of terms like 'For Kids' and 'For
> Children' in app metadata is reserved in the App Store for the Kids Category."

> "**2.3.9** You are responsible for securing the rights to use all materials in
> your app icons, screenshots, and previews, and you should display fictional
> account information instead of data from a real person."

> "**2.3.10** … Make sure your app metadata is focused on the app itself and its
> experience. Don't include irrelevant information."

**2.3.1(a) is the rule that governs the monk feed and the staff scanner**, and it
is stronger than the 2.1 framing. Both are invisible to a member account, so both
are "hidden" unless described with specificity and made accessible for review.
"The app has an admin mode" is a generic description and generic descriptions are
rejected. Name the tab, name the screen, name the tap path.

- [ ] App name **`STUHI: Student Innovation`** (25/30). Never a hackathon name,
      never a year, never a date.
- [ ] Subtitle **`Startup community & events`** (26/30).
- [ ] Description: association first, hackathon named as *the current event* in
      paragraph three or later. Include the line *"This app is published by STUHI
      and is not affiliated with, endorsed by, or sponsored by any university or
      venue."*
- [ ] **No screenshot may be the role chooser or the sign-in screen** (2.3.3). The
      role chooser is the most distinctive screen in the app and the temptation to
      lead with it is exactly the shape of a 2.3.3 rejection.
- [ ] **No real attendee data anywhere in screenshots** (2.3.9). Invented names,
      invented bios, a QR that resolves to nothing.
- [ ] **Trademark clearance on "STUHI"** via TMview / EUIPO / PRH before the App
      Store Connect record is created. Put the PRH register number in Review
      Notes.
- [ ] **No third-party marks** — "Tampere University", "Hervanta Campus", sponsor
      names — in app name, subtitle, keywords or icon. Hervanta as a place name in
      promotional text and inside the schedule content is factual and fine.
- [ ] **No mention of Luma** in metadata.
- [ ] **Content Rights** declared: challenge briefs authored by partner companies
      are third-party content and we need the partners' permission to publish
      them.
- [ ] Copyright field: `2026 Nuorten startup- ja innovaatioyhdistys ry`. No `©` —
      Apple adds it.

**The "children" trap, which the audience creates.** 5.1.4 ends:

> "Apps not in the Kids Category cannot include any terms in app name, subtitle,
> icon, screenshots or description that imply the main audience for the app is
> children."

That is broader than two banned phrases, and it covers the **icon**. "Students",
"opiskelijat", "lukiolaiset", "upper-secondary students" are all fine — teenagers
are not children. Ruled out: a cartoon mascot icon, crayon lettering, "young
learners", anything that reads as juvenile. Brief whoever makes the icon on this
explicitly.

### 4. Guideline 3.2.2(v) — arbitrarily restricting who may use the app

> "**3.2.2 Unacceptable (v)** Arbitrarily restricting who may use the app, such as
> by location or carrier."

**Verdict: not a threat here. Confidence high (~90%)**, conditional on the items
below. The monk tier restricts a *section*, not the app; anyone can install, sign
up freely, get a QR, join a team. The tier is **additive, not subtractive**. And
it is not arbitrary — it maps to a real, verifiable organisational status, which
is what "arbitrarily" is doing in that sentence. Structurally identical to any app
with an admin role.

The one screen that can accidentally create the appearance of a violation is the
role chooser.

- [ ] **The role chooser routes; it never gates.** Whatever a reviewer taps, they
      reach a working app.
- [ ] **"Monk" must never dead-end.** Picking it without the flag signs you in as
      a member anyway, with a neutral line: "STUHI team access is granted by the
      association — email team@stuhi.org if that's you." A reviewer who taps
      "Monk", gets stuck and back-buttons out is one tap from writing the
      rejection.
- [ ] **Never a client-side email-domain check.** Everyone signs up through the
      identical flow; `is_monk` is a server-side profile flag granted by an org
      admin, and the `@stuhi.org` address is a precondition the admin checks. A
      sign-up screen that rejects non-`@stuhi.org` addresses is the one version of
      this that *would* look like restricting who may use the app.
- [ ] **Enforce the monk feed in RLS, not in SwiftUI.** Hiding a tab is not access
      control; a client-only gate turns a compliance non-issue into a privacy
      incident.
- [ ] **Localise to English as well as Finnish, and default to English on a device
      not set to Finnish.** A reviewer in Cupertino landing in an all-Finnish UI
      cannot evaluate the app and will find something to reject. Highest-leverage
      cheap fix on the whole list.
- [ ] **Logged-out browse mode** for schedule, challenges and association info.
      5.1.1(v)'s first sentence invites it; it strengthens 4.2 (a reviewer sees
      real content before touching credentials), removes any whiff of 3.2.2(v),
      reduces personal data collected from 15-year-olds, and gives a working app to
      someone at the door whose sign-in is failing.

One adjacent line for the future: **3.2.2(iv)** forbids collecting funds for
charities in-app unless you are an approved non-profit, and *"Apps that seek to
raise money for such causes must be free on the App Store and may only collect
funds outside of the app."* Irrelevant today. It becomes a hard rule with an
approval process the moment anyone adds a donate button or ticket payment. **Ship
v1 with no money in it.**

**Territory restriction is not a 3.2.2(v) problem.** That rule is about gating
*within* a distributed app. Which storefronts you publish to is a first-class App
Store Connect control Apple expects developers to use. See §Age rating for why we
use it.

### 5. Guideline 4.2 — Minimum Functionality

> "**4.2** Your app should include features, content, and UI that elevate it
> beyond a repackaged website. If your app is not particularly useful, unique, or
> 'app-like,' it doesn't belong on the App Store. If your App doesn't provide some
> sort of lasting entertainment value or adequate utility, it may not be
> accepted."

> "**4.2.2** Other than catalogs, apps shouldn't primarily be marketing materials,
> advertisements, web clippings, content aggregators, or a collection of links."

Apple's own gloss adds the sentence that most directly threatens an event app:
*"If your app doesn't offer much functionality or content, **or only applies to a
small niche market**, it may not be approved."*

**Assessment: survivable, and not the top existential risk. ~85% that a correctly
shipped build clears 4.2 first pass.** The residual is presentation, not
substance, and presentation is entirely under our control.

The honest case *for* rejection: a reviewer signing in five weeks before the event
sees a table of times, a list of paragraphs, an empty Teams tab and a QR code that
means nothing to them. That composite reads like the aggregator pattern 4.2.2
names, unless the reviewer can actually operate the scanner and the matching flow.

The case for safety is stronger, because six things here are structurally
impossible for a website:

1. Hardware-backed camera QR scanning with a staff-side state machine (admitted /
   meal claimed / duplicate).
2. **The app is the issuing authority for a cryptographic credential**, not a
   viewer of remote content — and the token verifies **offline**, with no network
   call.
3. Push notifications — an OS integration, by definition not a web clipping.
4. A directed request/accept social graph with real state, writes and conflict
   resolution.
5. Role-gated content tiers backed by server-side authorisation.
6. User-generated content — the opposite of aggregation.

- [ ] **Structurally an association app with an events layer.** There must be an
      `events` concept in the data model and in the UI, even with exactly one row
      today. The hackathon is an entry *inside* the app, reachable from a screen
      that also carries STUHI's year-round life. A reviewer arriving on 3 November
      must find a live, useful app rather than a dead schedule. This same decision
      protects us under 4.3(a) and under App Store Improvements.
- [ ] **Metadata is STUHI-first** (see §3).
- [ ] **Offline QR verification built and mentioned in Review Notes.** Also the
      operationally correct answer: Hervanta with 500 phones on one weekend is a
      hostile network.
- [ ] **Category: Education primary, Social Networking secondary.** Confidence
      moderate (~65–85%) — a genuine coin flip, either defensible. Education wins
      because Social Networking maximises 1.2 scrutiny, and because neither
      Education nor Social Networking is a Time Allowance category, so the choice
      costs nothing there. 2.3.5 also says miscategorisation is low-cost: *"If
      you're way off base, we may change the category for you."*

**On 4.2.6 (templates).** Its text ends with *"or as an event app with separate
entries for each client event"*, which is Apple acknowledging that event apps are
an acceptable App Store shape — useful design confirmation. **Do not cite it as a
shield.** That sentence is a *permission granted to template providers*, and
quoting it invites the question "wait — is this a template app?", which was never
on the table. Cite only 4.2.6's opening clause if it ever comes up: template apps
are rejected *"unless they are submitted directly by the provider of the app's
content"*, and STUHI writes the SwiftUI and provides every challenge, schedule row
and announcement. ~90% that 4.2.6 never surfaces at all.

### 6. Guideline 4.3 — Spam

> "**4.3 (a)** Don't create multiple Bundle IDs of the same app (for example,
> submitting a separate map app for every city in the world instead of a single
> worldwide map that allows users to search any city). This practice results in
> unnecessary apps, which makes it hard for users to find the apps they want. If
> your app has different versions for specific locations, sports teams,
> universities, etc., consider submitting a single app and providing the
> variations using in-app purchase."

> "**4.3 (b)** Don't submit apps that are indistinguishable from what's already
> widely available. … Certain kinds of apps, such as **dating**, flashlight, sound
> effects, wallpaper, simple timers, and fortune telling, are well established on
> the App Store and we will not accept new submissions unless they offer a
> meaningfully different or improved experience."

**One binary. Confidence very high (~95%).** The member/monk split is a permission
tier inside one product — precisely the "single worldwide map" shape Apple asks
for. Two bundle ids (`org.stuhi.app` and `org.stuhi.monks`) would be the textbook
violation: same app, same content, differing only in which rows the server
returns.

- [ ] **No separate app per event.** "STUHI Hackathon 2026" and "…2027" as two
      bundle ids is 4.3(a) on the plainest reading of the "sports teams,
      universities, etc." clause. The events layer is what makes 2027 a content
      change rather than a submission.
- [ ] **Decline the IAP suggestion.** 4.3(a)'s last sentence proposes in-app
      purchase for variations. We have none and want none; the variation here is a
      free, org-granted role. Adding IAP to satisfy a sentence that does not apply
      opens 3.1.1 and is strictly worse.
- [ ] **Rule for the future: one bundle id per distinct product, never per
      audience segment, never per event.**

**STUHI Finance is not a second bundle id of the same app** — different purpose,
audience, feature set, zero content overlap. 4.3(a) targets duplicates, not
portfolios. One-line answer if it ever comes up: "STUHI Finance is a bookkeeping
tool for the association's treasurers; it shares no features or content with this
app." Be aware, though, that the team now has two apps and a third would attract
attention: Apple's gloss is *"Submitting several apps that are essentially the
same ties up the App Review process."*

**4.3(b) and the dating adjacency.** The removal threat in 4.3(b) is anaphoric —
*"We may remove **these** apps"* refers back to the enumerated categories, which do
not include association apps (~80% on the grammar; do not lean on it alone). The
angle that *does* apply is "indistinguishable from what's already widely
available": event apps are a crowded shelf (Whova, Bizzabo, EventMobi, Luma). And
**dating is on 4.3(b)'s list, and "team matching" is one design decision away from
reading as a dating app.** That is a second, independent reason — beyond 1.2 — for
the directed request/accept flow and no swipe deck.

- [ ] Review Notes states: *"Team matching is a directed request-and-accept flow
      between a person and a team. There is no swipe interface, no profile
      browsing for its own sake, no rating or ranking of people, and no romantic
      or dating intent."*

### 7. Guideline 4.5.4 — Push Notifications

> "**4.5.4** Push Notifications must not be required for the app to function, and
> should not be used to send sensitive personal or confidential information. Push
> Notifications should not be used for promotions or direct marketing purposes
> unless customers have explicitly opted in to receive them via consent language
> displayed in your app's UI, and you provide a method in your app for a user to
> opt out from receiving such messages. Abuse of these services may result in
> revocation of your privileges."

> "**4.5.3** Do not use Apple Services to spam, phish, or send unsolicited messages
> to customers, including Game Center, Push Notifications, Live Activities, etc."

And the fifth obligation, which is unconditional and sharper than 4.5.4's first
sentence:

> "**5.1.2(i)** … Your app may not require users to enable system functionalities
> (e.g. push notifications, location services, tracking) in order to access
> functionality, content, use the app, or receive monetary or other compensation,
> including but not limited to gift cards and codes."

Our pushes — meal service, schedule changes, team placement — are operational, not
promotional, so 4.5.4's opt-in and opt-out clauses do not strictly bind. **Build
them anyway**, for three reasons: a reviewer cannot tell operational from
promotional from the outside; the audience is 15–19 with minors in it; and the
moment someone sends "come to next month's meetup!" the pushes *become*
promotional and we are retroactively non-compliant with no toggle to point at.

- [ ] **No `requestAuthorization` on first launch.** A pre-permission explainer
      first, naming the categories and stating the negative: *"We never send
      advertising or marketing."* That sentence is what lets a reviewer close
      4.5.4 without thinking.
- [ ] **"Not now" is a real, non-punitive path into the full app.**
- [ ] **Settings → Notifications inside the app**, with per-category toggles
      (meals, schedule changes, team matching, association announcements for monks
      only), a master pause, and a line pointing at iOS Settings. **Persisted
      server-side** so the backend genuinely stops sending — an opt-out that only
      relies on the OS is not "a method in your app for a user to opt out" in any
      meaningful sense.
- [ ] **Never a required permission.** Verify every line below on a device with
      notifications **denied**, before submission:
  - [ ] The full schedule, including any change already pushed, is in the Schedule
        tab with the change marked.
  - [ ] Meal windows appear in the schedule and on Home.
  - [ ] Team placement is visible in the Teams tab the moment it happens.
  - [ ] Join requests and invites are listed in-app with counts. No request/accept
        flow is actionable *only* from a notification.
  - [ ] QR generation, display and scanning work with push fully off.
  - [ ] Sign-up, sign-in and account deletion work with push fully off.
  - [ ] No screen says "enable notifications to continue".
  - [ ] Denying never re-prompts on a loop.
- [ ] **No sensitive information in a payload.** Never a QR payload or token.
      Never dietary requirements, allergies or accessibility needs. Never another
      attendee's name plus contact details. *"You have a new join request"* is
      fine; *"Aino Virtanen (aino@…) wants to join"* on a lock screen is not.
- [ ] **Never user-generated text in a payload.** "Ali invited you to Team 12" is
      fine; "Ali: \<free text\>" routes unfiltered UGC to a lock screen and
      bypasses every filter we built. **Team names are UGC too** — use the team
      number in push, or have the notification service read the name only through
      the moderated view and re-check `visible` at send time.
- [ ] **Second person, not third.** "Sinut on sijoitettu tiimiin 12 / You've been
      placed on Team 12" — not "Momin Aldahdouh has been placed on Team 12" on a
      lock screen in a crowded hall.
- [ ] **Direct APNs from a Supabase Edge Function.** No Firebase, no OneSignal —
      FCM drags in a Google SDK and a whole new privacy-manifest and data-sharing
      disclosure problem.
- [ ] **The Edge Function selects the APNs host from the build environment and
      logs rejections.** This is the classic way an event-day push system dies: a
      development-signed build's token is valid only on
      `api.sandbox.push.apple.com`, while **TestFlight and App Store builds are
      distribution-signed and their tokens are valid only on
      `api.push.apple.com`**. Wrong pairing returns `BadDeviceToken`, and if the
      function swallows errors it fails **silently**.
- [ ] **Verify push on a TestFlight build**, not just a debug build, for exactly
      that reason.

### 8. Guideline 4.8 — Login Services

> "**4.8** Apps that use a third-party or social login service (such as Facebook
> Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login with Amazon,
> or WeChat Login) to set up or authenticate the user's primary account with the
> app must also offer as an equivalent option another login service … Another
> login service is not required if: **Your app exclusively uses your company's own
> account setup and sign-in systems.** …"

**Exempt on the first bullet. Confidence ~95%.** Email/password against STUHI's
own Supabase GoTrue instance is our own account system. Supabase being a hosted
vendor is irrelevant — the user never authenticates *to Supabase as an identity
provider*, no third-party account exists, no third-party login button appears.
Magic link / email OTP would be equally exempt.

- [ ] **Do not add Sign in with Apple "to be safe."** It adds a privacy-manifest
      surface, a data-type disclosure and an account-linking edge case for zero
      compliance benefit.
- [ ] **No social login before 24 October.** If anyone adds Google, three things
      follow, all bad on this timeline: SIWA becomes required (the specific 4.8
      bullet email/password fails is the second — a first-party email/password
      system by construction cannot "allow users to keep their email address
      private as part of setting up their account"); Apple private-relay addresses
      (`abc123@privaterelay.appleid.com`) break the `@stuhi.org` monk
      precondition; and the Google SDK contradicts the no-third-party-SDK posture
      and drags in its own privacy manifest to merge. Adding SIWA also adds a
      token-revocation step to the delete-account function: *"Apps that support
      Sign in with Apple should use the Sign in with Apple REST API to revoke user
      tokens."*

### 9. Guideline 5.1.1 — Data Collection and Storage

> "**(i) Privacy Policies.** All apps must include a link to their privacy policy
> in the App Store Connect metadata field **and within the app in an easily
> accessible manner**. The privacy policy must clearly and explicitly: Identify
> what data, if any, the app/service collects, how it collects that data, and all
> uses of that data. Confirm that any third party with whom an app shares user
> data … will provide the same or equal protection of user data … Explain its data
> retention/deletion policies and describe how a user can revoke consent and/or
> request deletion of the user's data."

> "**(ii) Permission.** Apps that collect user or usage data must secure user
> consent for the collection … Apps must also provide the customer with an easily
> accessible and understandable way to withdraw consent. Ensure your purpose
> strings clearly and completely describe your use of the data."

> "**(iii) Data Minimization.** Apps should only request access to data relevant to
> the core functionality of the app and should only collect and use data that is
> required to accomplish the relevant task. Where possible, use the out-of-process
> picker or a share sheet rather than requesting full access to protected
> resources like Photos or Contacts."

> "**(iv) Access.** Apps must respect the user's permission settings … Where
> possible, provide alternative solutions for users who don't grant consent."

> "**(v) Account Sign-In.** If your app doesn't include significant account-based
> features, let people use it without a login. **If your app supports account
> creation, you must also offer account deletion within the app.** Apps may not
> require users to enter personal information to function, except when directly
> relevant to the core functionality of the app or required by law."

> "**(vii)** SafariViewController must be used to visibly present information to
> users; the controller may not be hidden or obscured by other views or layers."

> "**(viii)** Apps that compile personal information from any source that is not
> directly from the user or without the user's explicit consent, even public
> databases, are not permitted on the App Store or alternative distribution."

> "**(x)** Apps may request basic contact information (such as name and email
> address) so long as the request is optional for the user, features and services
> are not conditional on providing the information …"

**5.1.1(v) is the single biggest delta from the finance app.** That document says,
correctly for itself: *"Accounts are created only by the organisation's admin; the
app has no account creation, so 5.1.1(v) does not apply."* **That line must not be
copied here.** Copying it would be a written admission of non-compliance in the
one field a reviewer definitely reads.

There is exactly one exemption and it does not apply to us: Apple's support page
allows a customer-service deletion flow only for *"apps in highly regulated
industries, as described in App Store Review Guideline 5.1.1(ix)"* — banking,
healthcare, gambling, legal cannabis, air travel, crypto exchanges. A student
association's event app is not on that list. Do not write "there is no exemption
path" anywhere; state it accurately.

From Apple's account-deletion support page, all verbatim:

> "Make the account deletion option easy to find in your app. Typically, it's
> included in the app's account settings."
> "Offer to delete the entire account record, along with associated personal data.
> You may include additional options, but only offering to temporarily deactivate
> or disable an account is insufficient."
> "All users should be allowed to delete their accounts, regardless of where
> they're located."
> "People expect that all data associated with their account will be deleted when
> the account is deleted. This includes user-generated content that's shared with
> others, such as photos, video, text posts, and reviews."

Two things commonly stated wrongly: **re-authentication is permitted, not
required** (*"Can I require reauthentication … **Yes.** … However, apps that make
it unnecessarily difficult for a user to delete their account will not pass
review"*), and **a delayed deletion is allowed** if you state the timeline and
confirm completion (*"Does account deletion need to be immediate and automatic?
**No.**"*). Ours is instant anyway, which makes both moot.

**Account deletion checklist:**

- [ ] Profile → Settings → **Delete Account**, destructive-styled, ≤3 taps from a
      root tab. Not a `mailto:`, not "contact us", not a web link, not
      deactivate-only.
- [ ] A consequences screen in plain Finnish and English: your QR stops working;
      you're removed from your team but the team survives and keeps its work; your
      bio and any requests or invites you sent are deleted; anonymous door and
      meal counts are kept for the association's records and are no longer linked
      to you.
- [ ] Confirm identity — password re-entry or an emailed code. Do not stack
      password *and* typed "DELETE" *and* an email code.
- [ ] Server RPC `delete_my_account()`, `SECURITY DEFINER`, taking the uid **from
      the JWT, never from the body**. `service_role` key never in the binary.

| Table | Action |
|---|---|
| `auth.users` | **hard delete** via GoTrue admin delete — this is what makes it deletion, not deactivation |
| `profiles` (name, bio, roles, challenge prefs) | **hard delete** — delete the bio, do not anonymise it; an "anonymised" bio is still the same paragraph on someone else's screen |
| `join_requests` / `invites`, sent and received | **hard delete**, including any copy of the name rendered in another user's inbox |
| `push_tokens`, notification history | hard delete — also a correctness bug if left |
| Issued QR token | **revoke first, then delete** — add the `jti` to a revocation list *before* deleting the row, or the door scanner still admits them |
| `team_members` | delete the membership, **keep the team**; transfer ownership if the deleted user owned it |
| Author attribution on shared team artefacts | replace with "Former member" |
| `checkins` / `meal_claims` | pseudonymise, keep the row — see below |
| `event_registrations` | set `status='deleted'`, null the display name |

Use `ON DELETE SET NULL` plus explicit column nulling on check-in and meal tables,
**not** `ON DELETE CASCADE`, which would destroy the counts organisers need.

**The meal-claim pseudonymisation must be done properly or the claim is false.**
Replacing `user_id` with `HMAC(registration_id, pepper)` while keeping the pepper
and the registration rows is reversible with a one-line SQL join — that is
pseudonymisation, not anonymisation, and Art. 17 erasure is therefore incomplete.
The design that actually works:

- [ ] On deletion, replace `user_id` with `HMAC-SHA256(user_id ‖ event_id,
      meal_pepper)` where `meal_pepper` is a **per-event** secret.
- [ ] **`pg_cron` destroys `meal_pepper` and purges `event_registrations` 30 days
      after the event.** Once the pepper and the registration rows are gone, no
      key maps a row back to a person and "some participant was admitted at 09:14
      and claimed lunch at 12:31" is genuinely outside the Regulation.
- [ ] The duplicate-meal check still works for the 36 hours it needs to, because
      the pepper is alive during the event.
- [ ] **Three separate secrets in the Supabase Vault**, different lifetimes: QR
      signing key, registration email pepper, per-event meal pepper. Reusing one
      for all three makes the anonymisation claim collapse again.
- [ ] **Ban-evasion record, tightly bounded.** Retain a *salted hash of the email
      only*, only for accounts banned for a moderation reason, deleted on a fixed
      date (30 November 2026), used only to refuse re-registration, and **disclosed
      in two places** — the privacy policy retention section and the delete-account
      confirmation copy the user actually reads. This runs against Apple's "delete
      all associated data" instruction, so it must be minimal, time-boxed and
      stated. It is legitimate-interest safety engineering (GDPR Art. 6(1)(f)),
      not a legal retention requirement; do not describe it as one.

**5.1.1(viii) and the Luma roster — the sharpest edge in the design.** Organisers
export a guest list from Luma and we import it. To a reviewer reading that in
Review Notes, "we import a CSV of people's names and emails from a third-party
service" is exactly the shape (viii) is written against. It is defensible, but
only built and documented a specific way:

- [ ] **Add the transfer notice to the Luma form today.** This cannot be
      retrofitted onto people who have already registered. Above the submit
      button, both languages:

      > "Ilmoittautumalla tietosi (nimi ja sähköpostiosoite) siirretään
      > STUHI-sovellukseen, jossa sinulle luodaan henkilökohtainen
      > sisäänpääsy-QR-koodi. Lue tietosuojaseloste: stuhi.org/privacy
      > By registering, your name and email address are transferred to the STUHI
      > app, where a personal admission QR code is issued to you. Privacy policy:
      > stuhi.org/privacy"

      Word it as a **notice, not a consent tickbox.** Apple's "explicit consent" is
      satisfied by the notice; the GDPR basis for the import stays Art. 6(1)(b)
      (necessary to admit the person to the event they signed up for). A tickbox
      creates a withdrawable consent you cannot honour without refusing entry.
- [ ] **The import happens on the server, never in the iOS app.** This takes
      5.1.1(viii) from "argue with a reviewer" to "not applicable to the binary",
      keeps the App Privacy label honest, and means the reviewer never sees a
      screen full of other people's names.
- [ ] **`event_registrations` stores `email_hash`, not `email`** —
      `HMAC-SHA256(lowercased_trimmed_email, pepper)`, pepper in the Vault. Exact
      matching on sign-up; the database holds no plaintext contact details for
      anyone who never installs. Keep `display_name` plaintext — door staff must
      find a person by name when their phone is dead. *(Say it accurately: a
      hashed email is pseudonymised, not anonymous. Art. 13/14 duties and the
      retention schedule still apply.)*
- [ ] **Name and email only.** Not phone, school, age, t-shirt size, dietary notes
      or free-text answers, even if the CSV contains them (5.1.1(iii)). Dietary
      data is Art. 9 special-category data — keep it out of the app entirely.
- [ ] **Never pre-create browsable profiles from the CSV.** A roster row becomes a
      visible profile only after that person signs up themselves and accepts the
      terms. Pre-created records are also "automatically generated accounts" under
      Apple's FAQ and would need their own deletion path.
- [ ] **Never enrich, never join a second list, never build a social graph from
      it.** No "12 of your co-registrants are here", no "invite the rest of your
      school". That is exactly the 5.1.2(iii)/(iv)/(v) behaviour (viii) exists to
      stop.
- [ ] **`pg_cron` purges unmatched rows 14 days after the event.**
- [ ] **Say all of it in the privacy policy and in Review Notes.**

**One more from the deletion FAQ that lands directly on us:** *"If my app links
out to the default web browser for account creation … note that linking out to the
default web browser to sign in or register an account provides a poor user
experience and is not appropriate, per App Store Review Guideline 4."* So: **no
"Sign up on Luma" button that opens Safari as the app's registration path.**
In-app sign-up must be a complete, first-class native flow. Linking to Luma as
*event registration* — a separate act — is fine.

**Other 5.1.1 items:**

- [ ] **Privacy policy live at `stuhi.org/privacy`, fi + en, linked in App Store
      Connect metadata AND in-app, reachable pre-authentication** — the first
      moment a 15-year-old hands over data is the sign-up form.
- [ ] If presented in `SFSafariViewController`, it must be **visible and
      unobscured** (5.1.1(vii)). No zero-height instance, no overlay.
- [ ] **Camera prompt only for staff, only in the scanner, after a screen
      explaining why.** A member must be able to install, sign up, get their QR,
      browse challenges, join a team and attend the whole event **without the
      camera permission ever being requested once** (5.1.1(iii)).
- [ ] **`NSCameraUsageDescription`, localised.** en: *"STUHI uses the camera only
      to read attendees' QR codes at the door and at meal service. No photos or
      video are taken, saved, or uploaded."* fi: *"STUHI käyttää kameraa vain
      osallistujien QR-koodien lukemiseen sisäänkäynnillä ja ruokailussa. Sovellus
      ei ota, tallenna eikä lähetä kuvia tai videota."* Verify it renders Finnish
      on a Finnish-locale device — if `project.yml` sets it via
      `INFOPLIST_KEY_…`, the `.lproj` files only win when they are actually in the
      target's resources.
- [ ] **Do NOT add**: `NSPhotoLibraryUsageDescription`,
      `NSMicrophoneUsageDescription` (an `AVCaptureSession` with only a video
      input and an `AVCaptureMetadataOutput` never needs it — if this prompt
      appears, the session setup is wrong), `NSLocationWhenInUseUsageDescription`,
      `NSContactsUsageDescription`, `NSUserTrackingUsageDescription`. A purpose
      string with no matching functionality is itself a flag.
- [ ] **Camera-denied fallback**: manual entry of the short code printed under the
      QR, plus an "Open Settings" button (5.1.1(iv)).
- [ ] **Bio, roles, display name all optional and skippable** (5.1.1(x)). No
      "write your bio to continue" wall.
- [ ] **Separate unticked consent for publishing the profile**, withdrawable via a
      "Hide my profile" toggle in Settings (5.1.1(ii), GDPR Art. 7(3)).
- [ ] **"I am at least 13" checkbox** at sign-up. Finland's Tietosuojalaki
      (1050/2018) § 5 sets the digital-consent age at 13. **Do not collect a
      birthdate** — 5.1.4(a) permits birthdate collection *"only for the purpose of
      complying with these statutes"*, and a boolean complies.
- [ ] **Session token in the Keychain**, not `UserDefaults`. A refresh token in a
      plist inside the app container is an Art. 32 weakness on a phone lost by a
      16-year-old.
- [ ] **RLS on every table, default deny.** A member reads only their own
      `profiles` row plus the public projection of others (name, bio, roles —
      **never email**). Only a monk reads `event_registrations` or writes
      `checkins`. Test with the demo accounts before submitting, the way the
      finance demo account was verified against the live server.
- [ ] **`PrivacyInfo.xcprivacy`** declaring six collected types — Email Address,
      Name, User ID, Device ID (the APNs token: Apple's own definition is *"the
      device's advertising identifier, **or other device-level ID**"*), Other User
      Content, Other Data Types — all Linked, all Tracking false, all purpose
      `AppFunctionality`; plus `NSPrivacyAccessedAPICategoryUserDefaults` with
      reason **`CA92.1`** (`@AppStorage` *is* `UserDefaults`; there is no version
      of this app that avoids the declaration). **Rebuild the data types from
      scratch — do not copy Finance's**, which declare financial info and receipt
      photos. If a widget or notification-service extension ever shares state
      through an App Group, the reason becomes `1C8F.1` and each extension bundle
      needs its own manifest.
- [ ] **Verify the manifest actually lands in the `.app`**, not just the repo —
      the classic failure. Fold this into `upload.sh` next to the signature check:

      ```sh
      unzip -q build/export/StuhiApp.ipa -d /tmp/ipa
      ls /tmp/ipa/Payload/StuhiApp.app/PrivacyInfo.xcprivacy   # must exist
      codesign -dvv /tmp/ipa/Payload/StuhiApp.app 2>&1 | grep Authority
      # must say: Apple Distribution: Nuorten startup- ja innovaatioyhdistys ry
      ```
- [ ] **Generate the privacy report** before the first upload — Product → Archive
      → control-click in Organizer → Generate Privacy Report — and reconcile it
      against the App Privacy questionnaire. It is what catches a dependency
      quietly declaring `Analytics`.

### 10. Guideline 5.1.2 — Data Use and Sharing

> "**(i)** Unless otherwise permitted by law, you may not use, transmit, or share
> someone's personal data without first obtaining their permission. You must
> provide access to information about how and where the data will be used. **You
> must clearly disclose where personal data will be shared with third parties,
> including with third-party AI, and obtain explicit permission before doing so.**
> … Your app may not require users to enable system functionalities (e.g. push
> notifications, location services, tracking) in order to access functionality,
> content, use the app, or receive monetary or other compensation …"

> "**(ii)** Data collected for one purpose may not be repurposed without further
> consent unless otherwise explicitly permitted by law."

> "**(iii)** Apps should not attempt to surreptitiously build a user profile based
> on collected data and may not attempt, facilitate, or encourage others to
> identify anonymous users or reconstruct user profiles …"

> "**(iv)** Do not use information from Contacts, Photos, or other APIs that access
> user data to build a contact database for your own use or for sale/distribution
> to third parties …"

The **"including with third-party AI"** clause is recent and directly relevant,
because STUHI's sibling projects routinely reach for Groq.

- [ ] **No hosted LLM touches attendee text in v1.** Not the bio filter, not the
      auto-assign matcher, not a "summarise the challenges" feature. Wordlists and
      regexes on our own server. AI moderation later needs its own consent gate
      and a privacy-policy update.
- [ ] **No analytics, no ad SDK, no Firebase, no Sentry, no Crashlytics.** This is
      what makes the privacy label clean.
- [ ] **Processors disclosed**: Supabase (Art. 28 processor, EU region, DPA
      signed, sub-processor list recorded — **keep it EU**, no US-region add-ons),
      Apple/APNs (device token and payload), Luma (registration form).
- [ ] **Check and document Supabase's request-log/IP retention window** and either
      state it in the privacy policy under security/abuse-prevention logging (Art.
      6(1)(f)) or confirm IPs are discarded. This is collection nobody has written
      a rule for.
- [ ] **No "invite your friends" feature, ever** (5.1.2(v)).
- [ ] Push not required for any functionality — covered in §7 above, and 5.1.2(i)
      is the stronger of the two rules.

---

## What must exist in the binary before first submission

Grouped by the guideline that forces it. Nothing here is optional.

**Accounts and access**

- [ ] Guest mode: schedule, challenges, About STUHI, venue, contact, code of
      conduct, terms and privacy links — all usable with no account.
- [ ] Role chooser moved out of cold launch and into the sign-in flow. Cold-launch
      lands on Schedule.
- [ ] Native in-app sign-up, any email, no code, no allowlist, no waiting.
- [ ] Unticked terms + privacy checkbox, and an unticked "I am at least 13"
      checkbox, both gating the Continue button.
- [ ] Separate unticked consent for publishing the profile.
- [ ] Settings → Account → **Delete Account**, ≤3 taps, with the consequences
      screen and identity confirmation.
- [ ] `is_monk` server-side flag; monk feed enforced in RLS.
- [ ] Verified-attendee gate on team-matching surfaces. **The QR and the schedule
      stay outside that gate and outside the social surface.**

**UGC safety**

- [ ] Client-side filter + Postgres trigger, EN + FI, normalising, contact-info
      stripping, length caps.
- [ ] Report on every profile, team and incoming request. `reports` table with
      `reporter_id` and `content_ref`. Webhook to `moderation@stuhi.org`.
- [ ] Block on every surface Report is on. `blocks` table, symmetric server-side
      exclusion, request-blocking, 20-block cap, Settings → Blocked People.
- [ ] Self-removal: clear own bio, edit/delete own team description, withdraw a
      sent request.
- [ ] `visible` flags and `banned_at`.
- [ ] Settings → About → Contact STUHI with both addresses and the association's
      registered details.
- [ ] Terms and Privacy links reachable **before** sign-in and from Settings.

**Event mechanics**

- [ ] QR signing **server-side only** — HMAC-SHA256 or Ed25519 in an Edge
      Function, secret in the Vault. The app receives an opaque signed token and
      never holds the key. Ship the key in the binary and a competent 17-year-old
      extracts it in an afternoon.
- [ ] Short-lived rotating tokens: `{user_id, event_id, exp, nonce}`, rotating
      every 30–60 seconds or single-use per scan type. A static QR is
      screenshot-and-forward.
- [ ] Separate scopes for door vs meal; the scanner declares which action it is
      performing and the server enforces one admission, one claim per serving.
- [ ] **QR verifies offline.** Cache it so it renders with no network.
- [ ] Scanner: styled denied/empty states, **manual code entry**, demo-QR
      affordance for the staff account.
- [ ] `events` concept in the data model and the UI.
- [ ] Server-driven schedule, challenges, announcements, meal windows, team
      assignments, and a **subtractive** kill-switch.

**Plumbing**

- [ ] `PrivacyInfo.xcprivacy` in the app target, verified present in the exported
      `.app`.
- [ ] Keychain for the session token.
- [ ] `ITSAppUsesNonExemptEncryption: NO`.
- [ ] **No** `NSAppTransportSecurity` exception of any kind. Hosted Supabase is
      TLS; this is one place we are genuinely safer than Finance.
- [ ] `UIBackgroundModes` → `remote-notification` **only if** we actually send
      silent pushes. 2.5.4 says background services may only be used *"for their
      intended purposes"*; declaring an unused mode invites a question.
- [ ] `TARGETED_DEVICE_FAMILY = 1` (iPhone only).
- [ ] Launch screen exists.
- [ ] English and Finnish localisation, defaulting to English off a Finnish
      device.
- [ ] `pg_cron` jobs written and scheduled: unmatched registrations at 14 days;
      meal pepper and registration purge at 30 days; bios/roles at 90 days; push
      tokens on sign-out, on delete, on the first APNs `Unregistered`, and a
      12-month hard cap; accounts after 24 months of inactivity with a warning at
      23. **A retention policy written in a document and not in the database is a
      retention policy that will not happen on 24 November.**

---

## What must exist in App Store Connect before first submission

- [ ] **App record** created under team `Q485H7YK66` against bundle id
      `org.stuhi.app`.
- [ ] **SKU** — any internal string, never shown. `stuhi-app-001`.
- [ ] **Primary Language** English (U.S.), with Finnish as a secondary
      localisation. *A `fi` localisation is not free — Description, Keywords,
      Support URL and Screenshots are each required and localisable. App Store
      Connect normally copies the default screenshots into a new localisation, but
      that is observed behaviour, not documented; add the `fi` localisation first
      and check the slots before assuming.*
- [ ] **App Name** `STUHI: Student Innovation` (25/30) · fi `STUHI: Nuorten
      yrittäjyys` (25/30).
- [ ] **Subtitle** `Startup community & events` (26/30) · fi `Startup-yhteisö ja
      tapahtumat` (29 chars / **30 bytes** — zero headroom, keep one character in
      reserve).
- [ ] **Keywords, 100 BYTES not characters, each keyword > 2 characters**:
      `hackathon,entrepreneur,team,match,challenge,schedule,agenda,pass,event,youth,tampere,finland,lukio`
      (97/100). fi:
      `hackathon,tiimi,haaste,aikataulu,opiskelija,lukiolainen,innovaatio,verkosto,tampere,suomi,kilpailu`
      (98/100). `ä`/`ö` are two bytes each. Do not use `qr` — two characters,
      fails the rule. `lukio` is the highest-value term in the set.
- [ ] **Promotional text** (170 max, editable without a build):
      `STUHI × TAMPERE runs 24–25 October at Hervanta Campus, Tampere. Your pass,
      the challenge briefs, the schedule and team matching are all in the app.`
      (147). Use `×` or lowercase `x`, **not a bare capital X** — 2.3.7 says
      metadata should not *"reference other apps"*, and X is a social network Apple
      itself names in 5.1.1(v). Free to remove the ambiguity.
- [ ] **Description** (4000 max, ~2500 used): association first, then how the app
      works, then a SAFETY paragraph (naming the pre-publication filter, report,
      block and the contact address — *"Bios and team descriptions are checked
      against a blocklist before they appear, and are reviewed by the STUHI
      team"*, not a vague "they are moderated"), a PRIVACY paragraph (in-app
      account deletion, no tracking, no ads), a CORE TEAM paragraph, and the
      not-affiliated-with-any-university line.
- [ ] **Copyright** `2026 Nuorten startup- ja innovaatioyhdistys ry`, no `©`.
- [ ] **What's New** — not required for 1.0. From 1.1 onward, 2.3.12 applies.
- [ ] **Categories** Education primary, Social Networking secondary. **Made for
      Kids: unchecked.**
- [ ] **Content Rights** declared for partner-authored challenge briefs.
- [ ] **Privacy Policy URL** `https://stuhi.org/privacy` — required, app-level,
      live before submission.
- [ ] **Support URL** `https://stuhi.org/support` — required, and per Apple's own
      field text it *"must lead to actual contact information (**legal address,
      email address, telephone number**)"*. **The phone number is the bit everyone
      forgets.** Page contents: legal name plus PRH register number, registered
      address, telephone, `support@stuhi.org` and `moderation@stuhi.org`, how to
      report content, how to block, how to delete your account, and a stated
      response-time commitment. Designate it explicitly as the point of contact for
      DSA Arts. 11 and 12, naming the languages accepted — one paragraph, closes
      both articles.
- [ ] **Marketing URL** — leave blank. A marketing URL pointing at a hackathon
      landing page actively undermines the positioning the whole name strategy
      exists to protect.
- [ ] **Custom License Agreement** selected and pasted (see §1).
- [ ] **App Privacy questionnaire** answered to match `PrivacyInfo.xcprivacy`
      exactly. Yes to collection; Contact Info → Name and Email Address; User
      Content → Other User Content; Identifiers → User ID and Device ID; Other Data
      → Other Data Types. Everything else No. **"Data Used to Track You" must be
      empty.** A mismatch is a rejection.
- [ ] **Age rating questionnaire** — see below.
- [ ] **Pricing and Availability: Free, territories restricted to Finland** (or
      the EEA). See Age rating for why this is not optional.
- [ ] **Scheduled or manual release**, so the listing goes live when STUHI is
      ready rather than the instant approval lands. Apple explicitly recommends
      this for event apps.
- [ ] **EU DSA trader status.** Account level: Business → Agreements → Digital
      Services Act → Complete Compliance Requirements. Plus the per-app
      declaration under App Information → App Store Regulations and Permits. Since
      17 February 2025, *"apps without trader status have been removed from the App
      Store in the European Union (EU) until trader status is provided and
      verified by Apple"*, and *"Even if you don't distribute apps in the EU,
      you'll still need to declare a trader status."* Finland is the entire market,
      so without this there is no launch. It is **probably already done** at
      account level, since `Q485H7YK66` has a live record for STUHI Finance — so
      treat it as a five-minute verification, not a lead-time blocker. Two things
      to settle anyway: whether a registered `ry` declares as a trader (a legal
      judgement for the board, not for us — the hobbyist carve-out in Apple's text
      was written for individual enrolments), and **which phone number and email get
      published on the EU product page**. The address auto-populates from the
      D-U-N-S number, so nobody's home address can leak by accident. Do not use a
      board member's mobile. Re-check the details annually as the board turns over.
- [ ] **App Review Information**: contact name, email and phone for someone who
      will answer during the review window.
- [ ] **Sign-In Information**: the member demo account. The others go in Notes.
- [ ] **Notes for Review** — see below. Not optional courtesy: 2.3.1(a) says
      generic descriptions will be rejected.

**Optional and worth knowing about, but not for v1's first submission:**

- **In-App Events** are the correct home for STUHI X TAMPERE — a first-class
  product-page object for *"timely events within apps"*, discoverable in search,
  with a 14-day pre-promotion window, **reviewed independently of the app
  version**. Up to 15 approved events, 10 published at once, 31 days max duration.
  Needs a 16:9 event card image and a 9:16 detail image. **Submit by 10 October**
  to use the pre-promotion window.
- **A Custom Product Page** is the clean answer to "where does the hackathon pitch
  go?" — its own URL, its own screenshots and promotional text, all
  hackathon-framed, for the Luma confirmation email, posters and school QR codes,
  while the default product page stays evergreen for App Review and organic
  search.
- **Skip Product Page Optimization.** At 500 users it will never reach
  significance.
- **Skip App Previews** for v1.

---

## Demo accounts for App Review

Apple's Before You Submit list, verbatim:

> "Provide App Review with full access to your app. If your app includes
> account-based features, provide either an active demo account or fully-featured
> demo mode, plus any other hardware or resources that might be needed to review
> your app (e.g. login credentials or **a sample QR code**)."

Three accounts. App Store Connect's Sign-In Information holds one username/password
pair, so the member account goes there and the other two go in Notes, clearly
labelled.

| Account | Role | Pre-seeded with |
|---|---|---|
| `reviewer@stuhi.org` | member / attendee | present in the demo event's roster so **a QR token already exists**; a filled-in bio; membership of one team; **one pending join request and one pending invite** so both directions are demonstrable without a second human; some notification history |
| `reviewer.monk@stuhi.org` | monk + staff scanner | all of the above, plus 5–10 realistic internal feed posts and scanner access |
| `reviewer.delete@stuhi.org` | throwaway member | exists solely so the reviewer can exercise account deletion without destroying the demo data |

The third is not padding. **Reviewers do test deletion**, and losing
`reviewer@stuhi.org` mid-review means the next resubmission arrives with no
working demo account.

- [ ] **No "become a monk" toggle in the shipping binary.** Self-elevation
      destroys the 3.2.2(v) argument that monk access is organisation-granted, and
      any curious user finds it.
- [ ] **Seed ~8 fictional attendees and 3 teams — fictional, never real STUHI
      members.** GDPR, and real 16-year-olds' bios must not sit in a review
      artefact.
- [ ] **The seeded attendees must be real rows in the database**, so Report
      actually inserts and returns its confirmation, and Block actually removes
      them from the browse list in front of the reviewer. **A Report button that
      no-ops against a static fixture reads as a stub and fails 2.1(a) and 1.2 in
      the same pass.**
- [ ] **Walk the whole flow yourself, signed in as `reviewer@stuhi.org`, against
      the live backend, before submitting** — the way the finance demo account was
      verified.
- [ ] **Make the seed idempotent and re-runnable**, or reset demo state on a
      schedule, so a second reviewer on a resubmission does not find an empty,
      half-blocked event.
- [ ] Passwords never in the repo — printed once by a create-script, then App
      Store Connect and a password manager. Extend `backend/create-demo-account.sh`
      from the finance repo.

### Review Notes

Specific, not generic. This is the highest-return artefact in the whole
submission, because 1.2 apps get rejected when reviewers **cannot find** the
mechanisms, not because they are absent.

> STUHI is the community app of Nuorten startup- ja innovaatioyhdistys ry, a
> registered Finnish non-profit student entrepreneurship association (PRH register
> number [X]). The app serves the association year-round; the STUHI X TAMPERE
> hackathon (24–25 October 2026) is the current event inside it. STUHI provides
> all content in this app; it is not built from a template or app-generation
> service.
>
> No account is needed to browse the Schedule and Challenges — the app opens
> straight into them.
>
> **Guideline 1.2 — where each mechanism is.** Sign in as reviewer@stuhi.org, then:
> 1. **EULA with a no-tolerance clause** — required at sign-up, and always at
>    Settings → Terms of Use. The no-tolerance clause is section 3.
> 2. **Filtering** — Profile → Edit Bio. Objectionable terms, and any email
>    address, phone number or social handle, are rejected on submit with an
>    explanation. The same check runs again on the server.
> 3. **Reporting** — Teams → any team → any member → the ⋯ menu at top right →
>    Report. Also on every team and every incoming join request. Reports are
>    emailed to a STUHI organiser on rota; our commitment is to act within 24
>    hours.
> 4. **Blocking** — the same ⋯ menu → Block. A blocked person cannot see you,
>    cannot appear in your lists, and cannot send you a request. Manage at
>    Settings → Blocked People.
> 5. **Published contact information** — Settings → About → Contact STUHI:
>    moderation@stuhi.org and support@stuhi.org, plus the association's registered
>    name, address and telephone number. Also at https://stuhi.org/support.
> 6. **Removing your own content** — Profile → Edit Bio → Clear, and Team → Edit →
>    Delete. Both take effect immediately.
>
> **Account deletion (5.1.1(v))** — Profile → Settings → Delete Account. Please use
> reviewer.delete@stuhi.org so the main demo account stays available. Deletion is
> immediate and permanent and removes the account, the profile, the bio and any
> requests or invitations the user sent, including copies visible to others.
> Attendance and meal records are retained in pseudonymised form for up to 30 days
> so catering totals stay correct, then irreversibly destroyed. No email or phone
> call is required.
>
> **Team matching** — attendees pick roles from a fixed list and write an optional
> short bio. Teams state a missing role; people request to join and teams invite.
> It is a directed request-and-accept flow. There is no swipe interface, no rating
> or ranking of people, no user-uploaded photos, no in-app messaging, and no
> romantic or dating intent. Access to other attendees' profiles requires a
> confirmed event registration; this demo account is registered for a demo event
> containing fictional attendees only.
>
> **STUHI team ("monk") experience** — sign in as reviewer.monk@stuhi.org /
> [password]. Same as above plus a fifth tab, "STUHI", containing a feed of
> association updates (equipment, spaces, announcements) and a QR scanner under
> "Scan". That feed is authored by the organisation: it is not user-generated
> content, not messaging, and not a social feed. Monk access is a server-side flag
> granted by the association to its own volunteers; it is not self-service and it
> does not restrict anyone from using the app.
>
> **Testing the scanner on one device** — tap "Enter code manually" in the Scan
> screen and enter `DEMO-7K42-QX19` to see a successful door check-in, then the
> same code again to see the duplicate-scan result. A scannable sample QR is also
> at https://stuhi.org/app/sample-qr.
>
> **Event roster** — attendees register on a public web form that tells them at the
> point of registration that their name and email are transferred to STUHI and used
> to verify them in this app. Organisers import that list through a web
> administration tool on our server; the iOS app does not import or contain any
> list of people, and never displays personal information about anyone who has not
> created their own account. We obtain personal data from no other source.
>
> **Push notifications** are operational only (meal service, schedule changes, team
> placement). They are optional, the app is fully usable with notifications
> declined, everything pushed is also visible in-app, and notification bodies never
> contain user-written text.
>
> **Camera** — used only by event staff to read QR codes. No photo or video is
> captured, stored or transmitted. Members never see a camera prompt.
>
> **Minors** — the app is rated 13+ and users confirm at sign-up that they are at
> least 13, in line with Finland's Data Protection Act (1050/2018 § 5). The app is
> not in the Kids Category and does not target children.

---

## Screenshots: sizes and shot list

Upload **6.9-inch iPhone only**. App Store Connect Help is explicit: 6.5" is
*"Required if app runs on iPhone and screenshots for 6.9″ display aren't
provided"*, and *"If screenshots with the accepted sizes aren't provided, scaled
screenshots for 6.9″ displays are used."* Supply the largest and Apple scales the
rest.

| Class | Portrait | Landscape |
|---|---|---|
| **6.9"** (17 Pro Max, 16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus, 14 Pro Max, iPhone Air) | **1320 × 2868**, **1290 × 2796**, or **1260 × 2736** | 2868 × 1320 / 2796 × 1290 / 2736 × 1260 |
| 6.5" (only if 6.9" is omitted) | 1284 × 2778 or 1242 × 2688 | — |
| 13" iPad | 2064 × 2752 or 2048 × 2732 | **not needed — `TARGETED_DEVICE_FAMILY = 1`** |

Rules: **1 to 10 per size**; `.png`, `.jpg` or `.jpeg`; **no alpha channel or
transparency** (a PNG with alpha is rejected at upload); captured at the
simulator's native resolution, never resampled; **built against the iOS 26 SDK**
so the Liquid Glass chrome matches what ships.

**The first 1–3 images appear in search results** when there is no app preview, so
treat shots 1–3 as the search set. Apple also recommends including at least one
Dark Mode screenshot — free, and it demonstrates the app handles both appearances.

**The app icon is not a listing upload.** For iOS it is read out of the build —
the asset catalog's App Icon set, or an Icon Composer `.icon` file under Xcode 26.
1024 × 1024, PNG, no alpha, no pre-baked rounded corners, enforced at validation
against the binary. One Xcode 26 gotcha: an Icon Composer `.icon` and an
asset-catalog app icon in Copy Bundle Resources conflict, with the asset catalog
silently winning. Pick one.

**Shot list, eight:**

1. **My Pass** — the personal admission QR, rendered. This is the app's identity.
2. **Challenges list** — real briefs, real titles.
3. **Team detail** with the Request to join button — the shot that visibly proves
   "directed request-and-accept, no swiping" to anyone scanning search results.
4. **Schedule** — the agenda in use.
5. **Scanner in use** with a successful check-in result. Strongest 4.2 evidence,
   but not slide 1: staff tooling as slide 1 invites "who is this app for?"
6. **Monk internal feed** — association updates, invented content.
7. **In-app notifications inbox** — as *in-app content*, never a mocked-up iOS
   banner. Fake system UI in a screenshot depicts something the app does not
   render, which is a 2.3 accuracy problem.
8. **Settings** showing **Delete Account** and, in the same frame, Report/Block
   reachable. The highest-leverage defensive shot in the set — it puts 5.1.1(v)
   and three of 1.2's four bullets in front of the reviewer before they go
   hunting. **Do not cut it if you trim to six.**

Optional ninth: **Challenge detail** with a full brief — the strongest single
piece of 4.2 "adequate utility" evidence we have.

**Never**: the role chooser, the sign-in screen, a splash screen (2.3.3); any real
person's name, face, email or bio (2.3.9); a QR that resolves to anything live;
prices, "free", "download now"; anything implying the audience is children
(5.1.4).

---

## Age rating: the answers

The bands changed. **12+ and 17+ no longer exist**; the system is **4+, 9+, 13+,
16+, 18+**. A brand-new record answers the new questionnaire from the start, and
from **September 2026 the social-media-capability questions are required for new
submissions** — which is exactly our window.

> "**2.3.6** Answer the age rating questions in App Store Connect honestly so that
> your app aligns properly with parental controls."

**Do not pick a rating. Answer honestly, then use the "set a higher rating"
control**, which exists precisely for this: *"If your app has a policy requiring a
higher minimum user age than the rating assigned by Apple, you can set a higher
age rating after you respond to the age ratings questions."* Our published terms
set 13 (Tietosuojalaki § 5), so the manual 13+ matches a real policy — the exact
condition Apple's wording requires.

| Question | Answer | Why |
|---|---|---|
| **User-Generated Content** | **Yes** | Bios and team text. Apple's minimum for this is **4+** — it does not raise the rating by itself. |
| **Social Media** | **Yes** | Confidence medium. Read strictly, there is no feed, no reposting, liking, commenting or reacting, and no search over bios — an honest "no" is arguable. But bios *are* surfaced to many users through a discovery tool, and mis-rating is the worse risk. Minimum **13+**. |
| **Social Media Disabled for Users Under 13** | **No** | It requires the Declared Age Range API (iOS 26+, our target is 17), and it is *itself* rated 13+ minimum, so it would buy nothing even if reachable. |
| **Messaging and Chat** | **No** | Ship requests and invites button-only, no free text. *(Note: adding messaging would NOT raise the rating — Messaging and Chat is 4+. Do not argue against messaging on age-rating grounds; that argument is false and using it undermines the real ones.)* |
| **Contests** | **No, conditionally** | Apple's definition covers *"events that allow users to compete … for rankings, rewards"* — the event, not just the binary. Answer No **only if** the shipped build has no prize amounts or sponsor rewards in the briefs, no leaderboard or standings anywhere, no in-app entry submission and no winner announcement. Otherwise Yes. Contests is not a mature descriptor and Yes does not push above 13+, so **if in any doubt, answer Yes.** |
| **Unrestricted Web Access** | **No** | Would force **16+**, which for 15-year-old *lukiolaiset* is actively harmful. Open external links in Safari; any in-app web view stays on known STUHI URLs. |
| **Parental Controls** | No | |
| **Age Assurance** | **No** | A self-declared checkbox is not age assurance in Apple's sense (that means the Declared Age Range API, age estimation, or government ID). Do not claim it. |
| **Advertising** | No | |
| All Mature Themes, Medical/Wellness, Sexuality/Nudity, Violence, Gambling, Simulated Gambling, Loot Boxes | **None / No** | The meal-claim counter is not a wellness topic. |
| **Made for Kids** | **Unchecked** | |
| **Final rating** | **13+, set manually** | Rating, description, terms and privacy policy must all say 13. Do not go to 16+ — it excludes part of a 15–19 audience and contradicts our own stated minimum. |

**Restrict availability to Finland (or the EEA). This is the one that could stop
us, and it is a two-minute change.** Australia's under-16 social media law has
been in force since **10 December 2025**: social media apps must prevent users
under 16 from creating accounts and deactivate existing under-16 accounts, with
the Declared Age Range API as Apple's named mechanism. We are about to answer
**Social Media = Yes** on an app with **open public sign-up and a 13+ minimum**
and **no age-assurance mechanism**. Separately, US state law now imposes a
*statutory duty on developers* to check age via the same API — Texas SB 2420 live
since **4 June 2026**, Utah since 6 May, Louisiana since 1 July — and App Store
availability is set per country, so Texas cannot be excluded without excluding the
United States. Restricting to Finland closes Australia, Texas, Utah, Louisiana,
Brazil, Singapore and COPPA in one setting. Nothing about this app serves anyone
outside Finland.

**Set territories at record creation.** Availability is far easier to widen later
than to explain retroactively. Worldwide availability would require adopting
`DeclaredAgeRange` (iOS 26 runtime against an iOS 17 target, so a manual fallback
anyway), `PermissionKit`'s significant-change consent flow, `RESCIND_CONSENT`
server notifications, the `com.apple.developer.declared-age-range` entitlement, a
provisioning round trip, and a build against the iOS 26.2 SDK. That is not a
63-day item.

Two footnotes. **App Review does not police age assurance** — Apple's Q&A:
*"Are there any changes to the App Review process related to my app's age assurance
obligations? **No.**"* So this is a legal-exposure decision, not a review-cycle
one. And **a later age-rating change is itself a "significant change"** requiring
re-consent in those jurisdictions, so get it right the first time rather than
raising it in v1.1.

**Time Allowances: not a risk for this event.** Declaring Social Media puts the
app in the Social Media Time Allowance category — but Time Allowances are an **iOS
27** feature, and attendees will be on iOS 26.x in October 2026. Nobody can be
locked out of their pass by a parental screen-time limit at this hackathon. It
becomes real for the 2027 event. The mitigations are worth doing anyway for
ordinary reasons: **cache the pass so it renders offline**, keep the QR and the
schedule on their own tabs outside the social surface, and have a laptop at the
door that can check someone in by name. 500 people in a concrete university
building will not all have signal.

---

## Dated submission timeline working back from 24 Oct 2026

Slack sized for **two** rejection cycles.

| Date | Milestone | Why this date |
|---|---|---|
| **★ TODAY 22 Aug** | **Claim App ID `org.stuhi.app` under `Q485H7YK66`.** Verify `project.yml` sets `DEVELOPMENT_TEAM: Q485H7YK66` **before any build runs on any device.** | Irreversible if it goes wrong, free to prevent today. `org.stuhi.finance` was lost exactly this way. |
| **★ TODAY 22 Aug** | **Add the transfer notice to the Luma registration form.** | 5.1.1(viii). Cannot be applied retroactively — every day of delay is a cohort registered without the notice. |
| **★ TODAY 22 Aug** | **Verify EU DSA trader status** at account level and settle who the published phone and email are. | Probably already declared, but it is a hard gate on EU distribution with a human in the loop, and Finland is the entire market. |
| **22 Aug** | **Decide the territory question**: Finland/EEA only. Set it when the record is created. | Australia's under-16 law plus three US states. |
| **23–24 Aug** | Create the App Store Connect record. Create the **APNs `.p8`** and enable Push on the App ID. Back it up alongside `~/.stuhi-signing/` and `~/.appstoreconnect/`. | Capabilities must be on the App ID before the first distribution build. |
| **26–29 Aug** | **Prove the pipeline end to end with a throwaway build.** Archive → export → `codesign -dvv` says `Apple Distribution: Nuorten startup- ja innovaatioyhdistys ry` → upload → TestFlight → installs → **a test push arrives via `api.push.apple.com`**. Fill in Test Information and the beta description, create the external group and public link, let the first build clear Beta App Review. | Highest-value week on the calendar. Every signing, provisioning and APNs surprise surfaces with 56 days of runway, and it stands up the fallback while it is cheap. |
| **1–5 Sept** | Terms, privacy policy and support page **live in fi + en** and tested from outside Finland. `PrivacyInfo.xcprivacy` written. Supabase DPA signed and log/IP retention checked. Two-page DPIA at `docs/DPIA.md`. | Hard blockers, trivially forgettable. A 404 is a 2.1 rejection. |
| **8–12 Sept** | **Feature complete.** Priority order: in-app account deletion; the 1.2 four; the notification settings screen; guest mode; verified-attendee gate; rate limits. | Everything after this is content, polish and defects. |
| **★ 12 Sept** | **Content lock.** Real challenges, real schedule, real monk posts, seeded demo event with fictional attendees. **Three demo accounts created and walked end to end against the live backend from an outside network, including a real Report and a real Block.** | 2.1 is over 40% of unresolved issues. Whoever owns content must be told 12 September is their lock date too. |
| **13–14 Sept** | Screenshots (8, 6.9" only, no alpha, one dark). All metadata. Age-rating questionnaire including the social-media questions. App Privacy answers reconciled against the manifest and the privacy report. Full pass of the push-denied checklist on a real device. Review Notes finalised. | |
| **★ 15 Sept** | **SUBMIT v1.0.** 39 days out. | The load-bearing date of the whole plan. Every day later is slack spent. |
| **16–18 Sept** | Expect a decision. Apple: *"On average, 90% of submissions are reviewed in less than 24 hours."* Assume slower for a new bundle id with UGC and minors. | |
| **19–25 Sept** | **Rejection cycle #1 budget.** Fix and resubmit within 72 hours. If the rejection is arguable rather than factual, **reply on the App Review page in App Store Connect first** — rebuilding to satisfy a misreading makes the app worse. An **appeal to the App Review Board is a separate, escalated mechanism**: *"Submit only one appeal per submission that didn't pass review. Respond to any requests for additional information before submitting an appeal."* You get one. Do not spend it on a first reply. | |
| **25 Sept – 1 Oct** | **Rejection cycle #2 budget.** | |
| **★ 1 Oct** | **HARD GATE: live and publicly installable.** If not: reply on the App Review page and request a 30-minute App Review appointment; file an expedited request; **activate the TestFlight public link as the event channel** and keep pushing the listing in parallel. | 23 days of margin. Still looping here means the problem is structural. |
| **5 Oct** | App Store link into Luma confirmation emails, stuhi.org, posters, school outreach. **Upload the TestFlight fallback build this week** so its 90-day clock expires in January. | Attendees need weeks, not days. Install problems should surface in October, not at the door. |
| **10 Oct** | **Feature freeze**, defect fixes only. **Submit the In-App Event** to use its 14-day pre-promotion window. | |
| **13–15 Oct** | **Full-scale dress rehearsal.** Import a synthetic 500-row CSV, issue 500 tokens, scan at a realistic rate, run a broadcast push **to a TestFlight build on the production APNs host**, run auto-assign against 500 synthetic bios. On Hervanta wifi if possible. | The import → issuance → scan path cannot fail and has never been run at scale. Do it before the last-submission gate so a discovered bug can still ship. |
| **★ 17 Oct** | **Last routine binary submission.** Bug fixes only, normal review assumed. | 7 days for one full cycle plus propagation to users. |
| **20 Oct** | Last-resort **expedited review** window. **We qualify on Apple's own wording**: *"Event-related app. … if your app is still in review and the launch of your event is quickly approaching, you can request to have your app review expedited. Make sure your request includes the event, date of the event, and your app's association with the event."* Have the event name, dates and venue written out in advance. Reserve it for a genuine defect — expedites are limited goodwill. | |
| **22 Oct** | **Absolute code freeze.** Server-side content only. Real CSV imported, tokens issued, every attendee has had the install link for 17 days. | |
| **24–25 Oct** | **Event.** Nobody submits anything to Apple. Someone technical on call all weekend with database access. Every runtime change is a Supabase write. | |
| **~10 Nov** | **Ship v1.1** — post-event content, results, the association's ordinary year, next-event placeholder. | Makes the "not a one-off event app" positioning *true in the public record* rather than merely asserted at review time. Do not skip it because the event is over. |
| **30 Nov** | Banned-hash set deleted (the fixed date we published). | |
| **Ongoing** | An update every 6 months minimum. Test on the iOS beta each **August**, ship a compatibility build each September. Re-check DSA trader details annually. | Removal for staleness needs **both** three years without an update **and** near-zero downloads — weak. But *"apps that crash on launch will be removed immediately from the App Store"* is unconditional, and that is the real removal risk. |

**Slack analysis.** 15 Sept → 24 Oct is 39 days. Two full cycles at ~7 days each
consumes to 1 Oct, leaving 23 days of true margin covering install adoption and one
late defect fix. **Submit on 1 October instead and you have room for exactly one
rejection and zero adoption runway.** That is the failure mode to guard against,
and it is a project-management failure, not a compliance one.

**Most likely to actually cost a cycle, ranked:**

1. **2.1 placeholder or incomplete content** — "TBA" rows on 15 September, a 404
   on terms/privacy/support, a demo account that does not work, a backend that is
   not reachable. Over 40% of unresolved issues.
2. **EU DSA trader status not verified** — not a rejection so much as a wall, and
   the only item with an external dependency we cannot code around.
3. **5.1.1(v) account deletion missing or incomplete** — the most mechanically
   checked rule on the list, and the finance exemption does not transfer.
4. **1.2 missing one of the four bullets** — all four are required; missing any
   one is a rejection. Most commonly the *filter*, because people build reporting
   and call it moderation.
5. **The reviewer cannot complete sign-up** — email confirmation they cannot
   access is a silent, guaranteed rejection.
6. **4.2 thinness or hackathon-first metadata.**

---

## Traps specific to this app

**The bundle-id trap, again.** Same Mac, same two teams, same failure that cost
`org.stuhi.finance`. A single development build run before `DEVELOPMENT_TEAM` is
set claims the id for `DQ54FKG6B4` permanently, because App IDs are globally
unique and a personal team's cannot be deleted. Claim it today.

**Copying the finance doc's 5.1.1(v) line.** It is right there in
`APPSTORE.md` §"Before the first upload" item 7 and it is tempting. Pasting
*"the app has no account creation, so 5.1.1(v) does not apply"* into this app's
Review Notes is a written admission of non-compliance in the one field a reviewer
definitely reads.

**Copying the finance privacy manifest.** It declares financial info and receipt
photos and carries camera and photo-library usage strings for the receipt scanner.
Ours declares user content, name, email, user ID and a push token, and **must not
have `NSPhotoLibraryUsageDescription` at all** — a photo-library purpose string in
an app that never opens the photo library is a 5.1.1(iii) invitation.

**In-app messaging. Cut it now, before any code exists.** Five reasons, and one
that people cite and shouldn't:

1. It is the **hardest** 1.2 obligation, not the easiest. *"A method for filtering
   objectionable material"* applies to private messages too, and satisfying it
   means either filtering conversations between minors or reading them when
   reported — which creates a GDPR problem (Art. 5(1)(c), Art. 6) harder than the
   Apple problem. A word filter on chat also fires on ordinary teenage
   conversation dozens of times a day, and every false positive is a support
   ticket.
2. It changes the app's character. A team-matching utility with bios is a utility.
   An app where 15-year-olds privately message each other is a social app for
   minors — materially stricter review, permanently higher operational burden.
3. The 24-hour SLA becomes unbounded. You can skim 500 bios once; you cannot skim
   a live chat, so every report arrives blind, during the two days when every
   organiser is running a hackathon.
4. It is the largest scope item on the list once you include filtering, reporting
   a specific message, blocking that actually stops delivery both ways, retention,
   deletion on account deletion, and push without UGC in the payload.
5. It is not needed. 500 people in one building for 48 hours who all already have
   WhatsApp, Discord and Instagram. You would be building, moderating and legally
   owning a messaging product to replace tools that already exist and that carry
   no liability for us.

**Do not** argue against it on age-rating grounds. Messaging and Chat is rated
**4+**; adding messaging would not raise our rating. That claim is false and using
it will get the whole recommendation questioned.

Ship instead: on acceptance, both sides see the team roster and a **physical meet
point** ("Team 12 · Table B4 · 14:30") — which is what people actually need — plus
organiser-to-attendee push. If a per-team link to an off-platform channel ships,
state the trade honestly: it is org-authored so it stays outside 1.2, but it is an
unmoderated space we have pointed minors at, so that Discord needs the same
moderator rota and the terms must say the app is not responsible for off-platform
channels while STUHI's community rules still apply there.

If messaging is later judged essential, ship it in v1.1 **after** 25 October, and
ship it as a **team-scoped wall, not private DMs**: every message visible to all
team members, no 1:1 channel, filtered on write, individually reportable, block
stops delivery both ways, and a banner saying organisers can read team walls.
Group-visible-with-disclosure is dramatically easier to defend — to Apple and to a
parent.

**The monk feed must ship read-only in v1.** Posts authored by two or three named
admins in Supabase or in the existing organiser tooling at
`/Users/mominaldahdouh/stuhi-hq`. **No compose UI in the binary.** Board
announcements are editorial content, not UGC, and keeping them editorial keeps a
whole surface outside 1.2. It is also load-bearing for the age rating: App Store
Connect defines Social Media around *"a social feed or similar discovery method"*,
and a read-only org-authored feed is not a social feed. Add a compose UI and you
have shipped the one thing in the app that unambiguously is one.

**The admission QR must NOT be an Apple Wallet pass in v1.** Guideline 1.5 ends:
*"Also ensure that Wallet passes include valid contact information from the issuer
and are signed with a dedicated certificate assigned to the brand or trademark
owner of the pass."* That means a separate Pass Type ID and certificate under
`Q485H7YK66`, a signing pipeline for 500 passes, and the `~/.stuhi-signing/` backup
discipline extended to another key — for zero benefit at a 500-person indoor
event. **Cache the QR for offline rendering instead.** Revisit Wallet after the
event.

**Money in the app.** None. Not tickets, not merch, not IAP, not a donate button.
Three separate rules land the moment it appears: 3.2.2(iv) (non-profit fundraising
needs approval and must be collected outside the app), 3.1.1, and Finnish contract
capacity for minors under Holhoustoimilaki. A free event is a customary
transaction and fine; a paid one from a 15-year-old is not.

**The demo Report and Block must actually work.** A Report button that no-ops
against a static fixture reads as a stub and fails 2.1(a) and 1.2 in the same
pass. Seed real database rows and walk it yourself.

**DSA obligations that survive the micro-enterprise exemption.** Art. 19 exempts
micro and small enterprises from Section 3 (Arts. 20–28), including Art. 28's
protection-of-minors duties. It does **not** exempt: **Art. 16** (notice and
action — which is why the `reports` row carries `reporter_id` and `content_ref`),
**Art. 17** (statement of reasons on removal — a templated email from
`moderation@stuhi.org` covers it), **Art. 11** (a point of contact for
authorities) and **Art. 12** (a point of contact for users, direct and electronic,
*not solely automated*). Arts. 11 and 12 are closed by one paragraph on
`stuhi.org/terms` and `/support` explicitly designating those addresses and naming
the languages accepted. Also **Art. 14(3)**: terms for a service predominantly
used by minors must be explained so minors can understand them — which is why the
terms are plain-language and in Finnish.

And a bonus from the design: under Art. 3(i) an "online platform" is a hosting
service that disseminates information *to the public*. **Because bios are visible
only to verified attendees of a specific event, we are arguably a hosting service
but not an online platform** — which removes Arts. 20–28 before the
micro-enterprise exemption is even reached. That makes "signing up does not grant
access to people" do double duty: it is the Apple defence *and* the EU-law
defence. Break it and we probably become an online platform. *(My reading, not
legal advice — the classification question in particular should be confirmed by
someone who is a lawyer.)*

**The identity property that is quietly load-bearing.** 1.2 names *"random or
anonymous chat"* as a prohibited pattern. Every account here maps to a named person
who physically attends, off an organiser-imported roster. **Protect that**: never
add pseudonymous handles, never let the display name diverge freely from the
roster name. The moment a user can pick an unlinked alias, we have moved toward
"anonymous" and lost the best 1.2 argument we have.

**The DPIA.** Confidence that one is *strictly legally mandatory*: low, ~25–30% —
the Finnish Ombudsman's mandatory list covers biometric, genetic, location,
information-obligation derogations and whistleblowing, none of which apply, and we
plainly miss "large scale" at 500 people. Confidence it is worth writing anyway:
**very high.** Two pages at `docs/DPIA.md`: purposes, data, bases, necessity, risks
(peer harassment via bios, QR forgery, roster exposure, retention drift),
mitigations, residual risk, a date. If anyone ever complains, that document is the
difference between a conversation and a problem.

**Sending someone's own name back to them in a push.** 4.5.4 forbids sensitive
personal information in payloads, and a crowded hall makes a lock screen a public
display. Always second person. Always the team *number*, not a user-chosen team
name, unless that name has passed the filter and is re-checked against `visible`
at send time.

**Retention that lives only in a document.** Every one of the retention rules
above must be a `pg_cron` job in week one. A policy written down and not scheduled
is a policy that will not happen on 24 November — and the 30-day meal-pepper
destruction is the thing that makes the "irreversibly anonymised" line in Review
Notes true rather than a claim we cannot support.
