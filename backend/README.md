# Aqra — Backend

The Firebase project `aqra-quran`, shared by all apps. Firestore, Storage and the Cloud Functions all live in one
region, Belgium (`europe-west1`): Google refuses new resources in the Middle East regions for this project.

- `firestore.rules`, `storage.rules`: who may read and write what (see below), with tests on the emulators.
- `firestore.indexes.json`: the two composite indexes the functions' queries need (the due auctions, a teacher's
  competitions a student is in). The emulators don't enforce indexes, so deploy them with the rules:
  `firebase deploy --only firestore`.
- `scripts/seed-emulator.mjs`: makes an emulator account a vetted teacher, for trying the teacher's side.
- `scripts/admin.mjs`: administration from the command line (applications, teachers, administrators, payouts,
  the server policy).
- `functions/`: the Cloud Functions (TypeScript, Node 22, region `europe-west1`), for everything that must be
  trusted rather than left to one client. Their defaults live in `functions/src/policy.ts`; an administrator can
  override any of them in `config/policy`.
  - `joinCall`: a LiveKit room token for a video session, only for its teacher or a student holding a seat, from
    15 minutes before the session until 3 hours after.
  - `onTasmeeRecorded`: when a teacher records a tasmee', tells the student in their inbox and scores the pages
    heard clean in that teacher's running competitions.
  - `redeemPurchase`: credits an App Store purchase of credits once its signed transaction is verified.
  - `placeBid`, `settleAuctions` (every 5 minutes), `settleAuctionNow` (administrators), `onSessionChanged`: the
    seat auction, its settlement, and the releases and refunds when a session is cancelled.
  - `onAccountDeleted`: deletes a deleted account's wallet and ledger.

### Setting up video (LiveKit Cloud)

Create a LiveKit Cloud project, then give the functions its URL and keys:

```
echo "LIVEKIT_URL=wss://<project>.livekit.cloud" > functions/.env.aqra-quran
firebase functions:secrets:set LIVEKIT_API_KEY
firebase functions:secrets:set LIVEKIT_API_SECRET
firebase deploy --only functions
```

On the emulators the functions use `functions/.secret.local` (copy `.secret.local.example`: the keys of
`livekit-server --dev`) and `ws://127.0.0.1:7880`, so a local `livekit-server --dev` makes calls work end to end.

## Commands

```
npm install                                         # once
npm install && npm --prefix functions install        # once
npm run test:rules                                  # the rules tests, on the Firestore and Storage emulators (needs Java)
npm run test:functions                              # the functions' tests, on the emulators
npm run emulators                                   # every emulator, functions built first; UI at http://localhost:4000
npm run seed -- --email teacher@example.com         # make that emulator account a vetted teacher (+ a session)
npm run admin -- applications --emulator            # administration (see scripts/admin.mjs; drop --emulator for real)
firebase deploy --only firestore,storage            # publish the rules and the indexes
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
  `startsAt`, `kind`, `place`), so the home can show it.
- `users/{uid}`: also `displayName`, the name the student chose to show teachers, peers and friends.
- `users/{uid}/tasmee/{id}`: a tasmee' the student recited, **written by whoever heard it**: `kind` (`sheikh`, the
  default, or `peer`), `teacherId` and `teacherName` (the listener), `sessionId` (the session, or a peer request's
  code), `at`, `pages` heard, `stumbles` (ayah indices), optionally `mistakes` (`[{ayah, type}]`, the stumbles a
  listener classified: `forgetting`, `prompting`, `hesitation`, `lahn`, `tajweed`; the rest are `memorization`)
  and, from a teacher, `test` (`{stage, allowedMistakesPerPage}`: a stage test), and `appliedAt`, null until the
  student's app has applied it to the progress on the device. The student may only set `appliedAt`. A teacher may
  write one only in their own session where the student holds a seat; a peer only with the student's valid code.
- `users/{uid}/inbox/{id}`: messages from the server or an administrator (`kind`, `at`, `readAt`): the
  application's status, payouts, and later bids and refunds. The student reads, marks read and deletes them.

The device's copy is the one the app works from; the account is its backup. See
`apps/ios/Aqra/Account/CloudBackup.swift` for the merge rules.

### Peer tasmee': `peerRequests/{code}`

A student's invitation to a friend to hear their tasmee': `studentUid`, `studentName` (absent for an anonymous
student), `startPage`, `createdAt`, `expiresAt` (at most 31 minutes ahead). The code is six characters from an
alphabet without look-alikes. It can be fetched by its code but never listed, never overwritten, and only its
student deletes it.

### Applications to teach: `teacherApplications/{uid}`

`name`, `city`, `line`, `riwayah`, `ijazahFrom`, `ijazahDetails`, `contact`, `files` (up to five paths in
Storage), `status` (`submitted`, `interview`, `approved`, `rejected`), `note` (the team's), `createdAt`,
`updatedAt`. A signed-in (not anonymous) user writes theirs while it's `submitted`; administrators read and
update every one. The copies of the ijazah live in Storage under `ijazahs/{uid}/`: images or PDFs under 10 MB,
read by the applicant and administrators.

### Teachers: `teachers/{uid}`

`name`, `city`, `line` (one line about the teacher), `vetted`, `createdAt`. Everyone signed in reads them. A
teacher edits their own name, city and line; nothing else is written from the app. **A teacher is made by an
administrator**, after the vetting (application, ijazah, interview): `npm run admin -- approve --uid <uid>`
creates `teachers/{uid}` with `vetted: true` from the application and tells the applicant in their inbox.
Deleting a teacher's account from the app leaves their teacher document and sessions; remove them by hand.

- `teachers/{uid}/students/{studentUid}` (`name`, `lastHeardAt`, `notes`) and its `records/{id}`: the teacher's
  own file on each student they heard — a copy of what they recorded, and their private notes. Only the teacher
  reads or writes it. It never holds the student's own progress.

### Administrators

A user with the `admin` custom claim (`npm run admin -- grant-admin --email <email>`; it takes effect at the next
sign-in). The rules let administrators read and review applications, create, update and delete teachers, and
read the uploads.

### Sessions: `sessions/{id}`

A tasmee' session: `teacherId`, `teacherName`, `startsAt`, `place` (empty by video), `seats` (1–30), `booked`,
`kind` (`inPerson` or `video`), `status` (`open` or `cancelled`), `createdAt`. Everyone signed in reads them. A
vetted teacher creates, edits (never below the seats booked), cancels and deletes their own.

- `sessions/{id}/seats/{studentUid}`: a booked seat: `bookedAt`, the student's `name`, and what they've
  memorized (`memorizedPages`, `juzSummary`) so the teacher can choose what to hear. Seen by the student and
  the teacher. A signed-in (not anonymous) student books for themselves while the session is open and ahead;
  the student or the teacher can give the seat back at any time.
- Booking writes the seat, the student's copy under `bookings`, and `booked + 1` in one transaction; the rules
  let the count move only by one, only together with that student's own seat, and never past `seats`.
  Cancelling does the reverse.

### Credits: `wallets/{uid}`, `purchases/{transactionId}`

`wallets/{uid}` holds `balance` and `held` (credits set aside for active bids), and `ledger/{id}` every movement
(`purchase`, `hold`, `release`, `spend`, `refund`, with `amount`, `at` and what it was for). Only the functions
write them; their owner reads them. `purchases/{transactionId}` records each App Store purchase credited (`uid`,
`productId`, `credits`, `environment`), so none is credited twice; no client reads it.

The credit packs are App Store consumables, `aqra.credits.10`, `.30` and `.60`, in `config/policy.creditPacks`.
To test purchases without App Store Connect, run the app from Xcode: the scheme uses `apps/ios/Credits.storekit`,
whose purchases are signed by Xcode, which `redeemPurchase` accepts only on the emulators. In production it verifies
purchases with Apple's App Store Server Library against Apple's root certificates in `functions/certs` (see its
README), with `APPLE_BUNDLE_ID` and `APPLE_APP_ID` (the app's App Store id) set in `functions/.env.aqra-quran`.

### The seat auction

A session may offer auctioned seats beside its free ones: `auctionSeats` (1–20), `minBid`, `biddingClosesAt`
(still ahead and at least 30 minutes before `startsAt`, which is at least an hour away; the app sets it three hours
before, or 30 minutes before a session sooner than three and a half hours; the policy's
`lateBiddingClosesBeforeMinutes` and `minAuctionLeadMinutes`, which the rules and the apps mirror, so changing them
means changing those too) and `auctionState` (`open`, then `settled`, `cancelled`
or `refunded`). The functions keep `auctionBids` (the active bids), `auctionFloor` (what the next bid must reach)
and `auctionWon` on the session.

- `sessions/{id}/bids/{uid}`: a bid (`name`, `amount`, `at`, `status`: `active`, `outbid`, `won` or `released`, and
  what the bidder has memorized). Written only by `placeBid`; seen by the bidder and the session's teacher.
- While auctioned seats remain, any bid of at least `minBid` holds one; once all are held, a new bid must beat the
  lowest by `minIncrement` and outbids it (ties go to the earlier bid). A bid holds its credits; an outbid one is
  released at once, and its bidder told in their inbox. A bidder may raise their own bid.
- When bidding closes, `settleAuctions` spends the winners' holds, makes their seats (with `paid`) and bookings,
  and records the teacher's share in `teacherBalances`.
- A session cancelled while bidding releases every hold; once settled, the credits paid are refunded and the
  teacher's share reversed. Everyone who had a seat is told.

### A teacher's earnings: `teacherBalances/{uid}`

`earned` and `paidOut`, and `entries/{id}`: each won seat's share (`kind: seat`, `amount` after the commission,
`gross`, `commission`), reversals, and payouts. Written by the functions and by `npm run admin -- payout`; read by
the teacher and administrators. Teachers are paid by bank transfer; record each with
`npm run admin -- payout --teacher <uid> --amount <credits> --reference "..."`.

### The server's policy: `config/policy`

Overrides of the defaults in `functions/src/policy.ts` (the call's window, the auction's minimum bid, increment and
closing time, the commission, the credit packs). Everyone signed in reads it; administrators change it with
`npm run admin -- policy --set commissionRate=0.15`.

### Friends and competitions

- `friendInvites/{code}`: an invitation (`ownerUid`, `ownerName`, `createdAt`, `expiresAt`, a week); fetched by its
  code, listed only by its owner.
- `friendships/{a_b}`: two friends (`members`, `names`, `inviteCode`, `createdAt`), made by the one accepting the
  other's valid invitation; either reads or deletes it.
- `competitions/{id}`: `kind` (`friends`, `khatmah` or `teacher`), `title`, `metric` (`pagesRevised`,
  `daysRevised`, `ayatMemorized`, `parts` or `cleanPages`), `ownerUid`, `ownerName`, `startsAt`, `endsAt`,
  `memberUids` (at most 50), `createdAt`. Only members read it; its owner manages it; any member leaves.
  - `members/{uid}`: `name`, `score`, `updatedAt`. In a race among friends each member's app writes its own; in a
    teacher's competition only `onTasmeeRecorded` does, from the pages that teacher heard clean.
  - `parts/{1…30}`: a khatmah's parts (`claimedBy`, `claimedName`, `done`), claimed and finished by members.

See [docs/VISION.md](../docs/VISION.md).
