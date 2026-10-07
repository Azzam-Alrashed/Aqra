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
./gradlew :app:installDebug
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleRelease
```

`-PuseFirebaseEmulator` makes a debug build talk only to the local emulators (`npm run emulators` in `backend/`,
project `demo-aqra`), reached from the Android emulator at 10.0.2.2.

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
