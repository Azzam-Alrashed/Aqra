# Aqra
عن عبد الله بن عمرو رضي الله عنهما عن النبي ﷺ قال: (يقالُ لصاحِبِ القرآنِ اقرَأ وارقَ ورتِّل كما كُنتَ ترتِّلُ في الدُّنيا فإنَّ منزلتَكَ عندَ آخرِ آيةٍ تقرؤُها). رواه أحمد.

## Repository layout

```
apps/
  ios/        iOS app (SwiftUI, XcodeGen: edit project.yml, then run `xcodegen generate`)
  android/    Android app (Kotlin, Jetpack Compose; see apps/android/README.md)
  web/        Web app (PWA): not started (its README says what's planned)
backend/      Firebase: Firestore and Storage rules with their tests, the indexes, the Cloud Functions (TypeScript),
              the seed and admin scripts (see backend/README.md)
shared/       Platform-neutral data: the Quran text, the Mushaf layout and page fonts, with their checksums (see shared/quran/README.md)
docs/         Product and technical documentation (VISION.md, SRS.md, REVISION.md, the QA log and proposals), and the
              website (index.html, privacy.html, support.html: served by GitHub Pages from main as soon as it's pushed)
scripts/      Restore the gitignored inputs: the 604 page fonts, the iOS Firebase config
.github/      CI: the four test suites (iOS, Android, rules, functions) on every pull request
```

`CLAUDE.md` holds the working notes for AI-assisted sessions: commands, device roles, and the owner's rules.

## Setup

The 604 Mushaf page fonts (~50 MB, with tajweed) aren't in git. After cloning, restore and verify them before building:

```
scripts/fetch-mushaf-fonts.sh
```

The app's Firebase config isn't in git either. Restore it with the Firebase CLI (signed in with access to the
`aqra-quran` project); without it the app still runs, with accounts and backup turned off:

```
scripts/fetch-firebase-config.sh
```

The Android app's config, `apps/android/app/google-services.json`, isn't in git either (see apps/android/README.md).
A debug build with it talks to the production project; build with `-PuseFirebaseEmulator` to test.

