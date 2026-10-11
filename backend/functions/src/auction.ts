// The seat auction (docs/SRS.md AUC). A session may offer auctioned seats beside its free ones. They start free:
// while seats remain, any bid of at least the minimum holds one; once all are held, a new bid must beat the lowest
// by the increment, and outbids it. Bidding holds credits; an outbid hold is released at once; bidding closes
// before the session and the winners' holds are spent, their seats made, and the teacher's share recorded. A bidder
// may take a free seat instead, letting their bid go. Every bid runs in a Firestore transaction, so a seat is never
// won twice. A seat is given back through `giveBackSeat`, which applies the refund policy to one won at auction.
import { DocumentSnapshot, FieldValue, QueryDocumentSnapshot, Timestamp, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "./admin.js";
import { policy } from "./policy.js";
import { accountExists, createWallet, move, notify, readWallet, walletRef } from "./wallet.js";

export interface Bid {
  uid: string;
  name: string;
  amount: number;
  at: number;
}

/** Active bids, best first: the highest amount, and between equal amounts the earlier bid. */
export function ranked(bids: Bid[]): Bid[] {
  return [...bids].sort((a, b) => b.amount - a.amount || a.at - b.at);
}

/** What a new bid must reach, given the other active bids and the seats: the minimum while seats remain, else
 * the lowest active bid plus the increment. Also the bid it would outbid, if any. */
export function bidRequirement(others: Bid[], seats: number, minBid: number, increment: number): { atLeast: number; outbids?: Bid } {
  if (others.length < seats) return { atLeast: minBid };
  const lowest = ranked(others)[others.length - 1];
  return { atLeast: Math.max(lowest.amount + increment, minBid), outbids: lowest };
}

const toBid = (doc: DocumentSnapshot): Bid => ({
  uid: doc.id, name: doc.get("name") ?? "", amount: doc.get("amount") ?? 0, at: (doc.get("at") as Timestamp)?.toMillis() ?? 0,
});

// A trigger may be delivered more than once. Each delivery's event id is recorded in the transaction that does its
// work, and a repeat finds the record and does nothing.
const eventRef = (eventId: string) => db.doc(`functionEvents/${eventId}`);
const alreadyHandled = async (tx: Transaction, eventId: string) => (await tx.get(eventRef(eventId))).exists;
const recordEvent = (tx: Transaction, eventId: string, details: Record<string, unknown>) =>
  tx.create(eventRef(eventId), { ...details, at: Timestamp.now() });

export interface BidResult {
  amount: number;
  /** What the next bid would need, for showing the floor. */
  nextAtLeast: number;
  balance: number;
}

export const placeBid = onCall(async (request): Promise<BidResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (request.auth?.token.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("permission-denied", "Bidding needs a signed-in account.");
  }
  const { sessionId, amount, name, memorizedPages, juzSummary } = request.data ?? {};
  if (typeof sessionId !== "string" || !Number.isInteger(amount) || amount < 0) throw new HttpsError("invalid-argument", "Which session, and how much?");
  const rules = await policy();
  const sessionRef = db.doc(`sessions/${sessionId}`);

  return db.runTransaction(async (tx) => {
    const session = await tx.get(sessionRef);
    if (!session.exists) throw new HttpsError("not-found", "There's no such session.");
    const seats = session.get("auctionSeats") ?? 0;
    const closesAt = (session.get("biddingClosesAt") as Timestamp | undefined)?.toMillis() ?? 0;
    if (seats <= 0) throw new HttpsError("failed-precondition", "This session has no auctioned seats.");
    if (session.get("status") !== "open" || session.get("auctionState") !== "open" || Date.now() >= closesAt) {
      throw new HttpsError("failed-precondition", "Bidding has closed.");
    }
    if (session.get("teacherId") === uid) throw new HttpsError("failed-precondition", "A teacher doesn't bid in their own session.");
    if ((await tx.get(sessionRef.collection("seats").doc(uid))).exists) {
      throw new HttpsError("failed-precondition", "You already hold a free seat in this session.");
    }

    const active = (await tx.get(sessionRef.collection("bids").where("status", "==", "active"))).docs.map(toBid);
    const mine = active.find((bid) => bid.uid === uid);
    const others = active.filter((bid) => bid.uid !== uid);
    const minBid = session.get("minBid") ?? rules.minBid;
    let outbid: Bid | undefined;
    if (mine) {
      // Raising one's own bid keeps one's place: it only has to be higher.
      if (amount <= mine.amount) throw new HttpsError("failed-precondition", "A new bid must be higher than yours.", { atLeast: mine.amount + 1 });
    } else {
      const requirement = bidRequirement(others, seats, minBid, rules.minIncrement);
      if (amount < requirement.atLeast) {
        throw new HttpsError("failed-precondition", "That bid is too low.", { atLeast: requirement.atLeast });
      }
      outbid = requirement.outbids;
    }

    const wallet = await readWallet(tx, uid);
    const hold = amount - (mine?.amount ?? 0);
    if (wallet.balance < hold) throw new HttpsError("failed-precondition", "Not enough credits.", { needed: hold - wallet.balance });
    if (outbid) await readWallet(tx, outbid.uid);

    // Writes, once everything is read. Every bidder ends up with a wallet, even one holding nothing: at settlement a
    // bidder without one is taken for a deleted account.
    if (hold > 0) move(tx, uid, "hold", { balance: -hold, held: hold }, hold, { sessionId });
    else if (!wallet.exists) createWallet(tx, uid);
    tx.set(sessionRef.collection("bids").doc(uid), {
      name: typeof name === "string" ? name.slice(0, 40) : "", amount, at: Timestamp.now(), status: "active",
      memorizedPages: Number.isInteger(memorizedPages) ? memorizedPages : 0,
      ...(typeof juzSummary === "string" ? { juzSummary } : {}),
    });
    if (outbid) {
      move(tx, outbid.uid, "release", { balance: outbid.amount, held: -outbid.amount }, outbid.amount, { sessionId });
      tx.update(sessionRef.collection("bids").doc(outbid.uid), { status: "outbid" });
      notify(tx, outbid.uid, { kind: "outbid", sessionId, teacherName: session.get("teacherName") ?? "", amount: outbid.amount });
    }
    const after = ranked([...others.filter((bid) => bid.uid !== outbid?.uid), { uid, name: "", amount, at: Date.now() }]);
    const next = bidRequirement(after, seats, minBid, rules.minIncrement).atLeast;
    tx.update(sessionRef, { auctionBids: after.length, auctionFloor: next });
    return { amount, nextAtLeast: next, balance: wallet.balance - hold };
  });
});

export interface FreeSeatResult {
  /** The credits that came back from the bid let go, if any. */
  released: number;
}

/** A free seat taken instead of a bid (docs/SRS.md AUC-08): in one transaction, the student's active bid in the
 * session is let go and its credits released, and their seat, booking and the seat count are made, so they never hold
 * both. Without an active bid it books the seat all the same. */
export const takeFreeSeat = onCall(async (request): Promise<FreeSeatResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (request.auth?.token.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("permission-denied", "Booking needs a signed-in account.");
  }
  const { sessionId, name, memorizedPages, juzSummary } = request.data ?? {};
  if (typeof sessionId !== "string") throw new HttpsError("invalid-argument", "Which session?");
  const rules = await policy();
  const sessionRef = db.doc(`sessions/${sessionId}`);
  const seatRef = sessionRef.collection("seats").doc(uid);
  const bidRef = sessionRef.collection("bids").doc(uid);

  return db.runTransaction(async (tx) => {
    const session = await tx.get(sessionRef);
    if (!session.exists) throw new HttpsError("not-found", "There's no such session.");
    const startsAt = (session.get("startsAt") as Timestamp | undefined)?.toMillis() ?? 0;
    if (session.get("status") !== "open" || Date.now() >= startsAt) throw new HttpsError("failed-precondition", "This session isn't open.");
    if (session.get("teacherId") === uid) throw new HttpsError("failed-precondition", "A teacher doesn't book their own session.");
    if ((session.get("booked") ?? 0) >= (session.get("seats") ?? 0)) throw new HttpsError("failed-precondition", "The free seats are taken.");
    if ((await tx.get(seatRef)).exists) throw new HttpsError("failed-precondition", "You already hold a seat in this session.");
    const bid = await tx.get(bidRef);
    const releasing = bid.exists && bid.get("status") === "active" ? (bid.get("amount") as number) ?? 0 : undefined;
    const active = releasing !== undefined
      ? (await tx.get(sessionRef.collection("bids").where("status", "==", "active"))).docs.map(toBid)
      : [];
    if (releasing) await readWallet(tx, uid);

    // Writes, once everything is read.
    const counts: Record<string, unknown> = { booked: FieldValue.increment(1) };
    if (releasing !== undefined) {
      if (releasing > 0) move(tx, uid, "release", { balance: releasing, held: -releasing }, releasing, { sessionId });
      tx.update(bidRef, { status: "released" });
      // The auction's standing without this bid.
      const after = ranked(active.filter((other) => other.uid !== uid));
      counts.auctionBids = after.length;
      counts.auctionFloor = bidRequirement(after, session.get("auctionSeats") ?? 0, session.get("minBid") ?? rules.minBid,
                                           rules.minIncrement).atLeast;
    }
    tx.set(seatRef, {
      name: typeof name === "string" ? name.slice(0, 40) : "", bookedAt: Timestamp.now(),
      memorizedPages: Number.isInteger(memorizedPages) ? memorizedPages : 0,
      ...(typeof juzSummary === "string" ? { juzSummary } : {}),
    });
    tx.set(db.doc(`users/${uid}/bookings/${sessionId}`), {
      teacherId: session.get("teacherId"), teacherName: session.get("teacherName") ?? "", startsAt: session.get("startsAt"),
      kind: session.get("kind") ?? "inPerson", place: session.get("place") ?? "",
    });
    tx.update(sessionRef, counts);
    return { released: releasing ?? 0 };
  });
});

export interface GiveBackResult {
  /** The credits refunded for a seat won at auction; 0 for a free seat, or when the policy keeps them. */
  refunded: number;
}

/** A seat given back (docs/SRS.md AUC-09): the seat, the student's booking and, for a free seat, the session's count
 * go in one transaction, and the count never drops below zero. A seat won at auction is refunded by the policy: in
 * full when given back at least `seatRefundCutoffMinutes` before the session, the teacher's share reversed with it;
 * later, the credits stay spent. The session's teacher may give a student's seat back too (`studentUid`), which
 * always refunds. In a cancelled or deleted session only the student's booking goes: the cancellation refunded. */
export const giveBackSeat = onCall(async (request): Promise<GiveBackResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { sessionId, studentUid } = request.data ?? {};
  if (typeof sessionId !== "string" || !sessionId) throw new HttpsError("invalid-argument", "Which session?");
  if (studentUid !== undefined && (typeof studentUid !== "string" || !studentUid)) throw new HttpsError("invalid-argument", "Which student?");
  const rules = await policy();
  const sessionRef = db.doc(`sessions/${sessionId}`);

  return db.runTransaction(async (tx) => {
    const session = await tx.get(sessionRef);
    const byTeacher = typeof studentUid === "string" && studentUid !== uid;
    if (byTeacher && (!session.exists || session.get("teacherId") !== uid)) {
      throw new HttpsError("permission-denied", "Only the session's teacher removes a student.");
    }
    const student = byTeacher ? studentUid : uid;
    const seatRef = sessionRef.collection("seats").doc(student);
    const bookingRef = db.doc(`users/${student}/bookings/${sessionId}`);
    const seat = await tx.get(seatRef);
    if (!seat.exists) {
      // Nothing but the student's own copy is left to remove.
      tx.delete(bookingRef);
      return { refunded: 0 };
    }
    const paid = seat.get("paid") as number | undefined;
    if (paid === undefined) {
      // A free seat goes back to the session's count, which never drops below zero.
      if (session.exists && (session.get("booked") ?? 0) > 0) tx.update(sessionRef, { booked: FieldValue.increment(-1) });
      tx.delete(seatRef);
      tx.delete(bookingRef);
      return { refunded: 0 };
    }
    // A seat won at auction.
    if (!session.exists || session.get("status") !== "open") {
      tx.delete(bookingRef);
      return { refunded: 0 };
    }
    const startsAt = (session.get("startsAt") as Timestamp | undefined)?.toMillis() ?? 0;
    const refundable = paid > 0 && (byTeacher || startsAt - Date.now() >= rules.seatRefundCutoffMinutes * 60_000);
    const teacherId = session.get("teacherId") as string;
    const wallet = refundable ? await readWallet(tx, student) : undefined;
    const entries = refundable
      ? (await tx.get(db.collection(`teacherBalances/${teacherId}/entries`)
          .where("sessionId", "==", sessionId).where("kind", "==", "seat").where("studentUid", "==", student))).docs
      : [];

    // Writes, once everything is read.
    tx.delete(seatRef);
    tx.delete(bookingRef);
    tx.update(sessionRef, { auctionWon: Math.max(0, ((session.get("auctionWon") as number) ?? 1) - 1) });
    if (!wallet) return { refunded: 0 };
    const reason = byTeacher ? "removedByTeacher" : "seatGivenBack";
    // A deleted account has no wallet to refund into; its booking and seat still go.
    if (wallet.exists) move(tx, student, "refund", { balance: paid }, paid, { sessionId, reason });
    const entry = entries[0];
    if (entry) {
      const share = entry.get("amount") as number;
      tx.create(db.collection(`teacherBalances/${teacherId}/entries`).doc(), {
        kind: "reversal", amount: -share, sessionId, studentUid: student, reason, at: Timestamp.now(),
      });
      tx.set(db.doc(`teacherBalances/${teacherId}`), { earned: FieldValue.increment(-share), updatedAt: Timestamp.now() }, { merge: true });
    }
    return { refunded: wallet.exists ? paid : 0 };
  });
});

/** Closes a session's auction: the winners' holds are spent, their seats and bookings made, and the teacher's share
 * recorded. Does nothing if the session isn't open, its auction isn't open, or (unless forced) bidding hasn't closed. */
export async function settle(sessionId: string, { force = false } = {}): Promise<number> {
  const rules = await policy();
  const sessionRef = db.doc(`sessions/${sessionId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const session = await tx.get(sessionRef);
    if (!session.exists || session.get("auctionState") !== "open") return 0;
    if (session.get("status") !== "open") {
      // A cancelled session is never settled, even when the cancellation's trigger failed to release its holds.
      logger.warn(`settle: session ${sessionId} is ${session.get("status")}, not settled`);
      return 0;
    }
    const closesAt = (session.get("biddingClosesAt") as Timestamp).toMillis();
    if (!force && Date.now() < closesAt) return 0;
    const bids = (await tx.get(sessionRef.collection("bids").where("status", "==", "active"))).docs;
    const wallets = await Promise.all(bids.map((bid) => tx.get(walletRef(bid.id))));
    // A bidder may have taken a free seat after bidding; they keep it, and their bid is let go.
    const freeSeats = await Promise.all(bids.map((bid) => tx.get(sessionRef.collection("seats").doc(bid.id))));
    // A bidder without a wallet either deleted their account (the wallet went with it) or bid 0 before every bidder
    // was given one: the account tells them apart.
    const alive = new Map(await Promise.all(
      bids.filter((_, index) => !wallets[index].exists).map(async (bid) => [bid.id, await accountExists(bid.id)] as const),
    ));
    const teacherId = session.get("teacherId");
    const startsAt = session.get("startsAt");

    let won = 0;
    let earned = 0;
    bids.forEach((bid, index) => {
      const amount = bid.get("amount") as number;
      const hasWallet = wallets[index].exists;
      if (!hasWallet && (!alive.get(bid.id) || amount > 0)) {
        // A deleted account has no wallet to spend from and nobody to seat; a hold without a wallet can't happen, and
        // is let go rather than charged.
        logger.warn(`settle: bid of ${amount} by ${bid.id} in ${sessionId} let go (${alive.get(bid.id) ? "no wallet" : "account deleted"})`);
        tx.update(bid.ref, { status: "released" });
        return;
      }
      if (freeSeats[index].exists) {
        if (amount > 0) move(tx, bid.id, "release", { balance: amount, held: -amount }, amount, { sessionId });
        tx.update(bid.ref, { status: "released" });
        return;
      }
      won += 1;
      if (amount > 0) move(tx, bid.id, "spend", { held: -amount }, amount, { sessionId });
      else if (!hasWallet) createWallet(tx, bid.id);
      tx.update(bid.ref, { status: "won" });
      tx.set(sessionRef.collection("seats").doc(bid.id), {
        name: bid.get("name") ?? "", bookedAt: Timestamp.now(), memorizedPages: bid.get("memorizedPages") ?? 0, paid: amount,
        ...(bid.get("juzSummary") ? { juzSummary: bid.get("juzSummary") } : {}),
      });
      tx.set(db.doc(`users/${bid.id}/bookings/${sessionId}`), {
        teacherId, teacherName: session.get("teacherName") ?? "", startsAt, kind: session.get("kind") ?? "inPerson",
        place: session.get("place") ?? "", paid: amount,
      });
      notify(tx, bid.id, { kind: "won", sessionId, teacherName: session.get("teacherName") ?? "", amount });
      if (amount > 0) {
        const share = Math.round(amount * (1 - rules.commissionRate) * 100) / 100;
        earned += share;
        tx.create(db.collection(`teacherBalances/${teacherId}/entries`).doc(), {
          kind: "seat", amount: share, gross: amount, commission: Math.round((amount - share) * 100) / 100, sessionId,
          studentUid: bid.id, at: Timestamp.now(),
        });
      }
    });
    if (earned > 0) {
      tx.set(db.doc(`teacherBalances/${teacherId}`), { earned: FieldValue.increment(earned), updatedAt: Timestamp.now() }, { merge: true });
    }
    tx.update(sessionRef, { auctionState: "settled", auctionWon: won });
    return won;
  });
}

/** Every five minutes, the auctions whose bidding has closed are settled. One that fails is logged and skipped, so
 * the rest are still settled; a session cancelled while its auction stayed open has its holds released instead. */
export const settleAuctions = onSchedule("every 5 minutes", async () => {
  const due = await db.collection("sessions").where("auctionState", "==", "open")
    .where("biddingClosesAt", "<=", Timestamp.now()).limit(50).get();
  for (const session of due.docs) {
    try {
      if (session.get("status") === "cancelled") await releaseCancelled(session.id);
      else await settle(session.id);
    } catch (error) {
      logger.error(`settleAuctions: session ${session.id} couldn't be settled`, { error: String(error), stack: (error as Error).stack });
    }
  }
});

/** An administrator settles a session's auction now (and the tests do). */
export const settleAuctionNow = onCall(async (request) => {
  if (request.auth?.token.admin !== true) throw new HttpsError("permission-denied", "Administrators only.");
  const sessionId = request.data?.sessionId;
  if (typeof sessionId !== "string") throw new HttpsError("invalid-argument", "Which session?");
  return { won: await settle(sessionId, { force: true }) };
});

/** The teacher's entries for the seats won in a session, to reverse them. */
const seatEntries = (tx: Transaction, teacherId: string, sessionId: string) =>
  tx.get(db.collection(`teacherBalances/${teacherId}/entries`).where("sessionId", "==", sessionId).where("kind", "==", "seat"));

/** A session cancelled by its teacher: holds still open are released; credits already spent are refunded and the
 * teacher's share reversed; everyone who had a seat or a bid is told, with the session's start so the message can say
 * which one. With an event id, done once however often the trigger is delivered. */
async function releaseCancelled(sessionId: string, eventId?: string): Promise<void> {
  const sessionRef = db.doc(`sessions/${sessionId}`);
  await db.runTransaction(async (tx) => {
    if (eventId && await alreadyHandled(tx, eventId)) return;
    const session = await tx.get(sessionRef);
    if (!session.exists) return;
    const teacherName = session.get("teacherName") ?? "";
    const startsAt = session.get("startsAt") ?? null;
    const state = session.get("auctionState");
    const bids = state === "open" ? (await tx.get(sessionRef.collection("bids").where("status", "==", "active"))).docs : [];
    const seats = (await tx.get(sessionRef.collection("seats"))).docs;
    const refunds = state === "settled" ? seats.filter((seat) => (seat.get("paid") ?? 0) > 0) : [];
    const teacherId = session.get("teacherId");
    const entries = refunds.length ? (await seatEntries(tx, teacherId, sessionId)).docs : [];
    const wallets = await Promise.all([...bids, ...refunds].map((doc) => tx.get(walletRef(doc.id))));

    let index = 0;
    for (const bid of bids) {
      const amount = bid.get("amount") ?? 0;
      if (wallets[index++].exists && amount > 0) move(tx, bid.id, "release", { balance: amount, held: -amount }, amount, { sessionId });
      tx.update(bid.ref, { status: "released" });
      notify(tx, bid.id, { kind: "cancelled", sessionId, teacherName, amount, startsAt });
    }
    let reversed = 0;
    for (const seat of refunds) {
      const paid = seat.get("paid");
      if (wallets[index++].exists) move(tx, seat.id, "refund", { balance: paid }, paid, { sessionId, reason: "sessionCancelled" });
      const entry = entries.find((e) => e.get("studentUid") === seat.id);
      if (entry) {
        reversed += entry.get("amount");
        tx.create(db.collection(`teacherBalances/${teacherId}/entries`).doc(), {
          kind: "reversal", amount: -entry.get("amount"), sessionId, studentUid: seat.id, reason: "sessionCancelled", at: Timestamp.now(),
        });
      }
    }
    if (reversed > 0) {
      tx.set(db.doc(`teacherBalances/${teacherId}`), { earned: FieldValue.increment(-reversed), updatedAt: Timestamp.now() }, { merge: true });
    }
    for (const seat of seats) {
      notify(tx, seat.id, {
        kind: refunds.includes(seat) ? "refund" : "cancelled", sessionId, teacherName, amount: seat.get("paid") ?? 0, startsAt,
      });
    }
    if (state === "open" || state === "settled") tx.update(sessionRef, { auctionState: state === "open" ? "cancelled" : "refunded" });
    if (eventId) recordEvent(tx, eventId, { trigger: "onSessionChanged", sessionId });
  });
}

export const onSessionChanged = onDocumentUpdated("sessions/{sessionId}", async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  if (!before || !after || before.get("status") === "cancelled" || after.get("status") !== "cancelled") return;
  await releaseCancelled(event.params.sessionId, event.id);
});

/** A session deleted outright. The rules allow it only with no seat booked, no bid active and no seat won, so this
 * is the safety net for anything that slips past them: holds are released, paid seats refunded and the teacher's
 * share reversed, everyone told, their bookings removed, and the orphaned seats and bids deleted. Once per event. */
export const onSessionDeleted = onDocumentDeleted("sessions/{sessionId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;
  const sessionId = event.params.sessionId;
  const sessionRef = db.doc(`sessions/${sessionId}`);
  await db.runTransaction(async (tx) => {
    if (await alreadyHandled(tx, event.id)) return;
    // A session made again under the same id before this ran has bids and seats of its own, which aren't this one's.
    if ((await tx.get(sessionRef)).exists) {
      logger.warn(`onSessionDeleted: session ${sessionId} exists again; its bids and seats are left alone`);
      return;
    }
    const bids = (await tx.get(sessionRef.collection("bids"))).docs;
    const seats = (await tx.get(sessionRef.collection("seats"))).docs;
    const active = bids.filter((bid) => bid.get("status") === "active");
    const refunds = data.auctionState === "settled" ? seats.filter((seat) => (seat.get("paid") ?? 0) > 0) : [];
    const teacherId = data.teacherId as string;
    const entries = refunds.length ? (await seatEntries(tx, teacherId, sessionId)).docs : [];
    const wallets = await Promise.all([...active, ...refunds].map((doc) => tx.get(walletRef(doc.id))));
    const teacherName = data.teacherName ?? "";
    const startsAt = data.startsAt ?? null;
    if (active.length || seats.length) {
      logger.warn(`onSessionDeleted: session ${sessionId} was deleted with ${active.length} active bids and ${seats.length} seats`);
    }

    let index = 0;
    for (const bid of active) {
      const amount = bid.get("amount") ?? 0;
      if (wallets[index++].exists && amount > 0) move(tx, bid.id, "release", { balance: amount, held: -amount }, amount, { sessionId });
      notify(tx, bid.id, { kind: "cancelled", sessionId, teacherName, amount, startsAt });
    }
    let reversed = 0;
    for (const seat of refunds) {
      const paid = seat.get("paid");
      if (wallets[index++].exists) move(tx, seat.id, "refund", { balance: paid }, paid, { sessionId, reason: "sessionDeleted" });
      const entry = entries.find((e) => e.get("studentUid") === seat.id);
      if (entry) {
        reversed += entry.get("amount");
        tx.create(db.collection(`teacherBalances/${teacherId}/entries`).doc(), {
          kind: "reversal", amount: -entry.get("amount"), sessionId, studentUid: seat.id, reason: "sessionDeleted", at: Timestamp.now(),
        });
      }
    }
    if (reversed > 0) {
      tx.set(db.doc(`teacherBalances/${teacherId}`), { earned: FieldValue.increment(-reversed), updatedAt: Timestamp.now() }, { merge: true });
    }
    for (const seat of seats) {
      notify(tx, seat.id, {
        kind: refunds.includes(seat) ? "refund" : "cancelled", sessionId, teacherName, amount: seat.get("paid") ?? 0, startsAt,
      });
      tx.delete(db.doc(`users/${seat.id}/bookings/${sessionId}`));
    }
    for (const orphan of [...bids, ...seats] as QueryDocumentSnapshot[]) tx.delete(orphan.ref);
    recordEvent(tx, event.id, { trigger: "onSessionDeleted", sessionId, bids: active.length, seats: seats.length });
  });
});
