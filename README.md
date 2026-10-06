# Aqra
عن عبد الله بن عمرو رضي الله عنهما عن النبي ﷺ قال: (يقالُ لصاحِبِ القرآنِ اقرَأ وارقَ ورتِّل كما كُنتَ ترتِّلُ في الدُّنيا فإنَّ منزلتَكَ عندَ آخرِ آيةٍ تقرؤُها). رواه أحمد.

## Repository layout

```
apps/
  ios/        iOS app (SwiftUI, XcodeGen: edit project.yml, then run `xcodegen generate`)
  android/    Android app (planned)
  web/        Web PWA (planned)
backend/      Firebase: Cloud Functions, Firestore rules and indexes (planned)
shared/       Platform-neutral data, e.g. the verified Quran text and its checksums (planned)
docs/         Product and technical documentation, see docs/VISION.md
```

## Setup

The 604 Mushaf page fonts (~205 MB) aren't in git. After cloning, restore and verify them before building:

```
scripts/fetch-mushaf-fonts.sh
```

