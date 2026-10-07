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
| **2. The student with others** | Accounts, teachers and tasmee', the "verified" mark, peer tasmee'. | Next |
| **3. The full journey** | The personal plan with new memorization and a completion date, stages and tests, competitions, the seat auction, payments. | Later |

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

### Tabs

A floating tab bar holds الرئيسية, تقدّمي and حسابي; التسميع joins them in wave 2. The Mushaf is not a tab: it's a button on the home. The Mushaf and today's wird open full screen over everything and close back where they were opened, so revising never moves the student's place in the Mushaf.

### Home

The home answers «وش علي اليوم؟». It shows:
- **The stage:** the منازل stairs (ten glossy steps of three juz' each) inside glowing rings, with chips for the share of the Quran memorized and the memorization's strength, and the revision streak above.
- **Today's wird:** a headline with the pages left and the length of a full revision, and one button to start.
- **The Mushaf:** a miniature of the page last read, which opens it.
- **Today's pages:** each page as a tile in its juz's color; tap to revise it, press and hold if it was revised outside the app.
- **What's memorized and the daily amount,** each opening its editor.

In wave 2 the home also shows a booked tasmee' and, after the first achievement, a calm invitation to sign in.

### Progress (تقدّمي)

The share of the Quran memorized, the revision streak over the last seven days, a few numbers, and every juz' at a glance: how much of it is memorized and how strong.

### Account (حسابي)

Where the progress lives (on the device, until accounts come in wave 2), the Mushaf's colors, a daily reminder, the app's language, and the sources Aqra is built on, credited as their terms ask. What's memorized and the daily amount are edited from the home only.

### Mushaf

The Mushaf is where the student reads and marks what they have memorized. It opens on the last page read, and its top bar leads back home.

- **Memorized ayat are colored.** Each ayah takes the color of its topic section, as in a printed thematic Mushaf, drawn as a soft highlight behind its words. The color is faint when the ayah is newly memorized, fuller as it grows strong, and fades when revision is overdue. Unmemorized ayat stay plain paper.
- **Tajweed colors** on the letters, with their own toggle.
- **Marking mode** marks pages and ayat as memorized directly on the page.

### Today's wird

The wird goes through its pages one after another, each held still with its memorized ayat veiled and revealed one at a time, then returns home when it's done.

## Memorization

### Where the student starts

The student **declares** what they already know, by juz', by surah, by page, and ayah by ayah, with a "whole Quran" shortcut:
- juz' and surahs on the «ماذا تحفظ؟» screen right after onboarding;
- pages and ayat in the Mushaf's marking mode.

Later, a tasmee' with a teacher **confirms** it, adding a "verified" mark (wave 2).

### Strength of an ayah

Every memorized ayah has a half-life that fades with time, grows with each clean revision and shrinks with each stumble. The details and every number are in [REVISION.md](REVISION.md).

## Revision

Each day's wird takes, in order, pages stumbled on recently (follow-up), then the next pages of a rotation through everything memorized, in Mushaf order, up to the daily amount the student chose. Missed days don't pile up.

A revision is recorded in one of three ways:
1. **In the app:** the page's ayat are veiled; the student recites, reveals them one at a time, and taps the ayat they stumbled on.
2. **Outside the app** (in prayer, or to a friend): the page is checked off from the wird.
3. **With a sheikh** during tasmee' (wave 2).

Each source will carry a different weight: self-revision less than a peer's tasmee', and a peer's less than a sheikh's.

See [REVISION.md](REVISION.md) for the policy, its defaults, and the open questions.

## Connectivity

- **Wave 1 works entirely offline with no account.**
- **Online only:** accounts, video calls, booking, the auction, and competitions.

## Accounts

Every user starts as an anonymous Firebase user. Their progress lives on the device until they sign in with Apple or Google, which links the credential to the anonymous account so nothing is lost. Signing in is required before booking tasmee' or buying credits.

## Roles

### Student

- Memorizes and revises.
- Books tasmee' sessions with teachers.

### Teacher

A separate role. Becoming a teacher requires:
- **An ijazah,** reviewed by the app before acceptance.
- **A personal interview.**
- **Other vetting procedures** (details TBD).

## Tasmee' sessions

- **Booking:** the student chooses a teacher and books a tasmee' time slot.
- **Format:** a live audio and video call in which the student recites and the teacher corrects, marking mistakes on the ayat.
- **Video provider:** LiveKit Cloud. Self-hosting is an option later if costs grow.
- **Access:** room tokens are issued by Cloud Functions only after verifying that the user holds a seat in that session.

### Seat auction

Each session has a limited number of seats.

**Biddable seats:**
1. **Start free:** a seat can initially be reserved at no cost.
2. **Bidding:** other students can outbid, and the price rises.
3. **Close:** bidding closes shortly before the session starts.
4. **Winners:** the highest bidders win the seats.

**Reserved free seats:** each session has free seats that cannot be bid on. They are given first come, first served.

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

- **Revenue split:** the teacher receives most of each winning bid, and the app keeps a commission to cover servers and video calls. Apple's fee also applies on top of this, at 15% under the Small Business Program or 30% otherwise.
- **Earnings:** each teacher's share accrues as earnings visible in their account.
- **Payouts:** teachers are paid traditionally, by bank transfer, since there are few teachers at first.

### Note on Stripe

Stripe does not currently support Saudi-based businesses directly. Revisit Stripe Connect or a regional gateway such as Tap if the company structure changes.

## Competitions

Competitions must be constructive and motivating, consistent with the [guiding principles](#guiding-principles). They may include:
- **Personal challenges,** where the student competes only with themselves.
- **Group goals,** such as a shared khatmah.
- **Private competitions between friends.**
- **Teacher-run competitions** for a teacher's own students.

Public standing should rest on verified evidence (a sheikh's tasmee'), not on self-reports. The exact scope is TBD.

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

- **Topic sections:** the stand-in data must be replaced by a published thematic Mushaf's division, with the publisher's permission.
- **Revision policy:** the numbers in [REVISION.md](REVISION.md) need trying with real huffaz.
- **Stages and tests:** how Etqan's ten stages and tests map onto Aqra's منازل (the ten stairs match the ten stages).
- **The sheikh's role:** an ongoing sheikh who follows a student, or booking any teacher, or both.
- **Free seats:** how many reserved free seats each session has.
- **Commission:** the app's commission percentage.
- **Teacher vetting:** the full acceptance procedure beyond the ijazah and interview.
- **Competitions:** their detailed design.
