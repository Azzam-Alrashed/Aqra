# Aqra — Backend

The Firebase project `aqra-quran`, shared by all apps. Firestore lives in Dammam, Saudi Arabia (`me-central2`).

- `firestore.rules`: who may read and write what (see below), with tests on the emulator.
- `firestore.indexes.json`: none yet. Every query filters on one field and sorts on the device.
- `scripts/seed-emulator.mjs`: makes an emulator account a vetted teacher, for trying the teacher's side.
- Planned: Cloud Functions for LiveKit room tokens, and later the seat auction and credits.

## Commands

```
npm install                                         # once
npm run test:rules                                  # the rules tests, on the Firestore emulator (needs Java)
npm run emulators                                   # Auth + Firestore emulators, with the UI at http://localhost:4000
npm run seed -- --email teacher@example.com         # make that emulator account a vetted teacher (+ a session)
firebase deploy --only firestore:rules              # publish the rules
```

## Trying the app against the emulators

Launch the iOS app with the argument `-UseFirebaseEmulator` (a checkbox in the Aqra scheme's Run arguments; Debug
builds only). The app then talks to the emulators as the project `demo-aqra`, with its own Firestore cache, and
needs no `GoogleService-Info.plist`. On حسابي, "Sign in to the emulator" signs in with any email, no password.
Use different simulators for the emulator and the real project: the app's settings (such as which account it
has restored) are shared on one simulator.

## What's stored

### A student's progress: `users/{uid}`

Only the student reads and writes it. Deleting the account deletes all of it.

- `users/{uid}`: `updatedAt`.
- `users/{uid}/memory/block-NN` (25 blocks of 256 ayat): each memorized ayah as
  `[since, stability, lastReviewed or -1, lapses, verified]`, dates in seconds since 1970.
- `users/{uid}/revision/state`: the revision record (daily amount, rotation, follow-ups, today's plan, the days
  revised and the last 1,000 revisions) as JSON.
- `users/{uid}/bookings/{sessionId}`: the student's copy of a session they booked (`teacherId`, `teacherName`,
  `startsAt`, `place`), so the home can show it.
- `users/{uid}/tasmee/{id}`: a tasmee' the student recited to a teacher, **written by that teacher**:
  `teacherId`, `teacherName`, `sessionId`, `at`, `pages` heard, `stumbles` (ayah indices) and `appliedAt`, null
  until the student's app has applied it to the progress on the device. The student may only set `appliedAt`.

The device's copy is the one the app works from; the account is its backup. See
`apps/ios/Aqra/Account/CloudBackup.swift` for the merge rules.

### Teachers: `teachers/{uid}`

`name`, `city`, `line` (one line about the teacher), `vetted`, `createdAt`. Everyone signed in reads them. A
teacher edits their own name, city and line; nothing else is written from the app. **A teacher is made by
hand**, after the vetting (ijazah, interview): create `teachers/{uid}` in the console with `vetted: true`.
Deleting a teacher's account from the app leaves their teacher document and sessions; remove them by hand.

### Sessions: `sessions/{id}`

An in-person tasmee' session: `teacherId`, `teacherName`, `startsAt`, `place`, `seats`, `booked`, `kind`
(`inPerson`), `status` (`open` or `cancelled`), `createdAt`. Everyone signed in reads them. A vetted teacher
creates, edits, cancels and deletes their own.

- `sessions/{id}/seats/{studentUid}`: a booked seat: `bookedAt`, the student's `name`, and what they've
  memorized (`memorizedPages`, `juzSummary`) so the teacher can choose what to hear. Seen by the student and
  the teacher. A signed-in (not anonymous) student books for themselves while the session is open and ahead;
  the student or the teacher can give the seat back at any time.
- Booking writes the seat, the student's copy under `bookings`, and `booked + 1` in one transaction; the rules
  let the count move only by one, only together with that student's own seat, and never past `seats`.
  Cancelling does the reverse.

See [docs/VISION.md](../docs/VISION.md).
