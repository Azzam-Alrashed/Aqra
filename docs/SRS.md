# Software Requirements Specification — Aqra (اقْرَأْ)

> «يقالُ لصاحِبِ القرآنِ اقرَأ وارقَ ورتِّل كما كُنتَ ترتِّلُ في الدُّنيا فإنَّ منزلتَكَ عندَ آخرِ آيةٍ تقرؤُها» — رواه أحمد

| | |
|---|---|
| **Document** | Software Requirements Specification (SRS) |
| **Product** | Aqra — Quran memorization, revision and mastery |
| **Standard** | Structured after IEEE Std 830-1998, with the requirement attributes of ISO/IEC/IEEE 29148:2018 |
| **Version** | 1.3 |
| **Date** | 2026-10-09 |
| **Baseline** | Commit `f7ac25b` ("Add the landing page") on `main`. Statuses below are as of the `full-journey` branch, after waves 2 and 3 were built, updated for the October QA proposals (`qa/proposals-2026-10`) |
| **Related documents** | [VISION.md](VISION.md) (product decisions), [REVISION.md](REVISION.md) (revision policy), [backend/README.md](../backend/README.md) (data and rules), [shared/quran/README.md](../shared/quran/README.md) (Quran sources) |

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Overall description](#2-overall-description)
3. [Specific requirements](#3-specific-requirements)
4. [Verification](#4-verification)
5. [Appendix A — Open issues](#appendix-a--open-issues)
6. [Appendix B — Status summary](#appendix-b--status-summary)

---

## 1. Introduction

### 1.1 Purpose

This document specifies the software requirements of Aqra: what the system shall do, under which constraints, and
how each requirement is verified. It consolidates the decisions recorded in [VISION.md](VISION.md) and
[REVISION.md](REVISION.md), the behavior of the code as of the baseline commit, and the requirements of the features
still to be built in release waves 2 and 3.

Its readers are the product owner, the engineers of every Aqra app (iOS now, Android and the web later), the
backend engineers, the reviewers who proofread the Mushaf, and the teachers and huffaz who will try the revision
policy.

### 1.2 Scope

Aqra helps a Quran memorizer (حافظ) through the whole journey: memorizing new portions, revising what is memorized,
and reaching lasting mastery, with teachers who hear them recite (تسميع) and confirm what they know. It is named after
the hadith above: the student's منزلة is the last ayah they reach, and the app shows that climb ayah by ayah.

The system comprises:

- **The iOS app** (SwiftUI, iOS 17+, iPhone and iPad): the Mushaf, the memorization map, the revision engine, the
  personal plan, stages and tests, rewards and competitions, the student and teacher sides of tasmee' in person, by
  video and with a peer, credits, and the seat auction.
- **The backend** on Firebase: Authentication, Cloud Firestore (in Belgium, `europe-west1`), Cloud Storage, and Cloud
  Functions for everything that must be trusted (video room tokens, purchases, the auction, competition scores,
  administration).
- **LiveKit Cloud** for live audio and video.
- **The website** (`docs/index.html`, GitHub Pages).
- **Later:** an Android app and a web app (PWA) on the same backend.

Out of scope: riwayat other than Hafs ʿan ʿĀṣim; Quran audio recitation and tafsir content; a public social network;
selling anything other than seats in tasmee' sessions; Etqan's parent dashboard (see [§2.3](#23-user-classes-and-characteristics)).

**Benefits.** The student always knows «وش علي اليوم؟» (what's mine to do today); revision is planned so what is
memorized is not lost; strength is visible on the Mushaf page itself; teachers and peers confirm memorization; and
the journey is joyful without encouraging showing off.

### 1.3 Definitions, acronyms and abbreviations

| Term | Meaning |
|---|---|
| **Ayah** (آية), pl. ayat | A verse. Aqra numbers the 6,236 ayat 0…6235 in Quran order. |
| **Surah** (سورة) | One of the 114 chapters. |
| **Juz'** (جزء) | One of the 30 parts of the Quran, as given by the official data. |
| **Hizb / rub'** (حزب / ربع) | The 60 hizbs and their 240 quarters. |
| **Mushaf** (مصحف) | The printed Quran. Aqra reproduces the 604-page Madinah Mushaf, 1441H print, 15 lines per page. |
| **Hafs** (حفص عن عاصم) | The riwayah (transmission) Aqra uses. |
| **Hafiz** (حافظ), pl. huffaz | One who memorizes the Quran; here, any user who memorizes. |
| **Manzil** (منزلة), pl. **manazil** (منازل) | A station of ascent. In Aqra the manazil are the ayat themselves; the student's manzil is the last ayah reached. Motivational only, never a claim of rank in the Hereafter. |
| **Stairs** | The ten glossy steps drawn on the home and setup screens; each step is three juz' (and one stage). |
| **Wird** (وِرد اليوم) | Today's revision plan: a fixed list of pages. |
| **Sabaq / sabqi / manzil lanes** | The hifz tradition's three lanes: new memorization (السبق), near revision (السبقي), far revision (المنزل). Aqra calls them *new portion*, *follow-up* and *rotation*. |
| **Tasmee'** (تسميع) | Reciting from memory to a listener who corrects. |
| **Sheikh / teacher** | A vetted teacher who holds tasmee' sessions. |
| **Peer** | Another Aqra user who hears a student's tasmee' informally. |
| **Ijazah** (إجازة) | A teacher's certified license to teach the Quran with a chain of transmission. |
| **Stumble** | An ayah the student hesitated on or got wrong during a revision or tasmee'. |
| **Mistake type** | A teacher's classification of a stumble (memorization error, forgetting, prompting, hesitation, لحن جلي, tajweed). |
| **Stability / half-life** | Days until the chance of recalling an ayah falls to one half. |
| **Strength** | 0…1: established-ness (stability ÷ mature stability, capped at 1) × freshness (recall probability now). |
| **Verified** | An ayah a teacher heard clean in their latest tasmee' of it. |
| **Mastered** | An ayah whose stability has reached the policy's mastery level and whose last revision was clean. |
| **Stage** (مرحلة) | One of ten curriculum stages of three juz' each (Etqan's structure), aligned with the ten stairs. |
| **Star** (نجمة) | Etqan's fixed curriculum unit, eight per juz' (240 in total), believed to equal the rub' al-hizb. |
| **Portion** | One day's new memorization: a run of ayat in the student's memorization order. |
| **Policy** | A set of tunable rules and numbers kept in one place, never buried in code (ReviewPolicy, PlanPolicy, …). |
| **Credits** | The in-app currency, bought as consumable In-App Purchases, used to bid for seats. |
| **Hold** | Credits set aside for an active bid; released if outbid, spent if the seat is won. |
| **KFGQPC** | King Fahd Glorious Quran Printing Complex (مجمع الملك فهد لطباعة المصحف الشريف). |
| **QUL** | Quranic Universal Library (qul.tarteel.ai), source of the page layout and glyph data. |
| **QCF V4** | The Complex's per-page Mushaf fonts of the 1441H print, with tajweed color layers (COLR v0 + CPAL). |
| **IAP** | Apple In-App Purchase (StoreKit 2). |
| **SFU** | Selective Forwarding Unit, the media server topology LiveKit uses. |
| **RTL** | Right-to-left layout. |

### 1.4 References

1. IEEE Std 830-1998, *IEEE Recommended Practice for Software Requirements Specifications*.
2. ISO/IEC/IEEE 29148:2018, *Systems and software engineering — Life cycle processes — Requirements engineering*.
3. [docs/VISION.md](VISION.md) — Aqra product vision (living document).
4. [docs/REVISION.md](REVISION.md) — the revision policy.
5. [backend/README.md](../backend/README.md) — data model and security rules.
6. [shared/quran/README.md](../shared/quran/README.md) — Quran text sources, licenses, checksums, verification.
7. «منصة إتقان القرآن — شرح تفصيلي للفكرة والنظام للمهندس البرمجي» (the Etqan Quran Platform document) — a
   *reference* for the full journey, not a specification. Aqra adopts from it only what the product owner agrees to.
8. Hadith source: dorar.net/hadith/sharh/116139 (Musnad Ahmad 6799); translation: sunnah.com/tirmidhi:2914.
9. Apple App Store Review Guidelines §3.1.1 (In-App Purchase), §5.1.1(v) (account deletion), §4.8 (Sign in with Apple).
10. Firebase documentation: Authentication, Cloud Firestore security rules, Cloud Functions (2nd gen), Cloud Storage.
11. LiveKit documentation: access tokens and the Swift client SDK.

### 1.5 Overview

[Section 2](#2-overall-description) describes the product's context, functions, users, environment, constraints
and release plan. [Section 3](#3-specific-requirements) lists every requirement, grouped by feature, each with an
identifier, priority and status. [Section 4](#4-verification) states how requirements are verified.
[Appendix A](#appendix-a--open-issues) lists the decisions still open and the provisional defaults adopted for them.

**Requirement attributes.** Each requirement has:

- **ID**: `AREA-NN`, stable once published.
- **Priority**: **M** must, **S** should, **C** could (MoSCoW).
- **Status**: ✅ implemented · 🟡 partial · 🔨 to build · ❓ awaiting the product owner's decision · ⛔ blocked on an
  external dependency · ⏳ deferred to a later release.
- **Source**: the decision it traces to — **V** VISION.md, **R** REVISION.md, **E** the Etqan reference adopted by
  the product owner's choice of the full journey (option C), **A** Apple or legal requirement, **P** a provisional
  default adopted in this SRS (listed in Appendix A).

---

## 2. Overall description

### 2.1 Product perspective

Aqra is a new, self-contained product. Its parts:

```
                 ┌──────────────────────────── iOS app (SwiftUI) ────────────────────────────┐
                 │ Mushaf · memorization map · revision engine · plan · stages & tests ·     │
                 │ rewards · tasmee' (student, teacher, peer) · credits · auction · account  │
                 │                                                                            │
                 │  On-device store (Application Support JSON, UserDefaults) ← works offline │
                 └───────┬───────────────┬────────────────┬───────────────┬──────────────────┘
                         │ Auth          │ Firestore      │ Functions     │ WebRTC
                         ▼               ▼                ▼               ▼
              Firebase Auth     Cloud Firestore      Cloud Functions   LiveKit Cloud (SFU)
              (anonymous,       (europe-west1)       (tokens, IAP,       ▲
               Apple, Google)        ▲               auction, scores,    │ room tokens
                                     │               admin)  ────────────┘
              Cloud Storage ─────────┘                 │
              (ijazah uploads)                 App Store Server (signed transactions)
```

**Design principles that shape the architecture:**

1. **Offline-first, device-authoritative personal progress.** What's memorized, its strength, the revision record,
   the personal plan, rewards and tests live on the device and work with no account and no network (wave 1). The
   account is a backup, restored on a new device; it is not live multi-device editing.
2. **Server-authoritative multi-party state.** Anything another person relies on — seats, bids, credits, video
   access, teacher-run competition scores, vetting — is written by security-rule-checked transactions or Cloud
   Functions, never trusted from one client.
3. **The student owns their map.** A teacher never reads a student's progress. What a teacher or peer hears is
   written into the student's account as a record; the student's app applies it.
4. **Policy, not code.** Every tunable rule lives in one policy value (see [§3.7](#37-policies)).
5. **Sacred text integrity.** Quran and hadith text is bundled unmodified from authoritative sources and verified
   by checksums and cross-checks in tests.

### 2.2 Product functions

| Area | Summary |
|---|---|
| Onboarding | Four pages: the hadith, the manazil, the features, the start of the journey. |
| Mushaf | 604 pages of the 1441H Madinah print, page-exact, with tajweed colors and topic highlights shaded by memorization strength. |
| Memorization map | Declare what's memorized by juz', surah, page or ayah; mark new portions as memorized. |
| Strength model | A half-life per ayah that grows with clean revision and shrinks with stumbles. |
| Revision engine | Today's wird: new-portion follow-ups, then the rotation through everything memorized; missed days don't pile up. |
| Personal plan | Daily new memorization amount, study days and order; today's portion; a dynamic completion date; planned vs actual. |
| Stages & tests | Ten stages of three juz'; memorization and mastery progress; in-app tests; a sheikh's stage test; stage passing. |
| Rewards | Points, streaks, personal challenges, achievements, celebrations. |
| Tasmee' | Vetted teachers; sessions in person or by video; free seats and auctioned seats; teacher marking with mistake types; peer tasmee'. |
| Social | Friends, private competitions, group khatmah, teacher-run competitions with verified scores. |
| Payments | Credits via IAP, wallet with holds, teacher earnings and manual payouts. |
| Account | Anonymous start, Apple/Google linking, backup and merge, sign-out, deletion. |
| Administration | Teacher applications and vetting, payouts, policy settings, admin claims. |

### 2.3 User classes and characteristics

| Class | Description | Access |
|---|---|---|
| **Student (anonymous)** | Every install starts here. Any age, Arabic or English UI, may know nothing of the app's terms. | All on-device features; reads teachers and sessions; can't book, bid, buy, join video or appear by name to others. |
| **Student (signed in)** | Linked Apple or Google sign-in. | Adds booking, bidding, credits, video tasmee', friends and competitions, backup across devices. |
| **Peer** | Any signed-in user hearing a friend's tasmee' with a code the friend shared. | Writes one tasmee' record into that friend's account while the code is valid. |
| **Teacher** | A signed-in user with an approved application (ijazah reviewed, interview passed), marked vetted by an administrator. Same app. | Creates sessions (in person / video, free and auctioned seats), hears students, records tasmee' and stage tests, runs competitions for their students, sees their earnings. |
| **Administrator** | Aqra staff, identified by an `admin` custom claim. | Reviews applications, vets teachers, records payouts, edits the server policy. Tools: admin scripts (CLI). |
| **Parent** | Etqan's future parent dashboard. | Out of scope for now (not adopted). |

Characteristics: users range from children (with a parent's device) to elderly huffaz; many read Arabic only; some
recite in mosques with poor connectivity; teachers may be unfamiliar with apps, so their screens must be simple.

### 2.4 Operating environment

- **iOS app:** iOS/iPadOS 17.0 or later; iPhone and iPad, every orientation; not Mac Catalyst. Built with Xcode 26,
  Swift 6, SwiftUI; project generated by XcodeGen from `apps/ios/project.yml`.
- **Backend:** Firebase project `aqra-quran`; Firestore in `europe-west1` (Belgium); Cloud Functions 2nd gen (Node.js
  22); Cloud Storage; Firebase Local Emulator Suite for development and tests (project `demo-aqra`).
- **Video:** LiveKit Cloud (self-hosting possible later).
- **Payments:** App Store (StoreKit 2); a local StoreKit configuration for development.
- **Website:** static HTML on GitHub Pages from `main:/docs`.

### 2.5 Design and implementation constraints

| ID | Constraint | Source |
|---|---|---|
| CON-01 | Quran text, layout and fonts come only from the KFGQPC (directly, or via QUL/Quran Foundation where the data is verified against the Complex's official data), Hafs only, bundled unmodified, never hand-edited or generated. | V |
| CON-02 | Every bundled Quran file is fingerprinted (SHA-256) and verified by a test; the page layout is cross-checked against the official data by a test. | V |
| CON-03 | Hadith text and its translation are quoted verbatim from their published sources and checked by SHA-256 tests. | V |
| CON-04 | Three typography layers: Quran = the Complex's fonts (Mushaf only); hadith = Amiri (OFL); the app's voice = the system font (SF Arabic). Quran fonts are never used for non-Quran text. | V |
| CON-05 | Font licenses: the KFGQPC fonts may not be modified or sold; QCF V4 bundling requires an active Quran Foundation developer account and credit; QUL resources need attribution (to confirm). | V |
| CON-06 | Digital goods are sold only through Apple IAP (consumable credits). | A, V |
| CON-07 | Account deletion is available in-app and deletes the account's data; Sign in with Apple is offered alongside Google; Apple tokens are revoked on deletion. | A |
| CON-08 | Firestore, Storage and the Cloud Functions all stay in one region, `europe-west1`; no deploy may create a resource in another region. | V |
| CON-09 | The app voice is formal Arabic (فصحى) with a natural English counterpart; Arabic is fully RTL. | V |
| CON-10 | Illustrations never depict faces or beings with souls; nothing tied to the Quran is tossed around carelessly. | V |
| CON-11 | The manazil and all competition features avoid showing off for its own sake; public standing rests only on verified evidence. | V |
| CON-12 | Every tunable rule lives in a policy value (see [§3.7](#37-policies)). | V, E |
| CON-13 | XcodeGen regeneration must never drop the signing team, display name, category or device settings kept in `project.yml`. | V |

### 2.6 User documentation

In-app copy explains every screen (headlines with one-line details); the Sources screen credits every data source as
its terms require; the website presents the product. Teacher onboarding instructions are given by the vetting team.
Developer documentation lives in the repository READMEs.

### 2.7 Assumptions and dependencies

| ID | Assumption / dependency |
|---|---|
| DEP-01 | The product owner's team proofreads all 604 pages (with and without tajweed) before release; QUL lists the V4 fonts as still under proofreading. |
| DEP-02 | Quran Foundation developer account and in-app credit before release (font bundling terms). |
| DEP-03 | The topic sections are a stand-in (QUL "Ayah theme"); a published thematic Mushaf's division with the publisher's written permission must replace them before release. |
| DEP-04 | Star (rub') boundaries need an authoritative data source (the Complex's data does not carry them). Until then, curriculum progress is reported by stage and juz'. |
| DEP-05 | A LiveKit Cloud project (URL, API key and secret) configured as Cloud Functions secrets. |
| DEP-06 | App Store Connect: the credit products, Small Business Program enrollment, and the App Store Server API key for production receipt verification. |
| DEP-07 | Firebase: Cloud Functions and Cloud Storage enabled on `aqra-quran` (Blaze plan), Storage bucket in `europe-west1`. |
| DEP-08 | Push notifications need an APNs key uploaded to Firebase; until then reminders are local notifications and server events land in an in-app inbox. |

### 2.8 Release waves (apportioning of requirements)

| Wave | Scope | Status at baseline |
|---|---|---|
| **1. The student alone** | Offline, no account: Mushaf, memorization map, revision engine, today's wird, home, progress. | Built |
| **2. The student with others** | Accounts and backup; teachers, sessions and booking; in-person tasmee'; the verified mark; video tasmee'; peer tasmee'; teacher applications. | Partly built (accounts, backup, teachers, in-person tasmee') |
| **3. The full journey** | Personal plan with new memorization and a completion date; stages, mastery and tests; rewards; competitions; credits, the seat auction, earnings and payouts; administration. | Not built |
| **Later** | Android app; web app (PWA). | Not built |

---

## 3. Specific requirements

### 3.1 External interface requirements

#### 3.1.1 User interfaces

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| UI-01 | Every screen outside the Mushaf uses the shared design language (`DesignSystem/AqraComponents.swift`): soft lavender surface, two-line headlines with the second line in brand purple, emoji in tinted rounded squares, white cards with soft shadows, floating chips, spring entrances with light haptics. | M | ✅ | V |
| UI-02 | The interface is fully localized in Arabic (RTL) and English; numbers, dates and plurals follow the locale; the Mushaf's own numerals are Arabic-Indic. Facts on one line are separated by «،» in Arabic (a middle dot beside Arabic-Indic digits reads as a zero) and «·» in English. | M | ✅ | V |
| UI-03 | Reduce Motion replaces entrance choreography and ambient motion with simple fades. | M | ✅ | V |
| UI-04 | Haptics: a light tick on choices and page turns, a firmer one on entering a new juz', success on completing the wird. | S | ✅ | V |
| UI-05 | VoiceOver and TalkBack read each Mushaf page as the official plain (Imla'i) text with ayah numbers, leaving out the ayat a revision veils or a student hid while memorizing (and saying how many are hidden); the page's taps are actions (reveal, stumble, hide and show, mark). Every control has a label. | M | ✅ | V |
| UI-06 | The Mushaf follows the system's dark mode (warm dark paper, cream ink, lighter gold). | M | ✅ | V |
| UI-07 | The app's own screens follow the system's dark mode with a very dark purple surface (not pure black), muted pastels and more prominent gold. | S | ❓ A-23 | V |
| UI-08 | Layouts adapt to iPhone and iPad in every orientation; the Mushaf shows two facing pages on a wide iPad in landscape. Below 700 pt (dp) of height, the home's stage is drawn smaller so today's wird comes up on the first screen. | M | ✅ | V |
| UI-09 | Rewards are celebrated with animation and a short, gentle sound (never on the welcome screen); sounds respect the silent switch. | S | ✅ | V |
| UI-10 | Navigation: the system tab bar (Liquid Glass on iOS 26, shrinking to the selected tab while a page scrolls down) with Home, Tasmee', Progress and Account; the Mushaf and today's wird open full screen from the home and close back to where they were opened. | M | ✅ | V |
| UI-11 | Launch: the launch screen is the lavender surface with a faint blurred hint of the arch logo, in light and dark mode (no white or black flash, no spinner). The splash continues from the hint without a seam: the logo fades in and comes into focus, the star turns in and lands with a soft haptic, the sparkles follow, and gold light swells as the logo breathes, while the Mushaf loads and the home is built beneath; then it drifts out of focus for the home's entrance. On first launch the hint fades as the welcome builds the logo. Reduce Motion cross-fades in place. The motion runs in Core Animation, so building the first screen never freezes it. | S | ✅ | V |

#### 3.1.2 Hardware interfaces

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| HW-01 | Video tasmee' uses the front camera and the microphone, asking permission with a clear purpose string, and works with audio only when the camera is off or refused. | M | ✅ | V |
| HW-02 | Peer tasmee' codes can be scanned as QR codes with the camera. | S | ✅ | P |
| HW-03 | Haptic feedback uses the Taptic Engine where present. | S | ✅ | V |

#### 3.1.3 Software interfaces

| ID | Interface | Use | Status |
|---|---|---|---|
| SW-01 | Firebase Authentication (iOS SDK 12) | Anonymous accounts; Apple and Google credentials linked to them. | ✅ |
| SW-02 | Cloud Firestore | Backup, teachers, sessions, seats, bookings, tasmee' records, applications, wallets, bids, competitions, inbox. Offline persistence on. | ✅
| SW-03 | Cloud Functions (callable, scheduled, Firestore triggers) | Video tokens, purchase redemption, bidding, auction settlement, refunds, teacher-competition scores, admin actions. | ✅
| SW-04 | Cloud Storage | Ijazah uploads for teacher applications. | ✅
| SW-05 | Google Sign-In SDK 9; AuthenticationServices | Sign-in credentials. | ✅ |
| SW-06 | StoreKit 2 | Credit packs (consumables); transaction updates; finishing after the server credits them. | ✅
| SW-07 | LiveKit Swift SDK; `livekit-server-sdk` (Functions) | Live audio/video rooms and their access tokens. | ✅
| SW-08 | UserNotifications | The daily reminder; session reminders. | ✅
| SW-09 | App Store Server Library (Functions) | Verifying signed transactions in production. | ✅

#### 3.1.4 Communications interfaces

| ID | Requirement | Status |
|---|---|---|
| COM-01 | All network traffic uses TLS (Firebase SDKs, HTTPS callable functions, LiveKit WSS/DTLS-SRTP). | ✅ |
| COM-02 | Debug builds launched with `-UseFirebaseEmulator` talk only to the local emulators (Auth 9099, Firestore 8080, Functions 5001, Storage 9199). | ✅
| COM-03 | The app opens `aqra://` links (peer tasmee' codes, friend invites). | ✅

### 3.2 Functional requirements

#### 3.2.1 Onboarding (ONB)

*Stimulus/response:* on first launch the student sees four swipeable pages and ends on «ابدأ»; afterwards the app
opens on the setup or the home.

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| ONB-01 | Onboarding is shown on first launch only and has four pages: the hadith (Ahmad's wording, «اقرَأ وارقَ» emphasized, «رواه أحمد», the Tirmidhi translation in English), the manazil, the features, and «ابدأ رحلتك». | M | ✅ | V |
| ONB-02 | There is no sign-in in onboarding; every user starts anonymously. | M | ✅ | V |
| ONB-03 | Right after onboarding the student declares what they've memorized («ماذا تحفظ؟»), then chooses a daily revision amount; "I'm just starting" skips both. Choosing to mark it in the Mushaf instead, the daily amount (when anything is marked) and the plan's offer follow the first Done or the Mushaf's closing, even after the app was closed during the marking. | M | ✅ | V |
| ONB-04 | After «ماذا تحفظ؟», a student offers to set up a personal memorization plan (or skips it). | S | ✅ | E |

#### 3.2.2 Mushaf (MUS)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| MUS-01 | Show all 604 pages of the 1441H Madinah print, 15 lines each, page-exact, from the QCF V4 page fonts and the QUL layout, drawing every word from its plain outline. | M | ✅ | V |
| MUS-02 | Surah headers in the Complex's header font; the basmala in the Hafs Smart font; ayah-end markers on a soft disc. | M | ✅ | V |
| MUS-03 | Tajweed colors tint the letters (clipped to the plain outline), with a toggle, on by default. | M | ✅ | V |
| MUS-04 | Memorized ayat sit on a soft rounded highlight in their topic section's color, its depth reflecting the ayah's strength (five steps); unmemorized ayat stay plain paper; toggle, on by default. | M | ✅ | V |
| MUS-05 | Pages turn right-to-left; the last page read is remembered and the Mushaf opens on it. | M | ✅ | V |
| MUS-06 | An index of surahs and juz' with ayah counts and the current one highlighted; a page slider. | M | ✅ | V |
| MUS-07 | Marking mode: tap toggles an ayah; press-and-hold starts a range that the next tap ends (across pages); "whole page / both pages"; juz' and surahs sheet. | M | ✅ | V |
| MUS-08 | Two facing pages on a wide iPad in landscape, odd page on the right. | S | ✅ | V |
| MUS-09 | While a new portion is being memorized, its ayat are framed on the page and the rest of the page is dimmed. | S | ✅ | E |

#### 3.2.3 Memorization map (MEM)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| MEM-01 | Declare memorization by juz', surah (setup screen), page and ayah (Mushaf marking), with a whole-Quran shortcut. Unmarking (a tap, a range or a page) can be undone for a few seconds, restoring the records exactly. | M | ✅ | V |
| MEM-02 | Each memorized ayah keeps `since`, stability, last revision, lapses and the verified mark; stored on device and reloaded, including older file versions. | M | ✅ | V |
| MEM-03 | The share of the Quran memorized counts every juz' equally (a juz' memorized in part counts by its ayat). | M | ✅ | V |
| MEM-04 | A tasmee' never marks new ayat as memorized; the student owns the map. | M | ✅ | V |
| MEM-05 | Each ayah records how it entered the map: declared, or memorized in Aqra as a new portion (with the date). | S | ✅ | E |

#### 3.2.4 Strength model (STR)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| STR-01 | Declared ayat start at the policy's declared half-life (14 days). | M | ✅ | R |
| STR-02 | A clean revision multiplies the half-life by the growth (2.5), reduced by the spacing effect; a declared ayah's first revision counts in full. | M | ✅ | R |
| STR-03 | A stumble multiplies it by the lapse factor (0.3), at least 1 day, and counts a lapse. | M | ✅ | R |
| STR-04 | Evidence weights: self 1, peer 1.25 (provisional), sheikh 1.5 (provisional); a stumble is a stumble whoever heard it; the last revision never moves backwards. | M | ✅ | R, P |
| STR-05 | Strength = min(stability ÷ mature, 1) × 2^(−days since revision ÷ stability); capped at 365 days; never zero while memorized. | M | ✅ | R |
| STR-06 | Newly memorized portions start at the plan policy's new half-life (2 days), so they appear faint and enter the follow-up lane. | M | ✅ | E, P |

#### 3.2.5 Revision engine and today's wird (REV)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| REV-01 | The daily amount (pages/day, 1–40) is chosen by the student; the suggestion covers everything memorized in about a month (2–20). | M | ✅ | R |
| REV-02 | Each day's plan takes, in order: pages due for follow-up (most overdue first), then the next rotation pages in Mushaf order, wrapping. | M | ✅ | R |
| REV-03 | The plan is fixed for the day; pages no longer memorized drop out. | M | ✅ | R |
| REV-04 | Missed days don't pile up: the rotation only moves past revised pages. | M | ✅ | R |
| REV-05 | A stumble brings the page back after 1 day, then 3, then 7 while clean. | M | ✅ | R |
| REV-06 | In-app revision veils the page's memorized ayat, reveals them one at a time, and taps on revealed ayat mark stumbles; «تم» records the page and moves to the next. | M | ✅ | V |
| REV-07 | A page revised outside the app is checked off with a long press. | M | ✅ | V |
| REV-08 | The streak counts days in a row with any revision; today not yet revised doesn't break it. | M | ✅ | V |
| REV-09 | A revision outside the app may also record the ayat stumbled on. | C | ✅ | R (open Q2), P |
| REV-10 | The rotation learns: pages that keep slipping (lapses in recent revisions, or low strength while the rest is strong) are suggested for extra follow-up; the student approves or dismisses each suggestion. | S | ✅ | V (agreed direction), R (open Q3) |
| REV-11 | Today's plan also shows today's new portion (when a plan is set) before the follow-ups. | M | ✅ | E |

#### 3.2.6 Home (HOME)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| HOME-01 | The home answers «وش علي اليوم؟»: greeting, Hijri date (Umm al-Qura), streak chip. | M | ✅ | V |
| HOME-02 | The stage: the manazil stairs climbing to the share memorized, in glowing rings, with share and strength chips. | M | ✅ | V |
| HOME-03 | The wird headline (pages left, cycle length) and one button to start or continue. | M | ✅ | V |
| HOME-04 | Cards: next tasmee' (or its cancellation), continue reading (page miniature), today's pages, the invitation to save progress (anonymous, after a first revision, snooze 7 days), what's memorized and the daily amount. | M | ✅ | V |
| HOME-05 | A card for today's new portion (from the plan) with «تم الحفظ», and the expected completion date. | M | ✅ | E |
| HOME-06 | The current stage and its progress lead to the stage's page. | S | ✅ | E |
| HOME-07 | Rotation suggestions (REV-10) and newly applied tasmee' records ("your teacher heard pages …") appear as cards. | S | ✅ | V |
| HOME-08 | An inbox badge for server events (outbid, seat won, session cancelled and refunded, application status). | S | ✅ | P |

#### 3.2.7 Progress (PRG)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| PRG-01 | Share of the Quran memorized, streak with the last seven days, ayat memorized, pages revised this week, average strength, every juz' at a glance. | M | ✅ | V |
| PRG-02 | Memorization progress and mastery progress are shown separately (e.g. 80% memorized, 45% mastered), with the verified share. | M | ✅ | E |
| PRG-03 | Stages: each of the ten with memorized %, mastered %, tests and passed state. | M | ✅ | E |
| PRG-04 | Points, achievements and personal challenges. | S | ✅ | V |
| PRG-05 | The tasmee' history: each record with who heard it (teacher or peer), when, pages heard and stumbles (with mistake types). | S | ✅ | V |

#### 3.2.8 Account, identity and backup (ACC)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| ACC-01 | Every install signs in anonymously; progress is backed up to that account from day one. | M | ✅ | V |
| ACC-02 | Sign in with Apple or Google links to the anonymous account; if the sign-in already belongs to another account, that account is used and the device's progress merged into it. | M | ✅ | V |
| ACC-03 | Backup: memorization in 25 blocks of 256 ayat and the revision record as JSON; only changed blocks are written, two seconds after a change; Firestore queues writes offline. | M | ✅ | V |
| ACC-04 | Merge: union of memorized ayat (newer revision wins, verified kept from either), revision record per CloudBackup rules. | M | ✅ | V |
| ACC-05 | Sign-out uploads first (fails safely when offline), then clears the device and returns to «ماذا تحفظ؟». | M | ✅ | V |
| ACC-06 | Account deletion deletes the backup, bookings (seats given back) and tasmee' records, revokes Apple's token, deletes the user; the device's progress stays. A student who hasn't signed in deletes their anonymous backup the same way ("Delete my backup"); the device then backs up afresh to a new anonymous account. | M | ✅ | A, V |
| ACC-07 | Sign-in is required before booking, bidding, buying credits, joining video, adding friends or applying to teach. | M | ✅ | V |
| ACC-08 | A display name the student chooses is shown to teachers, peers and friends instead of the sign-in's name or email. | S | ✅ | P |
| ACC-09 | The backup also covers the personal plan, rewards and test results; deletion removes them and the wallet, applications, friendships and competition entries. | M | ✅ | A, P |

#### 3.2.9 Settings and reminders (SET)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| SET-01 | Tajweed and topic color toggles (Mushaf menu and Account), kept app-wide. | M | ✅ | V |
| SET-02 | A daily reminder at a chosen time; explains when notifications are off in Settings. Today's is left out once today's work is done: the wird, and on a study day the new portion. | M | ✅ | E |
| SET-03 | The app's language opens the system's per-app language setting. | M | ✅ | V |
| SET-04 | Sources credits the Complex, Quran Foundation, QUL, Ayah by Ayah and Amiri. | M | ✅ | V |
| SET-05 | A reminder one hour before each booked session, and on the plan's study days a reminder for the new portion. | S | ✅ | E |

#### 3.2.10 Teachers and vetting (TCH)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| TCH-01 | Vetted teachers are listed by name with city and one line; a teacher's page lists their upcoming sessions. | M | ✅ | V |
| TCH-02 | A signed-in user applies to teach in-app: name, city, one line, riwayah, from whom they hold their ijazah, its chain or details, contact, and an upload of the ijazah (image or PDF, ≤10 MB). | M | ✅ | V |
| TCH-03 | The application shows its status (submitted, interview, approved, rejected, with the reviewer's note); an applicant can update a submitted application. | M | ✅ | V |
| TCH-04 | Only an administrator approves: approval creates `teachers/{uid}` with `vetted: true` from the application; nothing in the app can mark itself vetted. | M | ✅ | V |
| TCH-05 | A teacher edits their name, city and line in-app. | S | ✅ | V |
| TCH-06 | A teacher keeps a file per student built only from what they themselves heard: the student's records, mistakes and the teacher's private notes. | S | ✅ | E |

#### 3.2.11 Sessions and booking (SES)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| SES-01 | A vetted teacher creates a session: when (future), in person (place) or by video, free seats (1–30). | M | ✅ | V |
| SES-02 | A signed-in student books a free seat first come first served: seat, the student's copy and the count in one transaction; never more students than seats. | M | ✅ | V |
| SES-03 | A student cancels their booking; a teacher cancels a session (students see it cancelled, and the inbox message names its day and time). The Tasmee' tab lists every upcoming booking: the next in full, later ones as rows. | M | ✅ | V |
| SES-04 | A teacher edits a session's time, place and seat count (not below the seats taken). | S | ✅ | V |
| SES-05 | A session may also offer auctioned seats (see AUC). | M | ✅ | V |
| SES-06 | The seat carries the student's display name and a summary (pages memorized, whole juz') so the teacher can choose what to hear. | M | ✅ | V |

#### 3.2.12 In-person tasmee' (TSM)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| TSM-01 | The teacher opens a student's seat on the marking screen: the Mushaf on the teacher's phone, a tap marks a stumble, a button marks each page heard, «سجّل التسميع» records it into the student's account (queued offline). | M | ✅ | V |
| TSM-02 | The student's app applies each record once: a sheikh's revision of the pages heard (stumbled ayat weaken and lose the verified mark, clean ones grow by the sheikh weight and are verified), then marks it applied. | M | ✅ | V |
| TSM-03 | A long press on an ayah classifies the mistake: memorization error (default), forgetting, prompting (تلقين), hesitation, لحن جلي, tajweed. Types are stored with the record and shown to the student. | S | ✅ | E |
| TSM-04 | The teacher can record the tasmee' as a stage test for a stage, with the mistakes counted against the stage policy's threshold. | M | ✅ | E |
| TSM-05 | The student is told when a record was applied (home card, tasmee' history). | S | ✅ | V |

#### 3.2.13 Video tasmee' (VID)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| VID-01 | A video session has one LiveKit room; the teacher and the students holding a seat may join from 15 minutes before it starts until 3 hours after. | M | ✅ | V |
| VID-02 | Room tokens are issued only by a Cloud Function after verifying the caller is the session's teacher or holds a seat in it, the session is open and the time is within the window; tokens expire. | M | ✅ | V |
| VID-03 | The student's call screen shows the teacher large and the student's own preview small, with microphone, camera and leave controls. | M | ✅ | V |
| VID-04 | The teacher's marking screen shows the reciting student's video in a floating tile over the Mushaf, with the same marking as in person. | M | ✅ | V |
| VID-05 | Audio continues if the camera is off; the call reconnects after a network drop. | S | ✅ | P |
| VID-06 | LiveKit credentials are server secrets, never shipped in the app. | M | ✅ | V |

#### 3.2.14 Peer tasmee' (PEER)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| PEER-01 | A student (anonymous or signed in) creates a peer request and shows its six-character code and QR (`aqra://peer/CODE`); it expires after 30 minutes. | M | ✅ | V, P |
| PEER-02 | A signed-in friend enters or scans the code, sees the student's name, and marks stumbles and pages heard on the same marking screen as a teacher. | M | ✅ | V |
| PEER-03 | The record is written into the student's account as a peer tasmee'; rules accept it only with a valid, unexpired request of that student. | M | ✅ | V |
| PEER-04 | The student's app applies it as a peer revision (weight between self and sheikh); it never grants the verified mark. | M | ✅ | V |

#### 3.2.15 Personal memorization plan (PLAN)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| PLAN-01 | The student sets a daily new amount (¼, ½, ¾, 1, 1¼ or 1½ pages, measured in Mushaf lines), study weekdays, and the order (from the end of the Mushaf or from its beginning); the default order continues from what's already memorized. | M | ✅ | E |
| PLAN-02 | Today's portion is the next unmemorized ayat in that order, about the daily amount, ending at an ayah's end and not spilling into a new surah unless the current one ends. | M | ✅ | E |
| PLAN-03 | «تم الحفظ» marks the portion memorized (new half-life), puts its pages in follow-up, and logs the portion (date, ayat, planned and actual lines, stage, juz'). The student may mark only part of it. | M | ✅ | E |
| PLAN-04 | The expected completion date is recalculated from the remaining lines, the study days and the recent actual pace (the last 28 days, once at least 7 study days are logged), else the planned pace. | M | ✅ | E |
| PLAN-05 | Planned and actual are recorded separately; every change of amount, days or order is kept in a plan history. | M | ✅ | E |
| PLAN-06 | No portion is due on a non-study day; a missed study day doesn't double the next. | M | ✅ | E, R |
| PLAN-07 | The plan can be paused and resumed. | C | ✅ | P |

#### 3.2.16 Curriculum: stages and stars (CUR)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| CUR-01 | Ten stages of three juz' each (stage *k* = juz' 3*k*−2…3*k*), from the official juz' data, matching the ten stairs. | M | ✅ | E, V |
| CUR-02 | The student's current stage, steady through the day: the one holding the plan's next portion (whether today's is due, done or a rest day), else the one of the latest ayah memorized in Aqra (declared ayat don't move it), else the first stage not passed. | M | ✅ | E, P |
| CUR-03 | Eight stars per juz' (240) from authoritative rub' al-hizb boundaries, with position tracked inside a star (not a completed flag). | S | ⛔ DEP-04 | E |
| CUR-04 | Stage content (tajweed, meanings, tips) per stage. | C | ⛔ content | E |

#### 3.2.17 Mastery and assessments (MAS)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| MAS-01 | Mastered = stability ≥ the stage policy's mastery half-life (60 days) and the last revision clean; computed for every ayah, juz' and stage. | M | ✅ | E, P |
| MAS-02 | An in-app stage test of 10 questions drawn from the stage's memorized ayat: "what comes next?" and "which surah?", four choices each, ayat shown in the Complex's text and Hafs Smart font, unmodified (the options without their ayah-end markers, so the answer can't be read from the numbers). Score shown with the right answers. | M | ✅ | E |
| MAS-03 | The test requires the stage's ayat to be memorized; a failed test can be retaken after the cooldown (24 h). Results are kept. Left after its first answer (with a confirmation), a test counts as taken, the unanswered questions as wrong. | M | ✅ | E, P |
| MAS-04 | A sheikh's stage test is recorded by a teacher (TSM-04): passed when the mistakes are at most the allowed mistakes per page heard (1) times the pages heard. | M | ✅ | E, P |
| MAS-05 | A stage is passed when: all its ayat are memorized, mastered share ≥ 80%, in-app test ≥ 80%, and (when the policy requires it) a passed sheikh's test. Each requirement shows its state. | M | ✅ | E, P |
| MAS-06 | Passing a stage is celebrated and recorded as an achievement. | S | ✅ | V |
| MAS-07 | Every threshold above lives in `StagePolicy`; the sheikh's allowed mistakes can be set per test by the teacher. | M | ✅ | E |

#### 3.2.18 Rewards (RWD)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| RWD-01 | Points for actions (page revised in the app, outside it, heard by a peer or sheikh; portion memorized; wird completed; streak milestones), from `RewardPolicy`, kept on device, private. | S | ✅ | V |
| RWD-02 | Personal challenges the student chooses for the week or month (complete the wird N days, memorize N pages, revise a juz'), with progress and completion. | S | ✅ | V |
| RWD-03 | Achievements (first revision, first portion, first juz' memorized, streaks of 7/30/100, each stage passed, first verified page) with the date earned. | S | ✅ | V |
| RWD-04 | Small, frequent celebrations: a toast with points as they're earned; a fuller one for achievements. | S | ✅ | V |

#### 3.2.19 Social: friends and competitions (SOC)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| SOC-01 | Friends: a signed-in user shares an invite code (`aqra://friend/CODE`, 7 days); accepting creates a mutual friendship; either can remove it. | S | ✅ | V |
| SOC-02 | Private competitions among friends: a title, a metric (pages revised, days revised, ayat memorized), a start and end; members only see each other's scores; each member's app reports its own score. | S | ✅ | V |
| SOC-03 | Group goal (shared khatmah): 30 juz' parts claimed by members and marked done; the group's progress. | S | ✅ | V |
| SOC-04 | Teacher-run competitions among the teacher's students: scores are pages heard clean by that teacher within the window, computed by the server from the teacher's records only (verified evidence). | S | ✅ | V |
| SOC-05 | No public leaderboard rests on self-reports; names shown are display names; anyone can leave a competition. | M | ✅ | V |

#### 3.2.20 Credits and payments (PAY)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| PAY-01 | Credit packs are consumable IAP products (10, 30, 60 credits); buying needs a signed-in account. | M | ✅ | V |
| PAY-02 | A purchase is credited only after a Cloud Function verifies the signed transaction (App Store Server Library in production; Xcode's local StoreKit in development) and records it idempotently by transaction id; the app then finishes the transaction. | M | ✅ | V |
| PAY-03 | The wallet (balance, held) and its ledger (purchase, hold, release, spend, refund) are written only by Cloud Functions; the student sees both. | M | ✅ | V |
| PAY-04 | Unfinished transactions are redeemed again at launch. | M | ✅ | A |

#### 3.2.21 Seat auction (AUC)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| AUC-01 | A session offers reserved free seats (at least one; first come first served, not biddable) and optionally auctioned seats. | M | ✅ | V |
| AUC-02 | Auctioned seats start free: while seats remain, any bid ≥ the minimum (0) holds one. When all are held, a new bid must beat the lowest winning bid by the increment (1 credit), which outbids it. | M | ✅ | V |
| AUC-03 | Bidding holds credits; outbid holds are released at once; a bidder may raise their bid (holding the difference); ties go to the earlier bid. | M | ✅ | V |
| AUC-04 | Bidding closes before the session: 3 h before, or 30 min before for a session sooner than that (when 3 h would leave under 30 min to bid); a session less than 1 h away offers free seats only. A scheduled function settles it: winning holds are spent, seats and bookings created, teacher earnings recorded. | M | ✅ | V |
| AUC-05 | All bids go through a Cloud Function in a Firestore transaction, so a seat is never won twice. | M | ✅ | V |
| AUC-06 | Cancelling a session releases holds (before settlement) or refunds spent credits and reverses the teacher's earnings (after). | M | ✅ | P |
| AUC-07 | The student sees the current lowest winning bid, their own standing (winning / outbid), and is told when outbid or when they've won. | M | ✅ | V |
| AUC-08 | A student holds a free seat or a bid in a session, not both: with a seat, the auction isn't offered; with a bid, "Book a free seat instead" lets the bid go (its credits come back) and books the seat, in one server call. | M | ✅ | V |

#### 3.2.22 Teacher earnings and payouts (ERN)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| ERN-01 | Each won seat's price is split: the teacher earns (1 − commission) and the app keeps the commission (20%, provisional). | M | ✅ | V, P |
| ERN-02 | A teacher sees their earnings, payouts and the balance due, entry by entry. | M | ✅ | V |
| ERN-03 | Payouts are made by bank transfer and recorded by an administrator. | M | ✅ | V |

#### 3.2.23 Notifications and inbox (NTF)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| NTF-01 | Server events (outbid, seat won, refund, session cancelled, application status, peer/teacher record) are written to the user's inbox and shown in-app. | S | ✅ | P |
| NTF-02 | Local notifications for the daily wird, the new portion on study days and booked sessions; never more than one a day for the wird. On iOS the wird's are dated, two weeks ahead, and set again as the app is used; on Android the reminder checks when it goes off. | S | ✅ | E |
| NTF-03 | Push notifications for inbox events once an APNs key is configured. | C | ⛔ DEP-08 | P |

#### 3.2.24 Administration (ADM)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| ADM-01 | Administrators are users with the `admin` custom claim, granted by a script with service credentials. | M | ✅ | E |
| ADM-02 | Admin tools: list applications, move one to interview, approve (creating the vetted teacher) or reject with a note; record a payout; edit the server policy (`config/policy`). | M | ✅ | E |
| ADM-03 | A teacher's vetting can be revoked (vetted false), which hides them and stops new sessions. | S | ✅ | P |

#### 3.2.25 Website (WEB)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| WEB-01 | A static landing page in Arabic with an English toggle, real screenshots, the sources, for GitHub Pages. | M | ✅ | V |
| WEB-02 | The page describes the full journey once it ships (plan, stages, video and peer tasmee'). | C | ✅ | P |

#### 3.2.26 Other platforms (PLT)

| ID | Requirement | Pri | Status | Src |
|---|---|---|---|---|
| PLT-01 | An Android app on the same backend and data rules. | S | 🟡 (`apps/android` does everything the iOS app does, video calls included, except buying credits; it isn't registered in Firebase yet) | V |
| PLT-02 | A web app (PWA) on the same backend. | S | ⏳ | V |
| PLT-03 | Ayah numbering, scheduling, the strength model and manazil are platform-neutral (documented here and in REVISION.md, tested on iOS). | M | ✅ | V |

### 3.3 Performance requirements

| ID | Requirement | Status |
|---|---|---|
| PERF-01 | The Quran data loads off the main thread in under 3 s on a recent iPhone (test `loadsQuickly`). | ✅ |
| PERF-02 | Page turns are smooth (60 fps); word outlines are cached for the 12 most recent pages only. | ✅ |
| PERF-03 | Ambient animation renders on the GPU (`drawingGroup`) and pauses off screen; idle CPU under 20%. | ✅ |
| PERF-04 | Today's plan and the portion are computed in under 50 ms for a full Quran memorized. | ✅
| PERF-05 | A bid round-trip (callable function) completes in under 2 s on a good connection. | ✅
| PERF-06 | Video calls target ≤ 300 ms one-way latency within the Gulf region (LiveKit Cloud). | ⛔ DEP-05 |

### 3.4 Logical database requirements

#### On the device (Application Support)

| File | Content |
|---|---|
| `memorization.json` (v2) | Each memorized ayah: since, stability, last revision, lapses, verified, when it was learned in Aqra, its last stumble. |
| `revision.json` (v1) | Daily amount, rotation cursor, follow-ups, today's plan, history (last 1,000), days revised, days the whole wird was done. |
| `plan.json` | The personal plan, its history of changes, and the portions log (planned vs actual). |
| `rewards.json` | Points, events, achievements, challenges. |
| `assessments.json` | In-app test results and sheikh's stage tests applied. |
| UserDefaults | Onboarding seen, declared, last page, toggles, reminder, sounds, snoozes, dismissed suggestions, applied record ids. |

#### In Firestore

| Path | Writer | Reader |
|---|---|---|
| `users/{uid}` (`displayName`, + `memory/block-NN`, `revision/state`, `journey/state`) | owner | owner |
| `users/{uid}/bookings/{sessionId}` | owner (free seat) or functions (won seat) | owner |
| `users/{uid}/tasmee/{id}` | the vetted teacher with a seat, or a peer with a valid request; owner sets `appliedAt` | owner, writer |
| `users/{uid}/inbox/{id}` | functions | owner |
| `teachers/{uid}` | admin (create, vetted), owner (name, city, line) | signed in |
| `teachers/{uid}/students/{studentUid}` (+ notes) | the teacher | the teacher |
| `teacherApplications/{uid}` | owner (while submitted), admin (status, note) | owner, admin |
| `sessions/{id}` (+ `seats/{uid}`, `bids/{uid}`) | teacher; students (free seats); functions (bids, won seats, auction counts) | signed in (seats and bids: their owner and the teacher) |
| `peerRequests/{code}` | owner | signed in |
| `friendInvites/{code}`, `friendships/{a_b}` | owner / the one accepting | by code / members |
| `competitions/{id}` (+ `members/{uid}`, `parts/{juz}`) | owner, members (own score, parts), functions (teacher scores) | members |
| `wallets/{uid}` (+ `ledger/{id}`), `purchases/{transactionId}` | functions | owner |
| `teacherBalances/{uid}` (+ `entries/{id}`) | functions, admin | the teacher, admin |
| `config/policy` | admin | signed in |

#### In Cloud Storage

| Path | Writer | Reader |
|---|---|---|
| `ijazahs/{uid}/{file}` (image/PDF, ≤10 MB) | owner | owner, admin |

### 3.5 Design constraints and standards compliance

- Swift 6 strict concurrency; `@Observable` stores on the main actor; plain-value models with no Firebase types so
  rules are unit-testable.
- String catalogs (`Localizable.xcstrings`) with Arabic plural forms (zero/one/two/few/many/other where needed).
- Firestore security rules are the access-control specification and are covered by emulator tests.
- Cloud Functions are written in TypeScript and tested on the emulators.

### 3.6 Software system attributes

| ID | Attribute | Requirement | Status |
|---|---|---|---|
| ATT-01 | Integrity (sacred text) | Tests fail the build if any Quran file, the page fonts' manifest, the hadith or its translation changes, or if the layout diverges from the official data. | ✅ |
| ATT-02 | Reliability | Writes to the device are atomic; a crash never loses more than the last 300 ms of marking. Backups retry; restores merge, never overwrite blindly. | ✅ |
| ATT-03 | Availability | All personal features work offline; online features explain when the connection is needed. | ✅ |
| ATT-04 | Security | Least-privilege rules; credits, bids, tokens and vetting only through server code; secrets never in the app. | ✅
| ATT-05 | Privacy | A teacher never reads a student's progress; anonymous users are never shown by name; data deletable in-app; data stays in Saudi Arabia (Firestore). | ✅ |
| ATT-06 | Maintainability | Policies in one place; features in their own folders; every store has tests. | ✅ |
| ATT-07 | Portability | Platform-neutral data formats (ayah numbers, JSON snapshots, Firestore schema) documented here. | ✅ |
| ATT-08 | Accessibility | VoiceOver and TalkBack labels and actions; Dynamic Type up to Accessibility 2 on iOS (the Mushaf's own chrome and composed pictures keep their sizes), font scaling on Android; Reduce Motion; text contrast at WCAG AA (the soft grey is #6C6383). | ✅ |
| ATT-09 | Localizability | No user-facing string outside the catalog; architecture ready for Urdu, Indonesian, Turkish, French. | ✅ |

### 3.7 Policies

Every number below is a default, kept in one place in code, and open to tuning with real huffaz and sheikhs.

#### ReviewPolicy (`Revision/RevisionEngine.swift`)

| Field | Default | Meaning |
|---|---|---|
| declaredStability | 14 d | Half-life of declared ayat. |
| growth | 2.5 | Clean-revision multiplier. |
| lapseFactor | 0.3 | Stumble multiplier. |
| minStability / maxStability | 1 d / 365 d | Bounds. |
| matureStability | 90 d | Full color. |
| followUpDays | 1, 3, 7 | Follow-up after a stumble or a new portion. |
| sheikhWeight | 1.5 | Weight of a sheikh's clean revision. |
| peerWeight | 1.25 | Weight of a peer's clean revision. |

#### PlanPolicy (`Plan/PlanPolicy.swift`)

| Field | Default | Meaning |
|---|---|---|
| amountOptions | 4, 8, 11, 15, 19, 23 lines | ¼ … 1½ pages. |
| defaultAmount | 8 lines | ½ page a day. |
| defaultStudyDays | every day but Friday | |
| newStability | 2 d | Half-life of a newly memorized ayah. |
| paceWindowDays / minPaceDays | 28 / 7 | Recent-pace window and the minimum logged study days to use it. |

#### StagePolicy (`Curriculum/StagePolicy.swift`)

| Field | Default | Meaning |
|---|---|---|
| masteryStability | 60 d | Mastered at this half-life with a clean last revision. |
| requiredMemorized | 100% | Share of the stage memorized. |
| requiredMastered | 80% | Share of the stage mastered. |
| testQuestions / testPassScore | 10 / 80% | In-app test. |
| retestCooldown | 24 h | |
| sheikhTestRequired | true | |
| allowedMistakesPerPage | 1 | Sheikh's test threshold (per page heard), adjustable per test. |

#### RewardPolicy (`Rewards/RewardPolicy.swift`)

| Event | Points |
|---|---|
| Page revised in the app / outside / heard by a peer / heard clean by a sheikh | 2 / 1 / 3 / 5 |
| Portion memorized | 5 per page-equivalent (min 2) |
| Wird completed | 5 |
| Streak of 7 / 30 / 100 days | 20 / 50 / 100 |
| Stage passed | 100 |

#### AuctionPolicy (`config/policy` on the server, mirrored in Functions defaults)

| Field | Default |
|---|---|
| minFreeSeats | 1 |
| minBid | 0 credits |
| minIncrement | 1 credit |
| biddingClosesBeforeHours | 3 |
| lateBiddingClosesBeforeMinutes | 30 (a session sooner than 3 h 30 min) |
| minAuctionLeadMinutes | 60 (sooner: free seats only) |
| commissionRate | 0.20 |
| creditPacks | `aqra.credits.10` → 10, `aqra.credits.30` → 30, `aqra.credits.60` → 60 |

#### Video and peer

| Field | Default |
|---|---|
| joinOpensMinutesBefore / joinClosesHoursAfter | 15 / 3 |
| tokenTTLHours | 3 |
| peerRequestMinutes | 30 |
| friendInviteDays | 7 |

---

## 4. Verification

| Method | Covers |
|---|---|
| **Unit tests** (Swift Testing, `AqraTests`) | Quran data integrity and layout cross-check, strength model, revision engine, memorization store, backup encoding and merge, tasmee' models and application, plan and portion computation, completion date, stages and mastery, test generation, rewards, auction and wallet value types. |
| **Snapshot renders** (`WelcomeSnapshotTests`, `AppIconRenderTests`) | Visual review of key screens and the icon. |
| **Security-rules tests** (`backend/test`, Firestore emulator) | Every collection's read/write rules. |
| **Function tests** (`backend/functions/test`, emulators) | Video tokens, purchases, bidding, settlement, refunds, teacher-competition scores, admin actions. |
| **Simulator walkthroughs** | Two roles on two simulators against the emulators (see backend/README.md). |
| **Human review** | A qualified hafiz proofreads all 604 pages with and without tajweed; real huffaz and sheikhs try the policies. |

Each requirement's status in [§3](#3-specific-requirements) is ✅ only when its behavior is in the code and covered
by at least one automated test or, for pure UI, a simulator walkthrough.

---

## Appendix A — Open issues

Decisions not yet settled by the product owner. Where a feature needed an answer to be built, the provisional
default adopted is given; every one lives in a policy and can be changed without rewriting anything.

| # | Question | Provisional default | Where |
|---|---|---|---|
| A-1 | Topic sections from a published thematic Mushaf (and permission). | QUL "Ayah theme" stand-in. | DEP-03 |
| A-2 | Revision numbers (14 d, ×2.5, ×0.3, 1/3/7, 90 d). | As in REVISION.md. | ReviewPolicy |
| A-3 | Revisions outside the app: record stumbles too? | Optional: a page can be checked off clean (long press) or with stumbles. | REV-09 |
| A-4 | The rotation: adapt by itself or suggest? | Suggest; the student approves. | REV-10 |
| A-5 | Peer weight. | 1.25 (between self 1 and sheikh 1.5). | ReviewPolicy |
| A-6 | Should a sheikh hearing an undeclared ayah clean mark it memorized? | No. | MEM-04 |
| A-7 | How Etqan's stages map onto the manazil. | Stage *k* = juz' 3*k*−2…3*k* = the *k*-th stair; the current stage holds the plan's next portion (CUR-02). | CUR-01/02 |
| A-8 | Star boundaries (240 rub'). | Not built until an authoritative source is chosen. | DEP-04 |
| A-9 | Mastery definition. | Half-life ≥ 60 d and a clean last revision; "verified" shown separately. | MAS-01 |
| A-10 | Stage pass weights. | All requirements must hold (no weighting): 100% memorized, 80% mastered, test ≥ 80%, sheikh's test passed. | MAS-05 |
| A-11 | Mistake types and weights. | Six types recorded; weights all 1 for now. | TSM-03 |
| A-12 | Daily new amount unit. | Mushaf lines (15 per page). | PLAN-01 |
| A-13 | Default memorization order. | Continue from what's memorized: from the beginning when more of juz' 1 than of juz' 30 is memorized, otherwise from the end (where most begin). | PLAN-01 |
| A-14 | Free seats per session. | At least one; the teacher chooses. | AUC-01 |
| A-15 | Commission. | 20%. | ERN-01 |
| A-16 | Credit packs and prices. | 10 / 30 / 60 credits; App Store price tiers set in App Store Connect. | PAY-01 |
| A-17 | Bidding close. | 3 h before the session; for a session sooner than 3 h 30 min, 30 min before it; under 1 h away, no auctioned seats (decided 2026-10-09). | AUC-04 |
| A-18 | Teacher vetting beyond ijazah and interview. | Application → interview → approval by an administrator. | TCH-02/04 |
| A-19 | Competition scope. | Personal challenges, friends' competitions, group khatmah, teacher-run (verified). No public leaderboard. | SOC |
| A-20 | Points values. | RewardPolicy table. | RWD-01 |
| A-21 | Push notifications. | Inbox + local notifications until an APNs key is configured. | NTF-03 |
| A-22 | Cloud Functions region. | `europe-west1`, beside Firestore and Storage (the Middle East regions are refused for this project). | DEP-07 |
| A-23 | Dark mode for the app's own screens. The redesigned look (glossy stairs, glow rings, white cards) was built light-only, its palette giving light and dark the same values; a dark palette for it has not been designed. | Not built: the Mushaf follows the system's dark mode, the rest stays light until a dark palette is reviewed. | UI-07 |
| A-24 | Credit packs' prices and a credit's value in money (for payouts). | Prices in `Credits.storekit` are placeholders for testing; set them in App Store Connect. Payouts are recorded in credits. | PAY-01, ERN-03 |
| A-25 | A competition's metric for "days revised" counts days with any revision; "pages revised" counts pages recorded, so a page revised twice counts twice. | As stated. | SOC-02 |

---

## Appendix B — Status summary

**At the baseline** (`f7ac25b`): wave 1 complete; wave 2 had accounts, backup, teachers, sessions, booking and
in-person tasmee'; wave 3 not started.

**Built on the `full-journey` branch** (2026-10-07): every 🔨 requirement above except those marked otherwise.
What remains, and why:

| Requirement | Status | Why |
|---|---|---|
| UI-07 dark mode for the app's own screens | ❓ | Needs a dark palette for the redesigned look, reviewed by the product owner (A-23). |
| CUR-03 stars, CUR-04 stage content | ⛔ | Need an authoritative source of the rub' boundaries, and authored content (DEP-04). |
| NTF-03 push notifications | ⛔ | Needs an APNs key in Firebase (DEP-08); messages arrive in the in-app inbox meanwhile. |
| PERF-06 video latency | ⛔ | Needs the LiveKit Cloud project (DEP-05). |
| PLT-01 Android | 🟡 | Built in `apps/android`. Buying credits waits for the server to verify Google Play purchases; release needs the app registered in Firebase (its SHA-1 for Google sign-in) and Apple's web sign-in. |
| PLT-02 web app | ⏳ | After the iOS release, as planned. |

**Before release** (unchanged dependencies): proofreading of all 604 pages (DEP-01); Quran Foundation account and
credit (DEP-02); the thematic Mushaf's permission (DEP-03); LiveKit Cloud keys (DEP-05); App Store Connect
products, Apple's root certificates in `backend/functions/certs` and the app's App Store id (DEP-06); Cloud
Functions and Storage enabled on `aqra-quran` (DEP-07).

### Where each area lives

| Area | iOS (`apps/ios/Aqra`) | Backend (`backend`) | Tests |
|---|---|---|---|
| Mushaf | `Mushaf/` | — | `MushafTests` |
| Memorization, strength | `Memorization/` | — | `MemorizationTests`, `RevisionTests` |
| Revision, rotation | `Revision/` | — | `RevisionTests`, `JourneyTests` |
| Plan | `Plan/` | `users/{uid}/journey` | `JourneyTests` |
| Stages, mastery, tests | `Curriculum/` | — | `JourneyTests` |
| Rewards | `Rewards/` | — | `JourneyTests` |
| Account, backup, inbox | `Account/` | `firestore.rules` | `CloudSyncTests`, `JourneyTests`, rules tests |
| Teachers, sessions, tasmee', peer, video | `Tasmee/` | `firestore.rules`, `storage.rules`, `functions/src/video.ts` | `TasmeeTests`, rules, functions tests |
| Friends, competitions | `Social/` | `firestore.rules`, `functions/src/competitions.ts` | `SocialTests`, rules, functions tests |
| Credits, auction, earnings | `Credits/` | `functions/src/credits.ts`, `auction.ts`, `wallet.ts` | `TasmeeTests`, rules, functions tests |
| Administration | — | `scripts/admin.mjs` | rules tests |
