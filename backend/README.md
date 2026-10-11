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
  - `redeemPurchase`: credits an App Store purchase of credits once its signed transaction is verified, to the account
    that made it. `appStoreNotifications`: Apple's App Store Server Notifications (an HTTPS endpoint); a refund or
    revocation takes the credits back.
  - `placeBid`, `takeFreeSeat`, `giveBackSeat`, `settleAuctions` (every 5 minutes), `settleAuctionNow`
    (administrators), `onSessionChanged`, `onSessionDeleted`: the seat auction, a bidder's free seat taken instead, a
    seat given back (with the refund policy for one won at auction), the settlement, and the releases and refunds when
    a session is cancelled, or deleted behind the rules' back.
  - `onAccountDeleted`: deletes a deleted account's wallet and ledger, and its application to teach.
  - A trigger may be delivered more than once; each records its event id in `functionEvents/{eventId}` within the
    transaction that does its work, and a repeat does nothing. Nothing in the apps reads that collection.

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
npm run test:rules                                  # the rules tests, on the Firestore and Storage emulators (needs Java 21)
npm run test:functions                              # the functions' tests, on the emulators
npm run emulators                                   # every emulator, functions built first; UI at http://localhost:4000
npm run seed -- --email teacher@example.com         # make that emulator account a vetted teacher (+ a session)
npm run admin -- applications --emulator            # administration (see scripts/admin.mjs; drop --emulator for real)
firebase deploy --only firestore,storage            # publish the rules and the indexes
```

`test:rules` and `test:functions` each start their own emulators on the same ports as `npm run emulators`, and they
wipe the emulators' data: stop a running `npm run emulators` first. The functions' tests read the dev keys in
`functions/.secret.local` (copy `.secret.local.example`). CI runs both on every pull request (`.github/workflows/ci.yml`).

## Trying the app against the emulators

Launch the iOS app with the argument `-UseFirebaseEmulator` (a checkbox in the Aqra scheme's Run arguments; Debug
builds only). The app then talks to the emulators as the project `demo-aqra`, with its own Firestore cache, and
needs no `GoogleService-Info.plist`. On حسابي, "Sign in to the emulator" signs in with any email, no password.
Use different simulators for the emulator and the real project: the app's settings (such as which account it
has restored) are shared on one simulator.

## What's stored

### A student's progress: `users/{uid}`

Only the student reads and writes it. Deleting the account from the app deletes everything under `users/{uid}`
(memory, revision, journey, bookings with their seats given back, tasmee' records, inbox), the teacher's file on each
student if they taught, their uploads, and an application still waiting; the server then deletes the wallet, its ledger
and any reviewed application (`functions/src/accounts.ts`). What stays: `purchases` (the record of what was sold), the
account's bids, `teacherBalances`, and a teacher's own `teachers/{uid}` document and sessions (removed by hand).

- `users/{uid}`: `updatedAt`, and `lastWriter`, the install that last wrote the progress: a device coming back to
  the foreground reads it and fetches the account's copy only when another device wrote since.
- `users/{uid}/memory/block-NN` (25 blocks of 256 ayat): each memorized ayah as
  `[since, stability, lastReviewed or -1, lapses, verified, learnedAt or -1, lastLapseAt or -1]`, dates in seconds
  since 1970; an ayah unmarked leaves a tombstone, `[removedAt, 0, -1, 0, 0, -1, -1]`, which no app reads as
  memorized. A device writes only the rows that changed, merged into the block.
- `users/{uid}/revision/state`: the revision record (daily amount, rotation, follow-ups, today's plan, the days
  revised and the last 1,000 revisions) as JSON, beside `revisedDays` and `completedDays` as arrays (seconds since
  2001) only ever added to, so a day one device wrote survives another's write of the JSON.
- `users/{uid}/journey/state`: the personal plan with its history and portions log, the stage test results, the
  rewards (points, achievements, challenges) and the reader's ribbon (`reading`, optional) as JSON.
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

The device's copy is the one the app works from; the account is its backup, merged into the device's copy whenever
an account is attached and whenever the app comes back after another device wrote (unions, never a blind overwrite).
See `apps/ios/Aqra/Account/CloudBackup.swift` and the Android `CloudBackup.kt` for the merge rules.

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

### The app's downloads: Storage `models/`

`models/recitation/whisper-base-ar-quran-1.aar`: the speech model that follows a revision aloud (Tarteel's
`whisper-base-ar-quran`, Apache-2.0, converted for Core ML with WhisperKit's tools, in an Apple Archive; 134,001,846
bytes, SHA-256 `fd456db6f635bb49a17e4df535e70505ffd03094e9eccc00c3a6f75f8115c686`). The iOS app downloads it from the
`AqraRecitationModelURL` in its Info.plist. `models/recitation/whisper-base-ar-quran-1-onnx.zip` is the same model for
Android, exported to ONNX and quantized to 8 bits (encoder, merged decoder, the mel filter bank and the token list;
67,272,417 bytes, SHA-256 `25f67e1ea6369c553db0319a0bdb02ecfed6c6ebe42c1accc20763e9cb33b3f1`), downloaded from
`RecitationModel.DOWNLOAD_URL`. Anyone reads `models/`; no one writes it through the rules: a new
version gets a new name and is uploaded with the project owner's own credentials, then the app points to it.

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
vetted teacher creates, edits (never below the seats booked) and cancels their own. A session is deleted only while
nobody is in it (`booked` 0, no active bid, no seat won); one with students or bids is cancelled through its
`status`, which releases and refunds them. Should a session with people in it be deleted all the same (an older
build, a script), `onSessionDeleted` does what a cancellation does, removes their bookings and deletes the
orphaned seats and bids.

- `sessions/{id}/seats/{studentUid}`: a booked seat: `bookedAt`, the student's `name`, and what they've
  memorized (`memorizedPages`, `juzSummary`) so the teacher can choose what to hear; a seat won at auction also
  carries `paid`, the credits it cost. Seen by the student and the teacher. A signed-in (not anonymous) student
  books for themselves while the session is open and ahead.
- Booking writes the seat, the student's copy under `bookings`, and `booked + 1` in one transaction; the rules
  let the count move only by one, only together with that student's own seat, and never past `seats`.
- Giving a seat back goes through `giveBackSeat` (the student for their own seat; the teacher for a student's, with
  `studentUid`): it removes the seat, the booking and, for a free seat, one from `booked`, which never drops below
  0. The rules still let a client delete a free seat together with its count (an older build's way), but never a
  seat won at auction: that one is refunded by the policy (below).

### Credits: `wallets/{uid}`, `purchases/{transactionId}`

`wallets/{uid}` holds `balance` and `held` (credits set aside for active bids), and `ledger/{id}` every movement
(`purchase`, `hold`, `release`, `spend`, `refund`, `clawback`, with `amount`, `at` and what it was for; a `refund`
says its `reason`: `sessionCancelled`, `seatGivenBack`, `removedByTeacher` or `sessionDeleted`). Only the functions
write them; their owner reads them. Every bidder has a wallet, even one who never bought credits (a 0 bid makes an
empty one), so that at settlement a bidder without a wallet is known to have deleted their account.
`purchases/{transactionId}` records each App Store purchase credited (`uid`, `productId`, `credits`, `environment`,
`purchasedAt`, `redeemedAt`), so none is credited twice, and `revokedAt` with `revocation` (`REFUND` or `REVOKE`)
once Apple took it back; no client reads it.

The credit packs are App Store consumables, `aqra.credits.10`, `.30` and `.60`, in `config/policy.creditPacks`.

- **Who may redeem a purchase.** The app attaches the account's token to every purchase (StoreKit's
  `appAccountToken`: a UUID made from the uid, the first 16 bytes of its SHA-256 with the UUID version and variant
  bits; `WalletStore.accountToken` and `credits.ts accountToken` derive the same). `redeemPurchase` credits a
  purchase only to the account whose token it carries, and once.
- **Which stores are trusted.** To test purchases without App Store Connect, run the app from Xcode: the scheme uses
  `apps/ios/Credits.storekit`, whose purchases are signed by Xcode, which `redeemPurchase` accepts **only on the
  emulators**; nothing in the policy turns that on in production. Apple's sandbox (TestFlight, App Review) is
  refused unless `config/policy.allowSandboxPurchases` is true: turn it on for a review
  (`npm run admin -- policy --set allowSandboxPurchases=true`) and off afterwards, so nobody fills a wallet with
  test money. Production and sandbox purchases are verified with Apple's App Store Server Library against Apple's
  root certificates in `functions/certs` (see its README; without them every such purchase is refused with "App
  Store verification isn't set up"), with `APPLE_BUNDLE_ID` and `APPLE_APP_ID` (the app's App Store id) set in
  `functions/.env.aqra-quran`.
- **Refunds.** App Store Connect sends App Store Server Notifications (version 2) to
  `https://europe-west1-aqra-quran.cloudfunctions.net/appStoreNotifications` (set that URL for production and for
  the sandbox under the app's General → App Information). A `REFUND` or `REVOKE` takes the purchase's credits back
  as a `clawback` in the ledger, once, and marks the purchase revoked so it can't be redeemed afterwards; the
  balance may go below zero when the credits were spent meanwhile, and the next purchase pays that first. Other
  notifications are acknowledged and ignored; one that doesn't verify is answered 401 and Apple retries it.

### The seat auction

A session may offer auctioned seats beside its free ones: `auctionSeats` (1–20), `minBid`, `biddingClosesAt`
(still ahead and at least 30 minutes before `startsAt`, which is at least an hour away; the app sets it three hours
before, or 30 minutes before a session sooner than three and a half hours) and `auctionState` (`open`, then
`settled`, `cancelled` or `refunded`). Those three durations (3 h, 30 min, 60 min) and the one free seat every
session keeps are **fixed constants**, not policy: nothing on the server reads them at run time, so they live in
the session rules (`firestore.rules`) and in both apps' session editors (iOS `TasmeeStore.biddingClosesAt`, Android
`TasmeeSession.biddingClosesAt`); changing them means changing all three. The functions keep `auctionBids` (the
active bids), `auctionFloor` (what the next bid must reach) and `auctionWon` (the seats won, less those given back)
on the session.

- `sessions/{id}/bids/{uid}`: a bid (`name`, `amount`, `at`, `status`: `active`, `outbid`, `won` or `released`, and
  what the bidder has memorized). Written only by `placeBid`; seen by the bidder and the session's teacher.
- While auctioned seats remain, any bid of at least `minBid` holds one; once all are held, a new bid must beat the
  lowest by `minIncrement` and outbids it (ties go to the earlier bid). A bid holds its credits; an outbid one is
  released at once, and its bidder told in their inbox. A bidder may raise their own bid.
- A student holds a free seat or a bid, not both: `placeBid` refuses a student with a seat, and the rules refuse a
  free seat beside an active bid. A bidder takes a free seat with `takeFreeSeat`, which lets the bid go (releasing
  its credits) and makes the seat, the booking and the count in one transaction.
- When bidding closes, `settleAuctions` spends the winners' holds, makes their seats (with `paid`) and bookings
  (also with `paid`, so the app can say what giving the seat back means), and records the teacher's share in
  `teacherBalances`. It settles only a session still `open`; one cancelled while its auction stayed open has its
  holds released instead. A session that fails to settle is logged and skipped, and the rest are settled.
- A session cancelled while bidding releases every hold; once settled, the credits paid are refunded and the
  teacher's share reversed. Everyone who had a seat is told.
- A seat won at auction is given back only through `giveBackSeat`. Given back by its student at least
  `seatRefundCutoffMinutes` (60) before the session, it's refunded in full (`refund`, reason `seatGivenBack`) and the
  teacher's share reversed; given back later, the credits stay spent and the teacher keeps the share. A teacher
  removing a student (`studentUid`) always refunds them. In a cancelled session the cancellation refunded already,
  so only the student's booking goes.

### A teacher's earnings: `teacherBalances/{uid}`

`earned` and `paidOut`, and `entries/{id}`: each won seat's share (`kind: seat`, `amount` after the commission,
`gross`, `commission`), reversals (`kind: reversal`, a negative `amount`, with the `reason`: `sessionCancelled`,
`seatGivenBack`, `removedByTeacher` or `sessionDeleted`), and payouts. Written by the functions and by
`npm run admin -- payout`; read by the teacher and administrators. Teachers are paid by bank transfer; record each
with `npm run admin -- payout --teacher <uid> --amount <credits> --reference "..."`, which refuses more than is
due (a balance that was never paid out has no `paidOut`; a missing field counts as 0).

### The server's policy: `config/policy`

Overrides of the defaults in `functions/src/policy.ts`: the call's window (`joinOpensMinutesBefore`,
`joinClosesHoursAfter`, `tokenTTLHours`), the auction's `minBid` and `minIncrement`, the `commissionRate`, the
`seatRefundCutoffMinutes` for a paid seat given back, the `creditPacks`, and `allowSandboxPurchases`. Everyone
signed in reads it; administrators change it with `npm run admin -- policy --set commissionRate=0.15`. When bidding
closes and the free seat a session keeps aren't policy (see the seat auction above).

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

### Reports

- `reports/{id}`: a report of a person to the team (`reporter`, `subject`, `subjectName`, `context` — `teacher`,
  `student`, `call`, `friend` or `competition` — `contextId`, `reason` — `inappropriate`, `abuse`, `spam` or
  `other` — an optional `note` of at most 1,000 characters, and `createdAt`, the server's time). Anyone signed in
  creates one as themselves, about someone else; nobody but an administrator reads it. Read them with
  `npm run admin -- reports` (open ones; `--all` for every one) and close one with
  `npm run admin -- resolve-report --id <id> --note "what was done"` (it sets `resolvedAt` and `resolution`).
  Blocking stays on the device and never reaches the server.

See [docs/VISION.md](../docs/VISION.md).
