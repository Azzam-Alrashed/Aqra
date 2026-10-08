# Aqra — Vision

> «يقالُ لصاحِبِ القرآنِ اقرَأ وارقَ ورتِّل كما كُنتَ ترتِّلُ في الدُّنيا فإنَّ منزلتَكَ عندَ آخرِ آيةٍ تقرؤُها»
>
> رواه أحمد

This document records the product decisions agreed so far. It is a living document: update it as open questions are settled.

## Goal

Help Quran memorizers through the whole journey: memorizing, revising, and mastering what they have memorized, from the first ayah to lasting mastery.

Aqra began as a revision app for huffaz. On 2026-10-07 its scope grew to the full journey, taking the Etqan Quran Platform document as a reference (not as a specification).

### The منازل

The منازل are the ayat themselves, as the hadith says: a student's منزلة is the last ayah they have reached. The student rises one ayah at a time as they memorize, and each ayah carries a strength that grows with revision and fades without it.

### Guiding principles

- **The Quran text is sacred data.** See [Quran text](#quran-text).
- **The منازل are motivational.** They remind the user of the hadith and never claim to represent a real rank in the Hereafter.
- **Constructive competition.** Competition tools, leaderboards included, are welcome when they create a constructive, motivating environment. Features that encourage showing off for its own sake are avoided, to preserve sincerity (إخلاص).
- **Every rule is a policy, not code.** Review intervals, mastery thresholds and similar rules live in one adjustable place, so they can be tuned after trying them with real huffaz and sheikhs.

## Release waves

Each wave is complete and usable on its own, and each depends on the one before it.

| Wave | Scope | Status |
|---|---|---|
| **1. The student alone** | Offline, no account: the Mushaf, the memorization map, the revision engine, and today's wird. | Built (2026-10-07) |
| **2. The student with others** | Accounts, teachers and tasmee' (in person and by video), the "verified" mark, peer tasmee', applications to teach. | Built (2026-10-07); video needs a LiveKit Cloud project |
| **3. The full journey** | The personal plan with new memorization and a completion date, stages and tests, rewards and competitions, credits, the seat auction, teacher earnings. | Built (2026-10-07), provisionally (see [SRS.md](SRS.md), Appendix A); payments need App Store Connect |

The requirements, their status and the provisional defaults adopted to build waves 2 and 3 are in [SRS.md](SRS.md).

## Platform

- **First release:** an iOS app, built as an Xcode project with SwiftUI.
- **Minimum deployment target:** iOS 17. It can be raised if a feature requires it.
- **Later:** Android and the web. Data and logic, such as ayah IDs, scheduling and منازل, are designed to be platform-neutral so the expansion is straightforward.

## Quran text

Accuracy of the Quran text is the project's highest requirement.

### Source and display

- **Source:** the King Fahd Glorious Quran Printing Complex (مجمع الملك فهد لطباعة المصحف الشريف).
- **Riwayah:** Hafs only, for now.
- **Display:** 604 Mushaf pages in the Madinah layout of the **1441H print**, so that huffaz keep the visual memory of where each ayah sits on the page. The page fonts carry the tajweed colors, which can be turned off.

### Safeguards

1. **Bundled unmodified.** The text is never typed by hand, edited, generated or "cleaned up".
2. **Checksum.** A checksum of the original files is recorded, and a test fails the build if the text changes.
3. **Cross-verification.** The layout is checked against the Complex's official data line by line, by a test.
4. **Rendering review.** A qualified hafiz reviews the rendering before release, with and without tajweed colors.
5. **License.** The Complex's usage terms are respected, and the Complex is credited in the app.

See `shared/quran/README.md` for the sources, the provisional ones, and what must be settled before release.

## The screens

### The look

Every screen speaks the onboarding's language: the colored-Mushaf pastels on a soft lavender surface, two-line headlines with the second line in purple, emoji in tinted rounded squares, white cards lifted by soft shadows, chips that float, and entrances that build up with gentle springs and haptics. The building blocks are shared (`DesignSystem/AqraComponents.swift`), so the onboarding and the app stay identical.

The app opens on that lavender, in light and dark mode alike, with a faint, out-of-focus glimmer of the arch logo. While the Mushaf loads, the logo fades in out of a soft light and comes into focus as it settles; the star turns in and lands with a soft tap, the sparkles follow one by one, and gold light swells around the star as the logo breathes. Then it drifts out of focus and the home rises with its own entrance. On the very first launch the glimmer fades as the welcome builds the logo itself.

### Tabs

A floating tab bar holds الرئيسية, التسميع, تقدّمي and حسابي. The Mushaf is not a tab: it's a button on the home. The Mushaf and today's wird open full screen over everything and close back where they were opened, so revising never moves the student's place in the Mushaf.

### Home

The home answers «وش علي اليوم؟». It shows:
- **The stage:** the منازل stairs (ten glossy steps of three juz' each) inside glowing rings, with chips for the share of the Quran memorized and the memorization's strength, and the revision streak and a bell for messages above.
- **Today's wird:** a headline with the pages left and the length of a full revision, and one button to start.
- **Today's new portion:** from the personal plan, with «احفظ» and the expected completion date (or an invitation to make a plan).
- **The current stage:** how much of it is memorized and mastered; it opens the stage.
- **Pages that keep slipping,** suggested for extra follow-up, to take or dismiss.
- **The Mushaf:** a miniature of the page last read, which opens it.
- **Today's pages:** each page as a tile in its juz's color; tap to revise it, press and hold if it was revised outside the app (clean, or with stumbles).
- **What's memorized and the daily amount,** each opening its editor.

The home also shows what a teacher or a friend just heard (applied to the progress), the next tasmee' booked (or that its teacher cancelled it), leading to the التسميع tab, and, after the first revision, a calm invitation to sign in.

### Progress (تقدّمي)

The share of the Quran memorized, beside the shares mastered and verified (kept apart, as Etqan asks); the revision streak over the last seven days, a few numbers, and every juz' at a glance: how much of it is memorized and how strong. Below: the personal plan, the ten stages, the rewards (points, achievements and the week's challenges), and «مع الآخرين» (friends and competitions).

### Account (حسابي)

The account the progress is backed up to and the name others see, credits, the Mushaf's colors, a daily reminder, sounds, the app's language, and the sources Aqra is built on, credited as their terms ask. What's memorized and the daily amount are edited from the home only.

### Tasmee' (التسميع)

The same tab serves both roles.

- **Every student** sees their next booked session (with "Cancel booking", and "Join the call" for a video session), reciting to or hearing a friend, the vetted teachers, what others heard, and "Teach on Aqra". A teacher's page shows their profile and upcoming sessions, each with "Book" (or "Full"), and "Bid" for seats by auction; an anonymous student is asked to sign in before booking.
- **A teacher** sees their profile (editable), their earnings, "My sessions" and "My students" above that: each upcoming session with its seat count, and "New session" (when, in person or by video, how many free seats, and seats by auction). A session's page lists the students who booked (and the bids), with their name and what they've memorized; tapping a student opens the **marking screen**: the Mushaf on the teacher's phone, turned page by page as the student recites, a tap on an ayah marks a stumble, pressing and holding it says what kind of mistake it was, a button marks each page heard, a menu makes it a stage test, and «سجّل التسميع» records it all. The teacher's own memorization colors stay off the page. Each student has a file the teacher keeps: what they heard, and private notes.
- **A friend** hears a student with the code the student shows (or its QR), on the same marking screen; the record lands in the student's account as a peer's tasmee'.

The record lands in the student's account, and the **student's app applies it**: a sheikh's revision of the pages heard, and the "verified" mark on the clean ayat (see [REVISION.md](REVISION.md)). The teacher never reads the student's progress; the booked seat carries a small summary (pages memorized, whole juz') so the teacher can choose what to hear.

### Mushaf

The Mushaf is where the student reads and marks what they have memorized. It opens on the last page read, and its top bar leads back home. Its bars float over the page as white capsules in the app's colors, so the paper stays the Mushaf's own.

- **Memorized ayat are colored.** Each ayah takes the color of its topic section, as in a printed thematic Mushaf, drawn as a soft highlight behind its words. The color is faint when the ayah is newly memorized, fuller as it grows strong, and fades when revision is overdue. Unmemorized ayat stay plain paper.
- **Tajweed colors** on the letters, with their own toggle.
- **Marking mode** marks pages and ayat as memorized directly on the page.

### Today's wird

The wird goes through its pages one after another, each held still with its memorized ayat veiled and revealed one at a time, then returns home when it's done.

## The personal plan

The student chooses how much new memorization a day (a quarter page to a page and a half, in lines of the page), on which days, and in which order (from juz' ʿAmma back toward al-Baqarah, or from the beginning; by default the order continues what's already memorized). Each study day proposes today's portion: the next ayat not yet memorized, whole ayat, finishing a surah before the next. On the memorize screen the portion stands out on its pages; the student repeats it, hides ayat to recite them, and «حفظته» (or just the part memorized) starts them faint in the revision engine, back for follow-up the next day. Planned and actual portions and every change of the plan are kept. The expected completion date follows the plan's pace, then the student's recent one.

## Stages, mastery and tests

The ten stairs are Etqan's ten stages of three juz' each. Each shows how much of it is memorized, **mastered** (half-life of at least 60 days, clean since the last stumble) and verified. Passing a stage asks for all of it memorized, 80% mastered, the stage's test in the app ("which ayah comes next?", "which surah?", shown in the Complex's own text and font) and a teacher's stage test (mistakes within one per page heard). All of it is provisional, in one policy (see [SRS.md](SRS.md)). Etqan's 240 stars wait for an authoritative source of the rub' boundaries.

## Memorization

### Where the student starts

The student **declares** what they already know, by juz', by surah, by page, and ayah by ayah, with a "whole Quran" shortcut:
- juz' and surahs on the «ماذا تحفظ؟» screen right after onboarding;
- pages and ayat in the Mushaf's marking mode.

A tasmee' with a teacher **confirms** it: the ayat heard clean get a "verified" mark, and a stumble before the teacher takes it away until the ayah is heard clean again. A tasmee' never marks new ayat as memorized: the student owns the map.

### Strength of an ayah

Every memorized ayah has a half-life that fades with time, grows with each clean revision and shrinks with each stumble. The details and every number are in [REVISION.md](REVISION.md).

## Revision

Each day's wird takes, in order, pages stumbled on recently (follow-up), then the next pages of a rotation through everything memorized, in Mushaf order, up to the daily amount the student chose. Missed days don't pile up.

A revision is recorded in one of three ways:
1. **In the app:** the page's ayat are veiled; the student recites, reveals them one at a time, and taps the ayat they stumbled on.
2. **Outside the app** (in prayer, or to a friend): the page is checked off from the wird.
3. **With a sheikh** during tasmee': the teacher marks the pages heard and the stumbles on their own phone, and the student's app records them as a sheikh's revision.

A sheikh's tasmee' counts more than self-revision (1.5 times, provisionally); a peer's sits between the two (1.25). The rotation learns: pages that keep slipping are suggested for extra follow-up, and the student decides.

See [REVISION.md](REVISION.md) for the policy, its defaults, and the open questions.

## Connectivity

- **Wave 1 works entirely offline with no account.**
- **Online only:** accounts, video calls, booking, the auction, and competitions.

## Accounts

Every user starts as an anonymous Firebase user, and their progress is backed up to that account from the first day. Signing in with Apple or Google links the sign-in to the same account, so nothing is lost. If the sign-in already belongs to an account (another device, an earlier install), that account is used and this device's progress is merged into it. Signing in is required before booking tasmee' or buying credits.

- **What's stored:** what's memorized (with each ayah's strength and the verified mark), the revision record, the student's bookings, and the tasmee' records teachers write. The device's copy is the one the app works from; the account is its backup, restored on a new device or after a reinstall. It isn't live editing on two devices at once.
- **Where:** Firestore, Storage and the Cloud Functions together in Belgium (europe-west1).
- **Signing out** keeps the progress in the account and clears the device.
- **Deleting the account** deletes the account and everything backed up in it, as Apple requires; the progress on the device stays.

## Roles

### Student

- Memorizes and revises.
- Books tasmee' sessions with teachers.

### Teacher

A separate role. Becoming a teacher requires:
- **An ijazah,** reviewed by the app before acceptance.
- **A personal interview.**
- **Other vetting procedures** (details TBD).

Teachers use the same app. A teacher is enabled by hand once vetted (a `teachers/{uid}` document marked vetted, see `backend/README.md`), and the التسميع tab then shows their sessions and students.

## Tasmee' sessions

- **Booking:** the student chooses any vetted teacher and books a seat in one of their sessions. In wave 2 seats are free, first come first served; the auction adds paid seats in wave 3. Booking needs a signed-in (not anonymous) account. The seat, the student's own copy of the session and the seat count are written in one transaction, so a session never takes more students than it has seats.
- **In person or by video:** in person, the teacher marks each student's mistakes on his own phone during the session; remotely, a live video call in the session's room, with the reciting student's video floating over the teacher's Mushaf.
- **By video:** a live audio and video call in which the student recites and the teacher corrects, marking mistakes on the ayat.
- **Video provider:** LiveKit Cloud. Self-hosting is an option later if costs grow.
- **Access:** room tokens are issued by Cloud Functions only after verifying that the user holds a seat in that session.

### Seat auction

Each session has a limited number of free seats, first come first served, and may add seats by auction.

**Biddable seats:**
1. **Start free:** a seat can initially be reserved at no cost.
2. **Bidding:** other students can outbid, and the price rises.
3. **Close:** bidding closes shortly before the session starts.
4. **Winners:** the highest bidders win the seats.

**Reserved free seats:** each session has free seats that cannot be bid on (at least one). They are given first come, first served.

Bidding closes three hours before the session (provisional). A session cancelled while bidding releases every hold; once settled, the credits are refunded and the teacher's share reversed.

**Integrity:** all bids go through Cloud Functions with Firestore transactions, so a seat can never be won twice.

## Payments

### Students

Students pay through **Apple In-App Purchase**, chosen for simplicity.

Because Apple In-App Purchase only sells fixed-price products, the app uses **credits**:
1. **Buy:** students buy consumable credit packs.
2. **Hold:** credits are held when a student bids.
3. **Release:** held credits are returned if the student is outbid.
4. **Spend:** credits are spent only if the student wins the seat.

### Teachers

- **Revenue split:** the teacher receives most of each winning bid (80%, provisionally), and the app keeps a commission to cover servers and video calls. Apple's fee also applies on top of this, at 15% under the Small Business Program or 30% otherwise.
- **Earnings:** each teacher's share accrues as earnings visible in their account.
- **Payouts:** teachers are paid traditionally, by bank transfer, since there are few teachers at first.

### Note on Stripe

Stripe does not currently support Saudi-based businesses directly. Revisit Stripe Connect or a regional gateway such as Tap if the company structure changes.

## Rewards and competitions

Competitions must be constructive and motivating, consistent with the [guiding principles](#guiding-principles). Built, provisionally:
- **Rewards:** private points for each step (revising, memorizing, completing the wird, streaks, stages), achievements, and small celebrations with a soft chime.
- **Personal challenges,** where the student competes only with themselves, for a week.
- **Private races between friends:** pages revised, days revised or ayat memorized within their dates; friends are added by a code, and see only each other's names in the competitions they share.
- **Group khatmahs:** thirty parts, claimed and finished by the group's members.
- **Teacher-run competitions** for a teacher's own students, scored by the server from the pages the teacher heard clean.

Public standing should rest on verified evidence (a sheikh's tasmee'), not on self-reports: there is no public leaderboard.

## Backend

- **Firebase:**
  - **Auth:** anonymous users, then Sign in with Apple and Google. Phone number sign-in may be added later.
  - **Firestore.**
  - **Cloud Functions.**
- **LiveKit Cloud** for video calls.

## Market and language

- **Market:** global from the start.
- **Interface languages:** Arabic, with full right-to-left layout, and English. The architecture is ready for more languages, such as Urdu, Indonesian, Turkish and French.
- **Mushaf text:** always displayed in Arabic as published.

## Open questions

The full list, with the provisional defaults adopted to build them, is in [SRS.md](SRS.md), Appendix A.

- **Dark mode for the app's own screens:** the Mushaf follows the system's dark mode; the rest of the app keeps its light look until a dark palette for it is reviewed.
- **Topic sections:** the stand-in data must be replaced by a published thematic Mushaf's division, with the publisher's permission.
- **Revision policy:** the numbers in [REVISION.md](REVISION.md), the sheikh's weight among them, need trying with real huffaz and sheikhs.
- **Stages and tests:** the stage requirements and their numbers; the 240 stars' boundaries.
- **Free seats:** how many reserved free seats each session has.
- **Commission:** the app's commission percentage.
- **Teacher vetting:** the full acceptance procedure beyond the ijazah and interview.
- **Competitions:** their detailed design.
