# Aqra — Android

The Android app: Kotlin and Jetpack Compose (AGP 9.4, Kotlin 2.4, compileSdk 37, minSdk 26). It is the iOS app's
twin and uses the same account layout (Firestore documents, backup rows, journey JSON), so a student can move
between the two.

## Setup

- JDK 17 or newer and the Android SDK (`local.properties` holds `sdk.dir`).
- The 604 Mushaf page fonts: `scripts/fetch-mushaf-fonts.sh` from the repository root. The build bundles
  `shared/quran` as the app's assets, untouched, and warns when the fonts are missing.
- Firebase: put the Android app's `google-services.json` in `app/` (it isn't in git). Without it the app runs with
  accounts turned off. Google sign-in needs the signing key's SHA-1 in the Firebase project; Apple sign-in uses
  Firebase's web flow and needs the Apple provider's Services ID.

## Building and testing

```
./gradlew -PuseFirebaseEmulator :app:testDebugUnitTest :app:assembleDebug   # tests, and a debug build for the local emulators
./gradlew -PuseFirebaseEmulator :app:installDebug                           # install it on the running AVD
./gradlew :app:assembleRelease                                               # the release build, in a Gradle run of its own
```

`-PuseFirebaseEmulator` makes a debug build talk only to the local emulators (`npm run emulators` in `backend/`,
project `demo-aqra`), reached from the Android emulator at 10.0.2.2. Video calls there also need a local LiveKit
server (`livekit-server --dev`, see backend/README.md); the app reaches it at 10.0.2.2 as well.

**A debug build without the flag talks to the production project** as soon as `google-services.json` is present:
build that way only when production is what you mean. Never put the release task in the same Gradle run as the flag:
the flag leaves the google-services plugin out, so that release would ship with accounts off.

The Mushaf is drawn by the app's own font reader (WOFF2, TrueType, COLR/CPAL, GPOS kerning, and the Unicode bidi
algorithm for the text fonts). On a Mac, the tests compare it with CoreText, the engine the iOS app draws with:

```
swiftc -O tools/coretext-reference.swift -o build/coretext-reference
build/coretext-reference ../../shared/quran build/coretext
```

Then `testDebugUnitTest` checks every glyph of every page font, every word of every page, the basmala, the surah
headers and every ayah's words in Hafs Smart against those tables (they're skipped without them).

## Tools

- `tools/import-ios-strings.py`: regenerates `strings_ios.xml` (English and Arabic) from the iOS string catalog.
  Android-only strings live in `strings.xml`.
- `tools/render-icon.sh`: renders the launcher icon from the iOS logo code.

## Not on Android yet

- Buying credits: the server verifies App Store purchases only. The wallet, bidding and earnings work.

## Google Play Data safety (draft, not submitted)

The answers for Play Console's Data safety form, matching `docs/privacy.html` and the iOS privacy labels
(`apps/ios/AppStore/README.md`). Not submitted: the app isn't on Google Play yet.

- **Does the app collect or share user data?** Collects; shares none. All data is encrypted in transit (TLS), and
  users can request deletion in the app (Account, Delete account; or Delete my backup without signing in).
- **Collected, all for app functionality, none optional except where noted, none processed ephemerally:**

| Category: type | What | Optional |
|---|---|---|
| Personal info: Name | The sign-in name and the display name shown to teachers and friends; a teacher's application | Yes (sign-in) |
| Personal info: Email address | Sign in with Google or Apple; a teacher's application may give one | Yes (sign-in) |
| Personal info: Phone number | A teacher's application may give one | Yes |
| Personal info: User IDs | The Firebase account (anonymous from the first launch) | No |
| Financial info: Purchase history | Credit packs bought (Google Play Billing, once added) | Yes |
| Financial info: Other financial info | A teacher's earnings from booked seats and the payouts recorded; no bank details | Yes |
| Photos and videos: Photos | Copies of a teacher's ijazah | Yes |
| App activity: Other user-generated content | Memorization progress and the revision backup (from the first launch), tasmee' records, competitions, a teacher's notes | No |

- **Not collected:** location, contacts, messages, health, web history, device or other IDs, crash logs or
  diagnostics. Audio: «سمّع بصوتك» hears the microphone with a speech model on the device and never sends or keeps
  the audio; video tasmee' audio and video go live through LiveKit and aren't stored.
- **Account deletion URL** (asked by Play): `https://azzam-alrashed.github.io/Aqra/support.html`, which explains the
  in-app deletion. A dedicated support email (Q9 of the improvement run) is still to be chosen by the owner.
