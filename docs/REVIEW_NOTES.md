# STUHI — App Review Notes and App Store Connect metadata

Two things in this file:

1. **Notes for Review** — the literal text to paste into App Store Connect →
   *[version] → App Review Information → Notes*. Under 4000 characters.
2. **Metadata** — the ready-to-paste listing fields.

Anything in `<angle brackets>` or `[square brackets]` is a placeholder that must be
filled in before submission. Do not paste a placeholder into App Store Connect.

---

## Notes for Review

> Paste everything between the rules below into the Notes field, after replacing
> the three passwords and the PRH register number.
>
> **Length: 3,954 characters as written — 46 characters of headroom under 4,000.**
> The four placeholders total 48 characters (`[PRH-NUMBER]` plus three
> `<PASSWORD-n>`), so if the real values are longer than the placeholders you will
> go over. Keep each password short-ish, or drop the "REGISTRATION DATA" heading
> word and shorten the push paragraph. **Re-count after every edit:**
> `sed -n '/^STUHI is the community app/,/notification\.$/p' docs/REVIEW_NOTES.md | wc -m`

---

STUHI is the community app of Nuorten startup- ja innovaatioyhdistys ry, a registered Finnish non-profit student entrepreneurship association (PRH register no. [PRH-NUMBER]). It serves the association year-round — news, member profiles, internal updates for the core team — and events run inside it as entries. The current one is STUHI X TAMPERE, 24-25 October 2026, Tampere University Hervanta Campus. STUHI authors all content; this is not a template app.

NO ACCOUNT NEEDED
The app opens on Schedule and Challenges, both fully readable signed out, along with About STUHI, the venue, the code of conduct and the privacy policy. Sign-in is only for personal features.

ACCOUNTS FOR REVIEW
1) Member/attendee — reviewer@stuhi.org / <PASSWORD-1> (also in Sign-In Information above). Already on the seeded demo event's list, so the pass, a team, a pending join request and a pending invite are all present.
2) STUHI core team ("monk") + staff scanner — reviewer.monk@stuhi.org / <PASSWORD-2>.
3) Spare, for testing deletion — reviewer.delete@stuhi.org / <PASSWORD-3>. Please use this one for the delete flow so the main demo account stays usable.
All three are pre-confirmed (no email step) and contain fictional data only.

WHERE EVERYTHING IS
- Admission pass: Pass tab. The app issues its own signed token; it verifies offline.
- QR scanner (monk account): STUHI tab → Scan. Because a reviewer has one device, tap "Enter code manually" and use DEMO-7K42-QX19 for a successful door check-in, then the same code again for the duplicate-scan result. "Show a sample attendee QR" renders a scannable code on screen. If camera access is declined the screen explains why and offers manual entry rather than a blank frame.
- Team matching: Teams tab. Browse teams, open one, request to join; teams invite. Directed request-and-accept only: no swipe deck, no rating, ranking or scoring of people, no search over people, no user photos, no in-app messaging, no dating intent.
- Internal updates ("monk") feed: STUHI tab, monk account only. Written by the association, not by users — not a social feed, not messaging. Monk access is granted server-side and cannot be self-selected; nobody is blocked from using the app as a member.

USER-GENERATED CONTENT (1.2)
The only user-written content is an optional short bio, a display name and a team description. Each is checked against a blocklist on the server before it appears, and contact details (emails, phone numbers, social handles) are stripped. Report and Block sit in the ⋯ menu on every profile, team and incoming request. Blocking is immediate and mutual and cancels pending requests; manage it at Settings → Blocked People. Reports reach a named organiser on rota and we act within 24 hours. Our contact details are at Settings → About → Contact STUHI (moderation@stuhi.org, support@stuhi.org) and at https://stuhi.org/app/support. Users can clear their own bio and team text at any time.

ACCOUNT DELETION (5.1.1(v))
Settings → Account → Delete Account, two taps from the Profile tab. It permanently deletes the account and all personal data, including the bio and any requests or invitations sent. Attendance and meal records are kept in a form that cannot identify the user for 30 days for catering totals, then destroyed. No email or phone call is required.

REGISTRATION DATA
Attendees register on our own public web form, which states there that their name and email are passed to STUHI to issue their admission code. Organisers import that list through a web admin tool on our server — the iOS app holds no list of people and shows nothing about anyone who has not created their own account. We obtain personal data from no other source.

PUSH NOTIFICATIONS are operational only (meals, schedule changes, team placement), never marketing, and optional: everything pushed is also visible in-app, with per-category toggles at Settings → Notifications. No user-written text appears in a notification.

---

## Metadata

Paste-ready App Store Connect listing fields. Counts verified; the English keyword
string is at 97/100 **bytes**, the Finnish subtitle at 30/30 bytes — neither has
room for another non-ASCII character.

### App Information (applies to all versions)

| Field | Value |
|---|---|
| Bundle ID | `org.stuhi.app` — **claim under team Q485H7YK66 before any device build runs**; fallback `org.stuhi.community` |
| SKU | `stuhi-app-001` |
| Primary Language | English (U.S.) |
| Primary Category | **Education** |
| Secondary Category | **Social Networking** |
| Made for Kids | **No** — never tick this |
| Content Rights | Declare third-party content: the challenge briefs are authored by partner companies, so hold their written permission |
| Privacy Policy URL | `https://stuhi.org/app/privacy` (required; must be live and reachable from outside Finland before submission) |
| EU DSA trader status | Verify at Business → Agreements → Digital Services Act, **and** set the per-app declaration under App Information → App Store Regulations and Permits. Published phone + email must reach a human. |

### Version Information — English (U.S.)

**App Name** (25/30 characters)

```
STUHI: Student Innovation
```

**Subtitle** (26/30 characters)

```
Startup community & events
```

**Promotional Text** (147/170 characters — editable any time without a new build)

```
STUHI × TAMPERE runs 24–25 October at Hervanta Campus, Tampere. Your pass, the challenge briefs, the schedule and team matching are all in the app.
```

> Use `×` (multiplication sign) or lowercase `x`, never a bare capital `X` — it
> reads as a reference to another app under 2.3.7.

**Keywords** (97/100 bytes; every keyword ≥ 4 characters; no word duplicated from
the name or subtitle; singulars only; no category names; no "app")

```
hackathon,entrepreneur,team,match,challenge,schedule,agenda,pass,event,youth,tampere,finland,lukio
```

**Description** (~2,600/4,000 characters)

```
STUHI is the app of Nuorten startup- ja innovaatioyhdistys ry — a registered Finnish non-profit association for students who want to build things: startups, prototypes, projects, and the skills that go with them.

The app is where the association lives between and during its events. Read what STUHI is doing, follow announcements, and find the people working on the same things you are.

EVENTS
STUHI runs events through the year, and each one lives inside the app. The current event is STUHI X TAMPERE, 24–25 October 2026 at Tampere University, Hervanta Campus.

YOUR PASS
Every registered participant gets a personal entry pass in the app. It is issued by STUHI and works at the door and at meal service. It renders without a network connection, which matters in a building with five hundred phones on the same wifi.

CHALLENGES
The problem statements written by our partner organisations, in full, in the app. Read them before the event, pick the one you want, and come prepared.

SCHEDULE
Everything that is happening and when. If something moves, the schedule updates and you get a notification — if you want one.

FIND A TEAM
Pick the roles you can cover from a fixed list, and write a short bio if you want to. Teams say which role they are missing. You ask to join a team; teams invite people. Both sides have to agree. Anyone still without a team by the deadline is placed on one by the organisers.

There is no swiping, no rating people, no ranking, and no scoring. Team matching is a request and an acceptance between a person and a team, and nothing else.

NOTIFICATIONS
Only the operational kind: food is served, a session moved, you have been placed on a team. No marketing, ever. Every one of them can be turned off individually inside the app, and everything they tell you is visible in the app anyway.

SAFETY
Bios and team descriptions are checked against a blocklist before they appear, and contact details are removed automatically. Every profile, team and request has Report and Block. Blocking is immediate and works both ways. Reports go to a named STUHI organiser, and we act on them within 24 hours. You can reach us at moderation@stuhi.org and support@stuhi.org, in the app under Settings → About.

PRIVACY
No tracking, no analytics, no advertising, no third-party SDKs, no AI services. Your data is stored in the European Union. You can delete your account and everything in it from inside the app, at Settings → Account → Delete Account.

FOR THE STUHI TEAM
People active in the association also see internal updates — new equipment, new spaces, board announcements — and can scan participants in at events. This access is granted by the association.

The app is for people aged 13 and over.

This app is published by STUHI and is not affiliated with, endorsed by, or sponsored by any university or venue.
```

**Copyright** (no `©` symbol — App Store Connect adds it)

```
2026 Nuorten startup- ja innovaatioyhdistys ry
```

**Support URL** (required — the page must carry the association's legal name and
PRH number, registered address, **a telephone number**, a monitored email
(`app@stuhi.org`), how to report content, how to block, how to delete an account,
and a stated response time)

```
https://stuhi.org/app/support
```

**Marketing URL** — leave **blank**. A hackathon landing page here undercuts the
"ongoing association, not a single event" positioning that the whole naming
strategy exists to protect.

**What's New** — not required for version 1.0.

### Version Information — Finnish (fi)

A `fi` localization also requires its own Description, Support URL and Screenshots.
Confirm in App Store Connect whether the screenshot slots were copied from the
default localization before assuming Finnish captions are unnecessary — the
audience is 100% Finnish, so Finnish captions are worth the work either way.

**App Name** (25/30 characters)

```
STUHI: Nuorten yrittäjyys
```

**Subtitle** (29 characters / **30 bytes** — at the cap, no headroom)

```
Startup-yhteisö ja tapahtumat
```

**Keywords** (98/100 bytes)

```
hackathon,tiimi,haaste,aikataulu,opiskelija,lukiolainen,innovaatio,verkosto,tampere,suomi,kilpailu
```

### Age rating

Answer the questionnaire honestly, then **raise the minimum age to 13+** using the
"higher minimum user age" control — the app's own published policy sets 13, matching
Finland's Tietosuojalaki 1050/2018 § 5.

| Question | Answer |
|---|---|
| User-Generated Content | **Yes** |
| Social Media | **Yes** (bios surfaced through a discovery surface) |
| Social Media Disabled for Users Under 13 | No (requires the Declared Age Range API, iOS 26+; deployment target is iOS 17) |
| Messaging and Chat | **No** — ship requests and invites button-only, with no free text |
| Contests | **No, conditionally** — only if the binary carries no prize amounts, no leaderboard, no scores, no winner announcement and no entry submission. If any of those ship, answer **Yes**. |
| Unrestricted Web Access | No — open external links in Safari; never ship an in-app browser that can reach arbitrary URLs (it would force 16+) |
| Parental Controls / Age Assurance | No / No |
| Advertising | No |
| Mature themes, medical, sexuality, violence, gambling, loot boxes | None / No |

### Pricing and Availability

Free. **Restrict territories to Finland** (or the EEA).

This closes three live legal exposures in one control: Australia's under-16 social
media law (in force 10 Dec 2025, and this app answers Social Media = Yes with open
sign-up and no age assurance), and the US state age-assurance statutes that place a
duty on *developers* — Texas SB 2420 (live 4 Jun 2026), Utah, Louisiana. App Store
availability is per country, so Texas cannot be excluded on its own.

Note the open disagreement in the source analysis: the distribution review argued
for worldwide availability on the grounds that 3.2.2(v) forbids "arbitrarily
restricting who may use the app … by location". That guideline governs gating
*inside* a distributed app, not which storefronts you publish to; territory
selection is a first-class App Store Connect control. **Restricting to Finland is
the recommendation here**, but it is a decision the association should record
deliberately, because it is the one place the five reviews do not agree.

Use **scheduled or manual release** so the listing goes live when STUHI is ready,
not the moment approval lands.

### Screenshots

- **6.9-inch iPhone only** — 1320×2868, 1290×2796 or 1260×2736. Do not upload other
  sizes; Apple scales down from the largest provided.
- PNG or JPG, **no alpha channel** (an alpha channel is rejected at upload).
- 8 shots. Shots **1–3 are the search-results set**. Include at least one in Dark Mode.
- **No role chooser and no sign-in screen anywhere** (2.3.3: screenshots must show
  the app in use).
- Fictional names and bios only (2.3.9). Nothing that implies the audience is
  children — this extends to the icon (5.1.4(b)).
- iPad not supported: `TARGETED_DEVICE_FAMILY = 1`, so no 13-inch set is needed.
- The 1024×1024 App Store icon is **not** a listing upload; it is read out of the
  build's asset catalog / Icon Composer file.

Suggested order: 1 Pass · 2 Challenges list · 3 Team detail with Request to join ·
4 Challenge detail · 5 Schedule · 6 Monk feed · 7 In-app updates inbox (never a
mocked-up iOS banner) · 8 Settings showing Delete Account with Report/Block visible.

### App Review Information

| Field | Value |
|---|---|
| Contact name / email / phone | A person who will answer during the review window |
| Sign-In required | Yes |
| Sign-In username / password | `reviewer@stuhi.org` / `<PASSWORD-1>` |
| Notes | The block at the top of this file, with the other two accounts named in it |

### Also worth setting up (not required for v1.0)

- **In-App Event** — "STUHI × Tampere 2026", type Special Event. Reviewed
  independently of the app version, so it does not touch the binary's queue.
  Submit by **10 October 2026** to use the 14-day pre-promotion window.
- **Custom Product Page** — a hackathon-framed variant with its own URL for the
  registration confirmation email, posters and school outreach. Keeps the default
  product page evergreen and association-shaped for App Review.
- Skip Product Page Optimization (A/B testing) — 500 users will never reach
  significance.
