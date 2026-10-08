# QA log — October 2026

A full QA and code-review pass on Aqra: iOS first, then Android. Branch `qa/2026-10`.

- Fixes go in as one focused commit each, with a regression test where practical.
- Anything visual, new, or that changes the product's behavior or the SRS algorithm is written up in
  [QA-PROPOSALS.md](QA-PROPOSALS.md) for review instead of being built.

Severity: **P0** crash, data loss or a blocked core flow · **P1** a core flow wrong or broken for many users ·
**P2** a real bug with a workaround, an accessibility failure, a secondary flow broken · **P3** polish, copy, code
quality.

## Findings

| # | Sev | Area | Description | Status | Commit |
|---|---|---|---|---|---|
| 1 | P0 | Backup | After a reinstall the sign-in survives in the keychain. If the first restore failed (offline), the upload that followed wrote every memory block from the empty device, replacing the account's backup once back online. | Fixed: restore reads from the server only; nothing is uploaded until the account's copy is merged; each upload retries the restore. Verified on the emulator (reinstall restores 1,146 ayat, plan, streak). | a6c4d93 |
| 2 | P1 | Security rules | A seat could be created without the session's `booked` count rising in the same write, so a modified client could take a seat in a full session or skip an auction. | Fixed in `firestore.rules`, with a rules test that fails on the old rule. **Not deployed.** | c2b5861 |
| 3 | P2 | Mushaf index | Switching the index to Juz' left the top rows showing surahs (the lazy list reused rows with the same ids 1–30). | Fixed; verified both ways on the simulator. | 352b2ef |
| 4 | P2 | Progress | Mastered and verified counted ayat while memorized counts every juz' equally, so mastered could read higher than memorized (juz' ʿAmma: 3% memorized, 9% mastered). | Fixed, with a unit test. | 4e983d4 |
| 5 | P2 | Rewards | Achievements earned during the wird (first revision, streak milestones) chimed and buzzed unseen behind the revision screen and were gone on return. | Fixed: a celebration waits until nothing is presented over the tabs. Verified on the SE. | 1a17546 |
| 6 | P2 | Layout (iPhone SE) | «ماذا تحفظ؟» broke "Surahs" across two lines in its segmented control, wrapped "The whole Quran", and cut the line under the headline. | Fixed; verified on the SE in English and Arabic. | 5f669e9 |
| 7 | P1 | Mushaf, tasmee' | Press-and-hold on an ayah did nothing when held about 0.8 s or longer (the natural length): no range in marking mode, and teachers and peers couldn't classify a mistake. | Fixed with a UIKit tap and long press; verified 1 s and 2 s holds, taps and page swipes. | e178a7d |
| 8 | P2 | Offline | Showing a friend a code, inviting or accepting a friend, and starting a competition spun forever offline; sign-out's 12-second limit never fired (a task group waits for every child, and Firestore's calls ignore cancelling); deleting the account offline hung. | Fixed: `withServerTimeout`, a server check before deleting, "unavailable" read as offline. Unit test for the timeout. | 1668952 |
| 9 | P3 | Copy | A fresh tasmee' code read "valid for 29 minutes". | Fixed (rounded up). | 134d127 |
| 10 | P2 | Auction (Functions) | Bidding, then booking a free seat in the same session: at settlement the bid still won — the student was charged for a second seat, their free seat overwritten, an auctioned seat wasted. | Fixed in `settle`; functions test fails on the old code. **Not deployed.** | 23589a7 |
| 11 | P0 | Account deletion | Deleting an account failed for nearly every user ("That didn't work"): the deletion batch always deleted `teacherApplications/{uid}`, which the rules refuse when there is none or it's been reviewed, so the whole batch was refused. App Store 5.1.1(v), SRS ACC-06. | Fixed: the app withdraws an application only while it waits; the account-deletion trigger deletes it in any other state. Verified on the emulator (backup and user gone, device progress kept, new anonymous account); functions test. **Function not deployed.** | c7d8e57 |
| 12 | P2 | Dark mode | The Mushaf, the wird, memorizing a portion and hearing a tasmee' stayed on light paper in dark mode: they inherited the home's forced light scheme (since 2aa512e). SRS UI-06 / A-23 say the Mushaf follows dark mode. | Fixed: the system's scheme is read at the root and given back to those screens; verified on the Max in dark mode (the app's own screens stay light). | d30de68 |
| 13 | P3 | Localization | "These pages keep slipping" joined page numbers with an Arabic comma in English and Western digits in Arabic; a teacher saw a student's whole juz' as the raw "1, 29, 30". | Fixed: locale list formatting. | 8c2b4f1 |
| 14 | P3 | VoiceOver | "Continue reading" read as "al-Fatiha, dot, page 1" (also the marking bar and a competition line). | Fixed. | 5af7c89 |
| 15 | P3 | Friends | Making an invitation code swallowed errors: offline the button just came back with nothing. | Fixed: shows the problem line. | 7fd2c3b |
| 16 | P3 | Copy (Arabic) | Zero-day streak read «٠ يوم»; Arabic takes the plural with zero («٠ أيام»). | Fixed in the catalog. | 2c7b674 |
| 17 | P3 | Code quality | Two compiler warnings: `@preconcurrency` with no effect on Apple's sign-in delegates. | Fixed; the app target now builds without warnings. | f5ce591 |
| 18 | P0 | Android: backup | Same as #1. | Fixed. | c19cdca |
| 19 | P0 | Android: account deletion | Same as #11. | Fixed; verified on the Android emulator (backup and user deleted, new anonymous account). | 9e5d81a |
| 20 | P2 | Android: offline | Same as #8 (invite, accept, competition, peer code waited forever; sign-out's timeout already worked). | Fixed with 12 s timeouts and a server check before deleting. | 701d9f3 |
| 21 | P2 | Android: progress | Same as #4. | Fixed, with a unit test. | 78f30d0 |
| 22 | P3 | Android: copy | Same as #9 (29 minutes), #13 (number lists) and #16 (zero days). | Fixed. | 47920f4, 8781cef, 84df9a8 |
| 23 | P2 | Android: daily amount | The iOS fix 1e47d22 was never ported: the unit under the number always read «صفحة في اليوم» («٢ صفحة», «٣ صفحة»). | Fixed; verified 2, 3, 4 and 13 on the emulator. | a5951f2 |

## Proposed, waiting for review

Visual, design or behavior changes, written up in [QA-PROPOSALS.md](QA-PROPOSALS.md) and not built:

| # | Sev | Area | Description | Status |
|---|---|---|---|---|
| P1 | P2 | Typography (Arabic) | «·» next to Arabic-Indic digits reads as a zero: «١٬١٣٢ آية · ٣ أجزاء» reads "30 juz'" (27 places). | Proposed: the Arabic comma in Arabic. |
| P2 | P2 | Accessibility | The iOS app ignores the system text size (342 fixed sizes); Android already scales. | Proposed: type tokens on text styles, capped. |
| P3 | P2 | Stage test | "Which ayah comes next?" shows each option's ayah number, so the answer is the next number. | Proposed: hide the options' end markers (your call, CON-01). |
| P4 | P2 | Layout (iPhone SE) | The home's main button sits under the tab bar on first sight. | Proposed: a smaller stage on short screens. |
| P5–P16 | P3 | Various | VoiceOver in revision, soft-grey contrast, all bookings listed, auction/free-seat UI, auction cut-off, stage test closed midway, stage card steadiness, undo unmarking, daily amount after Mushaf marking, reminder after the wird, anonymous backup deletion, Android string import. | Proposed. |

## Won't fix

| Area | Description | Why |
|---|---|---|
| Firestore emulator | The app's listeners sometimes go stale after long runs (sockets left closed); a relaunch fixes it. | Known emulator behavior under load (noted before in this project); not seen against a real backend. |
| Credits | The App Store can't be reached from the simulator outside Xcode, so packs don't load ("The App Store can't be reached right now", shown correctly). | Environment; buying needs Xcode's StoreKit configuration or a device. |

## What was tested

### Devices and configurations

| Device | Configuration | Notes |
|---|---|---|
| QA-1026 Pro (iPhone 17 Pro, iOS 26.5) | Arabic (ar_SA) and English; light and dark | Main device: every flow, two-role tasmee' (student) |
| QA-1026 SE (iPhone SE 3rd gen, iOS 26.5) | English and Arabic | Smallest screen; teacher's side of the two-role flows |
| QA-1026 Max (iPhone 17 Pro Max, iOS 26.5) | Arabic, English; light, dark; largest accessibility text size | Seeded edge cases; account deletion |
| QA 1026 AVD (Android 16, API 36, emulator) | Arabic (ar-SA) | Android parity run |

All online flows ran against the local Firebase emulators (project `demo-aqra`), never the production project. The
QA simulators and the AVD were created for this pass; "Aqra QA" (an earlier session's), "Aqra Shots", "Aqra Store …"
and the personal simulators weren't touched. The simulator panel needed a per-device approval while you were away,
so the app was driven by a small XCUITest runner kept in the session's scratchpad (not in the repo).

### Flows

| Flow | iOS | Android | Notes |
|---|---|---|---|
| First launch, onboarding (4 pages), launch splash | ✅ | ✅ | |
| «ماذا تحفظ؟» by juz', by surah, whole Quran, "I'm just starting" | ✅ | ✅ | #6 on the SE |
| Daily amount, plan setup (4 pages), "Not now" | ✅ | ✅ | Android #23 |
| Home: wird headline, cards, today's pages, revised outside (press and hold) | ✅ | ✅ | |
| Today's wird: reveal, stumble, show page, done, next page, back home | ✅ | ✅ | |
| Memorizing a portion, whole and partial | ✅ | — | |
| Mushaf: turning, toolbar, index (surahs, juz'), slider, colors menu | ✅ | — | #3 |
| Marking mode: tap, press-and-hold range across ayat, whole page | ✅ | — | #7 |
| Progress: shares, streak, stats, juz' grid, plan, stages, rewards, together | ✅ | — | #4 |
| Stage detail and in-app stage test, retake cooldown | ✅ | — | P3 |
| Rewards and celebrations (first revision, wird, juz', streak 7/30/100) | ✅ | ✅ | #5 |
| Daily reminder (permission prompt, allow) | ✅ | — | |
| Long streak (120 days), missed day (streak resets, no pile-up), overdue follow-ups | ✅ | — | Seeded |
| Kill and relaunch; reinstall with the sign-in kept (restore) | ✅ | — | #1 |
| Accounts on the emulator: sign in, display name, backup, sign out, sign in again | ✅ | ✅ | |
| Account deletion | ✅ | ✅ | #11, #19 |
| Teacher: session in person and by video, auctioned seat, cancel session | ✅ | — | |
| Student: book, bid (0 credits, free seat), cancel; cancellation in the inbox | ✅ | — | #10, P7 |
| In-person tasmee': marking, mistake types, pages heard, record; applied on the student's device | ✅ | — | #7 |
| Peer tasmee': code, entering it (lowercase), marking, record; applied | ✅ | — | #8, #9 |
| Friends: invite code, accept, list; race competition and scores | ✅ | — | |
| Video call: join window, join (no LiveKit server locally: "That didn't work", handled) | 🟡 | — | Media untested |
| Credits wallet (signed in): balance, packs unavailable message | 🟡 | — | No StoreKit outside Xcode |
| RTL Arabic and English | ✅ | ✅ | |
| Light and dark | ✅ | — | #12 |
| Largest Dynamic Type | ✅ checked | — | P2 (no scaling) |
| VoiceOver (accessibility tree and audits; VoiceOver itself can't run in the simulator) | 🟡 | — | #14, P5 |
| Offline | 🟡 | 🟡 | The simulator can't be taken offline per app; the waits were found by reading the code and fixed with unit-tested timeouts |

### Automated tests at the end

| Suite | Result |
|---|---|
| iOS unit tests (`xcodebuild test`, clean build) | 72 passed (70 before; +2 regression tests) |
| Firestore and Storage rules | 51 passed (+1) |
| Cloud Functions (auction, competitions, video) | 12 passed (+1, one extended) |
| Android unit tests | 64 passed, 5 skipped by design (63 before; +1) |

The iOS app builds with no warnings in its own code (2 before).

### Not tested

- Real video and audio in a call: no LiveKit server locally (DEP-05, as before).
- Buying credits: needs Xcode's StoreKit configuration or a device.
- Sign in with Apple and Google for real (only the emulator's sign-in).
- iPad, and iOS 17 and 18 (only iOS 26.5 is installed).
- Push notifications (DEP-08), and a reminder actually firing.
- **Deploys:** the rules (#2) and Functions (#10, #11) fixes are on this branch only; production keeps the old rules
  and functions until they're deployed.
