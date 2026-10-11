# iOS and Android, side by side

What each app does, behavior by behavior, so a student can move between the two and find the same Aqra. The
Android app is the iOS app's twin: the same Firestore documents, backup rows, journey JSON and policy constants
(`docs/SRS.md` has the requirements; this table says where each platform stands). Kept here rather than under `docs/`,
which is the published website.

Status: ✅ the same · ≈ the same behavior in the platform's own form · ⚠️ a gap or a difference · ❌ not there.
"Checked" is the last date each row was tried on a device or simulator of both platforms, or verified in code.

Last pass: 2026-10-10 (workstream WS8, Android on an emulator against the Firebase emulators, in Arabic and English).

## Onboarding and setup

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Four onboarding pages (hadith, منازل, features, start); shown once | ✅ | ✅ | |
| «ماذا تحفظ؟» by juz', surah, page, ayah or the Mushaf; "just starting" | ✅ | ✅ | |
| Daily revision amount after declaring; the plan's offer; back a step | ✅ | ✅ | |
| Marking in the Mushaf during setup, then the amount and the plan, even after the app was closed | ✅ | ✅ | |
| Launch screen and splash animation | ✅ | ❌ | Android opens on the home; no splash choreography (UI-11 is an iOS row) |

## Mushaf

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| 604 page-exact pages from the Complex's fonts and the QUL layout, right-to-left | ✅ | ✅ | Android draws with its own font reader, cross-checked against CoreText in the tests |
| Tajweed colors and topic highlights shaded by strength; toggles | ✅ | ✅ | |
| Last page read remembered; the Mushaf opens on it | ✅ | ✅ | |
| Two facing pages on a wide screen in landscape (≥ 900 pt/dp), odd on the right | ✅ | ✅ | |
| Rotating keeps the page (the left, even page too) | ✅ | ✅ | Fixed in WS8 (`MushafPaging`, test `rotatingKeepsThePage`); before, rotating read another spread and wrote it down as the page read |
| Index of surahs and juz'; page slider | ✅ | ✅ | |
| Marking mode: tap, press-and-hold ranges, whole page / both pages, juz' and surahs, undo for a few seconds | ✅ | ✅ | |
| Dark mode follows the system (warm dark paper) | ✅ | ✅ | |
| Status bar comes back after the Mushaf or a revision | ✅ | ✅ | Fixed in WS8 (`SystemBars` restores it on leaving) |
| Closing the Mushaf | swipe down (not while marking) | back gesture or the home button | The owner's rule keeps the Mushaf a button on Home on both |

## Memorization and strength

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Per-ayah record (since, stability, last revision, lapses, verified, how it entered the map); file versions read back | ✅ | ✅ | Same JSON |
| Half-life model: declared 14 days, growth 2.5 with spacing, lapse 0.3, evidence weights | ✅ | ✅ | Policy constants shared |
| Share of the Quran counts every juz' equally | ✅ | ✅ | |

## Revision (today's wird)

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Follow-ups first, then the rotation through everything memorized, whole pages in Mushaf order; missed days don't pile up | ✅ | ✅ | `scheduleParityFixture` read by both suites |
| Veil and reveal ayah by ayah; tap a revealed ayah to mark a stumble; show page; done moves to the next page | ✅ | ✅ | |
| A page revised outside the app, with its stumbles | ✅ | ✅ | |
| Leaving a revision with progress (ayat revealed, or stumbles marked) asks «تخرج دون تسجيل؟» | ✅ | ✅ | WS9 on iOS (the X), WS8 on Android (the X and back). A page logged from outside asks only once stumbles are marked |
| A revision survives the process being killed in the background | n/a (SwiftUI state lives with the scene) | ✅ | WS8: the page, what's revealed and the stumbles are saved with the activity, and the wird comes back open |
| «سمّع بصوتك»: on-device speech model follows the recitation, reveals words, marks stumbles and prompts | ✅ WhisperKit (Core ML) | ✅ ONNX Runtime | Same model, exported to ONNX and quantized for Android; the models download from Storage on first use |
| Rotation advice (pages to add or rest) | ✅ | ✅ | |

## Personal plan and memorizing

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Daily amount, study days, order; today's portion; completion date; planned vs actual; pause | ✅ | ✅ | |
| Memorize screen: portion framed, rest dimmed; hide ayat; count repetitions; «حفظته» / part of it | ✅ | ✅ | |
| Leaving the memorize screen with progress (repetitions, hidden ayat, choosing the end) asks first | ✅ | ✅ | WS8 |
| Hidden ayat, the chosen end and the repetition count survive the process | n/a | ✅ | WS8 |

## Stages, tests, rewards

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Ten stages of three juz'; memorization and mastery progress; in-app test; a teacher's stage test | ✅ | ✅ | Star (rub') boundaries missing on both (DEP-04) |
| Leaving an in-app test asks first | ✅ | ✅ | |
| Points, streaks, challenges, achievements, celebrations with a soft chime | ✅ | ✅ | Android's chime: `rewards/Chime.kt` |
| Reduce Motion: fades instead of choreography | ✅ | ✅ | Android reads the animator duration scale |

## Tasmee'

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Vetted teachers; sessions in person or by video; free seats; auctioned seats; bookings; cancellations shown | ✅ | ✅ | |
| Video call (LiveKit): camera and microphone asked for; the call goes on without either | ✅ | ✅ | Real-device audio test still open on both (owner) |
| A camera turned off shows the person's initial, not its last frame | ✅ | ✅ | WS9 on iOS (it kept the frozen frame) |
| Before a call opens, its button says when: today, tomorrow, the weekday or the date, and the time | ✅ | ✅ | WS9 |
| Report anyone shown by name (teacher, call, friend, competitor, a teacher's student); block on the device | ✅ | ✅ | WS9; `reports/{id}` needs the rules deployed (owner) |
| Screen sharing | ❌ | ❌ | Never; WS8 removes LiveKit's media-projection service and permission from the Android manifest so Play doesn't ask about it |
| Teacher's marking: pages heard, stumbles, mistake types, stage test; the student's own app applies it | ✅ | ✅ | |
| A marking under way survives the app being killed in the background | n/a | ✅ | WS8: kept in a small file per student, back when the same student is opened; deleted once recorded or left |
| Peer tasmee' by code and QR; QR scanning | ✅ | ✅ | Android scans with ML Kit's code scanner; says so when the device can't |
| Teacher application with ijazah upload | ✅ | ✅ | |
| Session reminders an hour before | ✅ local notifications | ✅ alarms | Android: `setAndAllowWhileIdle` since WS8 (was a 10-minute window, deferred by Doze) |

## Social

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Friends by invitation code and link (`aqra://`); remove a friend | ✅ | ✅ | |
| Why an invitation code couldn't be made (offline, refused) | ✅ (7fd2c3b) | ✅ | Ported in WS8 |
| Private competitions, group khatmah, teacher-run competitions with verified scores | ✅ | ✅ | |

## Credits and seats

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Wallet, balance, holds; bidding; outbid and won; a teacher's earnings | ✅ | ✅ | |
| Buying credits | ✅ App Store (StoreKit 2) | ❌ | The server verifies App Store purchases only (CON-06). The wallet page explains it; the bid sheet's «buy credits» link is hidden since WS8 (`Features.BUY_CREDITS`) |

## Account

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Anonymous start; backup to Firestore; merge on sign-in; restore on a new device | ✅ | ✅ | Same documents and rows |
| Sign in with Google | ✅ | ✅ | Android needs the Play signing key's SHA-1 in the Firebase project (owner) |
| Sign in with Apple | ✅ | ❌ hidden | Firebase's web flow needs the Apple Services ID (owner). Hidden since WS8 (`Features.APPLE_SIGN_IN`); turning it on brings the button back |
| Sign out; delete the account and its data; delete the backup alone | ✅ | ✅ | |
| In-app inbox for server events | ✅ | ✅ | |
| Help and contact, privacy policy, and the people blocked, in Account | ✅ | ✅ | WS9 |
| Crash reports | Apple's (from those who share them) and MetricKit kept on the phone | Play's Android vitals | Q7: no crash service, nothing leaves the one region |
| Language switch in the app | system settings | ✅ in the app (per-app locales, kept on Android 12 and older too) | |

## Reminders

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Daily reminder of today's wird at the chosen time; mentions the new portion on study days; withdrawn once today's work is done | ✅ 14 dated notifications | ✅ one alarm, set again each time | |
| Refreshed on every launch and resume | ✅ | ✅ | WS8 (`MainActivity.onResume` → `DailyReminder.refresh`); test `dailyReminderReschedulesOnLaunch` |
| Follows a change of time zone or clock | ✅ (calendar triggers) | ✅ | WS8: `TIMEZONE_CHANGED` and `TIME_SET` set the alarm again |
| Survives a restart | ✅ | ✅ | `BOOT_COMPLETED` |
| Delivered while the device dozes | ✅ | ≈ | `setAndAllowWhileIdle` is inexact (a few minutes), without the exact-alarm permission |

## Look, layout, language

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| The onboarding's design language on every screen (two-line headlines, cards, chips, BrandButton) | ✅ | ✅ | |
| Tab bar | system Liquid Glass, minimizes on scroll | floating white capsule | The owner's rule is about keeping the system bar on iOS |
| The app's own screens in dark mode | ❓ (UI-07) | ❌ light only | Open on both. iOS keeps the system chrome light over them since WS9 |
| Arabic (RTL) and English; «،» / «·» between facts; plurals | ✅ | ✅ | |
| Arabic-Indic digits in dates | ✅ | ✅ | Fixed in WS8 (`DecimalStyle.of(locale)`; test `arabicDatesUseArabicDigits`); numbers were already right |
| Keyboard never covers a field in a sheet | ✅ | ✅ | WS8: `AqraSheet` pads for the keyboard |
| Separators not read aloud by VoiceOver / TalkBack | ✅ (5af7c89) | ✅ | Ported in WS8 (`FactsText`), on five lines |
| Page read aloud as the plain text with ayah numbers; veiled ayat left out | ✅ | ✅ | |
| Phone and tablet, every orientation; content no wider than 560 pt/dp | ✅ iPhone + iPad | ✅ | |
| Haptics | ✅ | ✅ | |

## Release

| Behavior | iOS | Android | Notes |
|---|---|---|---|
| Debug builds talk to the emulators by default | needs `-UseFirebaseEmulator` | ✅ default since WS8 (`-Paqra.production` for the real project) | A plain Android debug build used to talk to production |
| A release can't ship without its Firebase config or pointed at the emulators | ✅ `check-release-inputs.sh` (WS9, also the 604 fonts) | ✅ `checkReleaseConfig` (WS8) | CI passes `-Paqra.ciRelease` for its compile check |
| Signing | Xcode team 6QYT6GJB4Z | `keystore.properties` (owner's upload key; ⏸ not created yet) | |
| Store bundle | archive | `bundleRelease` with ABI, density and language splits | Size per ABI in the WS8 report |
| Store listing | filled in, not submitted | ❌ not on Play | Owner's decision |
