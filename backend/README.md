# Aqra — Backend

The Firebase project `aqra-quran`, shared by all apps. Firestore lives in Dammam, Saudi Arabia (`me-central2`).

- `firestore.rules`: each user reads and writes only their own progress under `users/{uid}`; everything else is
  closed until a later step opens it on purpose.
- `firestore.indexes.json`: none yet.
- Planned: Cloud Functions for session booking, LiveKit room tokens, and later the seat auction and credits.

## Commands

```
npm install                                         # once, for the rules tests
npm run test:rules                                  # the rules tests, on the Firestore emulator (needs Java)
firebase deploy --only firestore:rules              # publish the rules
```

## What's stored

- `users/{uid}`: `updatedAt`.
- `users/{uid}/memory/block-NN` (25 blocks of 256 ayat): each memorized ayah as
  `[since, stability, lastReviewed or -1, lapses, verified]`, dates in seconds since 1970.
- `users/{uid}/revision/state`: the revision record (daily amount, rotation, follow-ups, today's plan, the days
  revised and the last 1,000 revisions) as JSON.

The device's copy is the one the app works from; the account is its backup. See
`apps/ios/Aqra/Account/CloudBackup.swift` for the merge rules. Deleting the account deletes all of it.

See [docs/VISION.md](../docs/VISION.md).
