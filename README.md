# Aqra
عن عبد الله بن عمرو رضي الله عنهما عن النبي ﷺ قال: (يقالُ لصاحِبِ القرآنِ اقرَأ وارقَ ورتِّل كما كُنتَ ترتِّلُ في الدُّنيا فإنَّ منزلتَكَ عندَ آخرِ آيةٍ تقرؤُها). رواه أحمد.

## Repository layout

```
apps/
  ios/        iOS app (SwiftUI, XcodeGen: edit project.yml, then run `xcodegen generate`)
  android/    Android app (planned)
  web/        Web PWA (planned)
backend/      Firebase: Firestore rules and their tests; Cloud Functions (planned)
shared/       Platform-neutral data, e.g. the verified Quran text and its checksums (planned)
docs/         Product and technical documentation (see docs/VISION.md), and the website (index.html, served by GitHub Pages)
```

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

