# Aqra
عن عبد الله بن عمرو رضي الله عنهما عن النبي ﷺ قال: (يُقَالُ لِصَاحِبِ القُرْآنِ: اقْرَأْ وَارْتَقِ، وَرَتِّلْ كَمَا كُنْتَ تُرَتِّلُ في الدُّنْيَا؛ فإنَّ مَنْزِلَكَ عِنْدَ آخِرِ آيةٍ تَقرَؤُها).

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
