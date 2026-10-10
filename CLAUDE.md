# Aqra — notes for Claude Code

Aqra («اقْرَأْ») helps a حافظ memorize, revise and keep the Quran. Read first: `docs/VISION.md` (product decisions),
`docs/SRS.md` (requirements and statuses), `docs/REVISION.md` (revision policy), `backend/README.md` (data and rules),
`shared/quran/README.md` (Quran sources). Quran text integrity is the first principle.

## Repo map

```
apps/ios/            SwiftUI app, iOS 17+. XcodeGen: edit project.yml, then `xcodegen generate` (procedure below)
  Aqra/Account/      AccountStore (anonymous auth → Apple/Google link), CloudSync + CloudBackup (Firestore backup/merge), Journey, Inbox
  Aqra/Revision/     RevisionEngine (ReviewPolicy, RevisionStore: plan, follow-ups, rotation, streak), WirdView, DailyAmountView
  Aqra/Memorization/ MemorizationStore (AyahMemory half-life), MemorizationSetupView («ماذا تحفظ؟»)
  Aqra/Mushaf/       MushafStore (data), MushafPageView (COLR glyph drawing), MushafView (+ MushafRootView: root/setup state machine)
  Aqra/Plan/ Curriculum/ Rewards/ Social/ Tasmee/ (VideoCall.swift = LiveKit) Credits/ Progress/ Home/ Onboarding/ DesignSystem/ Recitation/
  Aqra/Localizable.xcstrings   ar + en; the keys are the English source
  AqraTests/         Swift Testing suites (filter by suite: `-only-testing:AqraTests/RevisionTests`; `…/func` silently runs 0)
  AppStore/          listing text, privacy labels, review notes, screenshots
apps/android/        Kotlin + Compose twin, package com.azzamalrashed.aqra (same Firestore layout, same policy constants)
  app/src/main/java/com/azzamalrashed/aqra/{account,revision,memorization,mushaf,quran (font engine),recitation (ONNX),tasmee,…}
  app/src/main/res/values*/strings_ios.xml  generated from the iOS catalog (below); strings.xml = Android-only strings
  app/src/test/      JUnit tests; the CoreText cross-check reads apps/android/build/coretext (see apps/android/README.md)
backend/             firestore.rules, storage.rules, firestore.indexes.json, functions/src/*.ts, scripts/{seed-emulator,admin}.mjs, test/
shared/quran/        KFGQPC Hafs data, QUL layout + glyphs + ayah-themes (stand-in topics), qcf4/ (604 page fonts, gitignored). NEVER EDIT.
docs/                VISION, SRS, REVISION, QA-LOG, QA-PROPOSALS, qa/; index.html + privacy.html + support.html are LIVE on GitHub Pages
                     (azzam-alrashed.github.io/Aqra) as soon as main is pushed
scripts/             fetch-mushaf-fonts.sh (the 604 fonts), fetch-firebase-config.sh (the iOS plist)
.github/workflows/   ci.yml: the four suites on every pull request
build/               gitignored scratch (videos, prompts, proofreading packs)
```

## Commands

Keep DerivedData outside the repo. After an iOS test run, check `git status`: a build can rewrite `Localizable.xcstrings`.

```sh
# iOS tests (~2 min warm)
cd apps/ios && xcodebuild test -project Aqra.xcodeproj -scheme Aqra -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath <scratch>/DD
# iOS Release (simulator)
xcodebuild build -project Aqra.xcodeproj -scheme Aqra -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/DD-release CODE_SIGNING_ALLOWED=NO
# Android: tests + debug build against the emulators
cd apps/android && ./gradlew -PuseFirebaseEmulator :app:testDebugUnitTest :app:assembleDebug
# Android release: ALWAYS a separate Gradle run (the flag skips the google-services plugin and ships with accounts off)
./gradlew :app:assembleRelease          # then read app/build/outputs/mapping/release/mapping.txt
# Backend (each starts its own emulators; stop `npm run emulators` first — the ports clash and the tests wipe emulator data)
cd backend && npm run test:rules && npm run test:functions
```

Walkthroughs against the emulators:

```sh
cd backend && npm run emulators                                   # Auth 9099, Firestore 8080, Functions 5001, Storage 9199, UI 4000
xcrun simctl launch <udid> com.azzamalrashed.aqra -UseFirebaseEmulator -AppleLanguages "(ar)" -AppleLocale ar_SA
adb -s emulator-5554 shell cmd locale set-app-locales com.azzamalrashed.aqra --locales ar-SA   # after a -PuseFirebaseEmulator install
npm run seed -- --email teacher@example.com                       # a vetted teacher with a session tomorrow
xcrun simctl keychain <udid> reset                                # after an emulator restart: Firebase Auth keeps its user in the keychain
printf '…' | LC_ALL=en_US.UTF-8 xcrun simctl pbcopy <udid>        # type Arabic into the simulator through the pasteboard
```

## Devices

| Simulator / device | Use |
|---|---|
| The owner's "iPhone 17 Pro" (162B4A28…) | **Never touch.** Signed in to his real account |
| "Aqra Shots" (C154C23A…), "Aqra Store iPhone", "Aqra Store iPad" | Seeded screenshot data. Never test on them, never seed the owner's own simulator |
| Your own (e.g. "Aqra Next", iPhone 17, iOS 26.5) | Make it for the run; delete it at the end with the owner's OK |
| Android AVD `medium_phone` | The owner's. Make your own by copying `~/.android/avd/medium_phone.avd/config.ini` (there's no avdmanager) |
| Physical: iPhone 12 "Azzam Rar"; Samsung SM-A075F `R83L10JQ9WX` | Never install on a phone without asking |

Target by UDID or serial (`adb -s …`). Debug builds for testing use the emulators: iOS `-UseFirebaseEmulator`, Android
`-PuseFirebaseEmulator`. A plain Android debug build with `google-services.json` talks to **production**.

Gitignored inputs a fresh worktree lacks: `shared/quran/qcf4/`, `apps/ios/Firebase/GoogleService-Info.plist`,
`apps/android/app/google-services.json`, `apps/android/local.properties`, `apps/android/build/coretext/`,
`backend/node_modules`, `backend/functions/node_modules`, `backend/functions/.env.local`, `backend/functions/.secret.local`.
**Copy** the first two (they're bundled into the app, and a symlink inside the bundle makes the simulator refuse to
install it); the rest can be symlinks. Unlink the symlinks before removing the worktree.

## Rules

Set by the owner, word for word:

- For any UI change, propose it and mock it up in the app's own style, then wait for my "go" before coding.
- Never let xcodegen wipe the dev team, display name or category. Keep them in project.yml.
- Someone else also works in this tree (apps/android). Stage only your own paths and never run `git add -A`.
- The backend stays in europe-west1 only.
- Never seed my own simulator.
- Never submit to the App Store or Google Play.

Sacred text:
- Quran text comes only from the King Fahd Complex data and fonts in `shared/quran` (Hafs), bundled unmodified. Never
  type, generate, edit or "clean up" Quran text, not even in comments: refer to ayat as surah:ayah or by word ids.
- Hadith and translations are quoted byte-for-byte from the chosen source (`SacredText`, with SHA-256 tests).

Ask first, and say in plain words why it's needed:
- downloading anything (name, source, size), including a new SDK or package dependency; uploading anything, including
  to Firebase Storage; any deploy; any Firebase, Apple, Google, LiveKit or GitHub settings change; deleting anything
  outside the repo.
- Commit, push, merge and deploy only when the owner says so. The repo is public and `docs/` is the live website:
  deploy rules and functions **before** pushing a commit that describes a security fix. For a production deploy, show
  the diff and a dry run first.

Production and devices:
- Never test against production. Never strip roles or data from the owner's real account (a test cleanup once removed
  his teacher status).
- Before touching `apps/android`, check `git status` and `git log -- apps/android` for work that isn't yours.
- Do every workstream in its own worktree under `.claude/worktrees/<ws>`: a branch in the shared checkout moves
  everyone's HEAD. One branch and one PR per workstream.

Talking to the owner:
- When he frames something as discussion ("no code for now", "log it"), discuss only.
- One question at a time, recommendation first. After a bare "no", ask what's off and offer concrete options. When he
  says he's unsure, step back to the big picture instead of picking a default.
- Plain words for technical terms. Measure sizes and timings rather than estimating. Justify technical picks with evidence.
- Chat in English (he may write in Arabic).

Design:
- Every screen speaks the onboarding's language: `OnboardingPageLayout`, `OnboardingHeadline` (two lines, the second in
  purple), `DesignSystem/AqraComponents.swift`, the BrandButton. Functions are visible cards and buttons, not hidden
  gestures. No duplicate controls across screens. The Mushaf stays a button on Home, never a tab. Keep the system
  Liquid Glass tab bar with minimize-on-scroll. No characters or living beings. Don't hand-draw ornament in code.
- Once the owner says "go", build to the best standard and improve on the instruction rather than following it literally.
- Before claiming a screen is checked: scroll to the bottom of every scroll view (floating bars hide the last row), zoom
  in on alignment, check Arabic and English, an iPhone SE and a Pro Max, and an Android small and large screen.

Words:
- App copy is formal Arabic (فصحى), always in Arabic and English. Marketing copy must be true to the current build.
- Don't name other apps as Aqra's model in docs or memory; describe the direction as Aqra's own.

Doing the work:
- Do in-app test steps yourself when no password is involved. The owner does every sign-in himself, and pastes every
  secret himself (`pbpaste | firebase functions:secrets:set NAME --data-file=-`). Never read secret values.

## Procedures

**XcodeGen.** `project.yml` is the source of truth. Before `xcodegen generate`, copy `Aqra.xcodeproj/project.pbxproj`
aside; afterwards diff them and confirm these survived: `DEVELOPMENT_TEAM` 6QYT6GJB4Z, the display name «اقْرَأْ»
(`INFOPLIST_KEY_CFBundleDisplayName`), the Education category, `TARGETED_DEVICE_FAMILY` "1,2" (iPad) with all four
orientations, and the build number (`CURRENT_PROJECT_VERSION` on the Aqra target). All of them live in `project.yml`;
if one is missing from the diff, fix `project.yml`, never the pbxproj.

**String catalog.** Edit `Localizable.xcstrings` as JSON in Xcode's own format: keys sorted as Xcode writes them, the
`" : "` separator with spaces, two-space indentation, every key with an `ar` translation (English is the key). A
build may rewrite the file; review that diff before staging it.

**Android strings.** After changing the iOS catalog, run `python3 apps/android/tools/import-ios-strings.py`; it
regenerates `values/strings_ios.xml` and `values-ar/strings_ios.xml` and keeps existing resource names. Android-only
strings go in `strings.xml` by hand.

**Tests to run before a PR.** All four suites (iOS, Android with the CoreText cross-check tables present, rules,
functions), then CI on the PR. New behavior gets a test on both platforms; shared scheduling logic gets a fixture both
suites read.

**Docs to keep in step.** A behavior change updates `docs/SRS.md` (the row's status and Appendix B), `docs/REVISION.md`
for the revision policy, and `docs/VISION.md` for product decisions. `docs/*.html` are published on push: change them
only with the owner's go.
