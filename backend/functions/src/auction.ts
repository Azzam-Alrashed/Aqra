// The seat auction (docs/SRS.md AUC). A session may offer auctioned seats beside its free ones. They start free:
// while seats remain, any bid of at least the minimum holds one; once all are held, a new bid must beat the lowest
// by the increment, and outbids it. Bidding holds credits; an outbid hold is released at once; bidding closes
// before the session and the winners' holds are spent, their seats made, and the teacher's share recorded. Every
// bid runs in a Firestore transaction, so a seat is never won twice.
import { DocumentSnapshot, FieldValue, Timestamp, Transaction } from "firebase-admin/firestore";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "./admin.js";
import { policy } from "./policy.js";
import { move, notify, readWallet } from "./wallet.js";

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

    // Writes, once everything is read.
    if (hold > 0) move(tx, uid, "hold", { balance: -hold, held: hold }, hold, { sessionId });
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

/** Closes a session's auction: the winners' holds are spent, their seats and bookings made, and the teacher's share
 * recorded. Does nothing if it's not open or (unless forced) bidding hasn't closed. */
export async function settle(sessionId: string, { force = false } = {}): Promise<number> {
  const rules = await policy();
  const sessionRef = db.doc(`sessions/${sessionId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const session = await tx.get(sessionRef);
    if (!session.exists || session.get("auctionState") !== "open") return 0;
    const closesAt = (session.get("biddingClosesAt") as Timestamp).toMillis();
    if (!force && Date.now() < closesAt) return 0;
    const bids = (await tx.get(sessionRef.collection("bids").where("status", "==", "active"))).docs;
    const wallets = await Promise.all(bids.map((bid) => tx.get(db.doc(`wallets/${bid.id}`))));
    // A bidder may have taken a free seat after bidding; they keep it, and their bid is let go.
    const freeSeats = await Promise.all(bids.map((bid) => tx.get(sessionRef.collection("seats").doc(bid.id))));
    const teacherId = session.get("teacherId");
    const startsAt = session.get("startsAt");

    let won = 0;
    let earned = 0;
    bids.forEach((bid, index) => {
      const amount = bid.get("amount") as number;
      // A bidder whose account was deleted has no wallet left to spend from: no seat.
      if (!wallets[index].exists) {
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
      tx.update(bid.ref, { status: "won" });
      tx.set(sessionRef.collection("seats").doc(bid.id), {
        name: bid.get("name") ?? "", bookedAt: Timestamp.now(), memorizedPages: bid.get("memorizedPages") ?? 0, paid: amount,
        ...(bid.get("juzSummary") ? { juzSummary: bid.get("juzSummary") } : {}),
      });
      tx.set(db.doc(`users/${bid.id}/bookings/${sessionId}`), {
        teacherId, teacherName: session.get("teacherName") ?? "", startsAt, kind: session.get("kind") ?? "inPerson",
        place: session.get("place") ?? "",
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

/** Every five minutes, the auctions whose bidding has closed are settled. */
export const settleAuctions = onSchedule("every 5 minutes", async () => {
  const due = await db.collection("sessions").where("auctionState", "==", "open")
    .where("biddingClosesAt", "<=", Timestamp.now()).limit(50).get();
  for (const session of due.docs) await settle(session.id);
});

/** An administrator settles a session's auction now (and the tests do). */
export const settleAuctionNow = onCall(async (request) => {
  if (request.auth?.token.admin !== true) throw new HttpsError("permission-denied", "Administrators only.");
  const sessionId = request.data?.sessionId;
  if (typeof sessionId !== "string") throw new HttpsError("invalid-argument", "Which session?");
  return { won: await settle(sessionId, { force: true }) };
});

/** A session cancelled by its teacher: holds still open are released; credits already spent are refunded and the
 * teacher's share reversed; everyone who had a seat or a bid is told, with the session's start so the message can say
 * which one. */
export const onSessionChanged = onDocumentUpdated("sessions/{sessionId}", async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  if (!before || !after || before.get("status") === "cancelled" || after.get("status") !== "cancelled") return;
  const sessionRef = after.ref;
  const sessionId = event.params.sessionId;
  const teacherName = after.get("teacherName") ?? "";
  const startsAt = after.get("startsAt") ?? null;

  await db.runTransaction(async (tx) => {
    const session = await tx.get(sessionRef);
    const state = session.get("auctionState");
    const bids = state === "open" ? (await tx.get(sessionRef.collection("bids").where("status", "==", "active"))).docs : [];
    const seats = (await tx.get(sessionRef.collection("seats"))).docs;
    const refunds = state === "settled" ? seats.filter((seat) => (seat.get("paid") ?? 0) > 0) : [];
    const teacherId = session.get("teacherId");
    const entries = refunds.length
      ? (await tx.get(db.collection(`teacherBalances/${teacherId}/entries`).where("sessionId", "==", sessionId).where("kind", "==", "seat"))).docs
      : [];
    const wallets = await Promise.all([...bids, ...refunds].map((doc) => tx.get(db.doc(`wallets/${doc.id}`))));

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
      if (wallets[index++].exists) move(tx, seat.id, "refund", { balance: paid }, paid, { sessionId });
      const entry = entries.find((e) => e.get("studentUid") === seat.id);
      if (entry) {
        reversed += entry.get("amount");
        tx.create(db.collection(`teacherBalances/${teacherId}/entries`).doc(), {
          kind: "reversal", amount: -entry.get("amount"), sessionId, studentUid: seat.id, at: Timestamp.now(),
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
  });
});
