// Credits and the seat auction (functions/src/credits.ts, auction.ts, accounts.ts). Run with `npm run test:functions`.
import assert from "node:assert/strict";
import { after, beforeEach, describe, test } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import { adminAuth, adminDb, clearFirestore, client, closeClients, inMinutes, rejects } from "./helpers.js";

beforeEach(clearFirestore);
after(closeClients);

async function eventually(check, timeout = 10_000) {
  const start = Date.now();
  for (;;) {
    try {
      return await check();
    } catch (error) {
      if (Date.now() - start > timeout) throw error;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
  }
}

/** A signed transaction as Xcode's StoreKit testing makes it: not signed by Apple, in the Xcode environment. */
function xcodeTransaction(overrides = {}) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Date.now();
  return [
    encode({ alg: "ES256", typ: "JWT" }),
    encode({
      transactionId: `${now}${Math.random()}`.replace(".", ""), originalTransactionId: "1", bundleId: "com.azzamalrashed.aqra",
      productId: "aqra.credits.10", purchaseDate: now, originalPurchaseDate: now, quantity: 1, type: "Consumable",
      inAppOwnershipType: "PURCHASED", signedDate: now, environment: "Xcode", transactionReason: "PURCHASE", storefront: "SAU",
      storefrontId: "143479", price: 10000, currency: "SAR", ...overrides,
    }),
    "c2lnbmF0dXJl",
  ].join(".");
}

const wallet = async (uid) => (await adminDb.doc(`wallets/${uid}`).get()).data() ?? { balance: 0, held: 0 };

async function auctionSession(id, teacherId, overrides = {}) {
  await adminDb.doc(`sessions/${id}`).set({
    teacherId, teacherName: "الشيخ أحمد", startsAt: inMinutes(60 * 24), place: "", seats: 1, booked: 0, kind: "video",
    status: "open", createdAt: Timestamp.now(), auctionSeats: 2, minBid: 0, biddingClosesAt: inMinutes(60 * 20),
    auctionState: "open", ...overrides,
  });
}

describe("redeemPurchase", () => {
  test("a test purchase is credited once, to the account that made it", async () => {
    const alice = await client();
    const jws = xcodeTransaction();
    const first = await alice.call("redeemPurchase", { signedTransaction: jws });
    assert.deepEqual(first, { credits: 10, balance: 10, alreadyRedeemed: false });
    const again = await alice.call("redeemPurchase", { signedTransaction: jws });
    assert.equal(again.alreadyRedeemed, true);
    assert.equal((await wallet(alice.uid)).balance, 10);
    const ledger = await adminDb.collection(`wallets/${alice.uid}/ledger`).get();
    assert.equal(ledger.size, 1);
    assert.equal(ledger.docs[0].data().kind, "purchase");

    const bob = await client();
    await rejects(bob.call("redeemPurchase", { signedTransaction: jws }), "functions/permission-denied");
  });

  test("not for an anonymous account, an unknown product, another app or a refunded purchase", async () => {
    const anonymous = await client({ anonymous: true });
    await rejects(anonymous.call("redeemPurchase", { signedTransaction: xcodeTransaction() }), "functions/permission-denied");
    const alice = await client();
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction({ productId: "aqra.gold" }) }), "functions/invalid-argument");
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction({ bundleId: "com.other" }) }), "functions/permission-denied");
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction({ revocationDate: Date.now() }) }), "functions/failed-precondition");
    await rejects(alice.call("redeemPurchase", { signedTransaction: "not-a-jws" }), "functions/invalid-argument");
    // A sandbox purchase needs Apple's root certificates, which the emulators don't have.
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction({ environment: "Sandbox" }) }), "functions/failed-precondition");
  });
});

describe("the seat auction", () => {
  test("seats start free, then each new bid must beat the lowest, which is outbid and released", async () => {
    const teacher = await client();
    const [alice, bob, carol] = [await client(), await client(), await client()];
    await auctionSession("s1", teacher.uid);
    for (const user of [alice, bob, carol]) await adminDb.doc(`wallets/${user.uid}`).set({ balance: 10, held: 0 });

    await alice.call("placeBid", { sessionId: "s1", amount: 0, name: "Alice" });
    const bobFirst = await bob.call("placeBid", { sessionId: "s1", amount: 0, name: "Bob" });
    assert.equal(bobFirst.nextAtLeast, 1);
    await rejects(carol.call("placeBid", { sessionId: "s1", amount: 0, name: "Carol" }), "functions/failed-precondition");
    // Carol's 1 outbids the later of the two free holds: Bob's.
    await carol.call("placeBid", { sessionId: "s1", amount: 1, name: "Carol" });
    assert.equal((await adminDb.doc(`sessions/s1/bids/${bob.uid}`).get()).data().status, "outbid");
    assert.deepEqual(await wallet(carol.uid), { ...(await wallet(carol.uid)), balance: 9, held: 1 });
    // Bob comes back with 5, outbidding Alice's free hold; Carol raises hers, holding the difference.
    await bob.call("placeBid", { sessionId: "s1", amount: 5, name: "Bob" });
    assert.equal((await adminDb.doc(`sessions/s1/bids/${alice.uid}`).get()).data().status, "outbid");
    await carol.call("placeBid", { sessionId: "s1", amount: 3, name: "Carol" });
    assert.equal((await wallet(carol.uid)).held, 3);
    assert.equal((await wallet(carol.uid)).balance, 7);
    await rejects(carol.call("placeBid", { sessionId: "s1", amount: 3, name: "Carol" }), "functions/failed-precondition");
    // Alice must now beat Carol's 3, and can't bid more than she has.
    await rejects(alice.call("placeBid", { sessionId: "s1", amount: 3, name: "Alice" }), "functions/failed-precondition");
    await rejects(alice.call("placeBid", { sessionId: "s1", amount: 11, name: "Alice" }), "functions/failed-precondition");
    const session = (await adminDb.doc("sessions/s1").get()).data();
    assert.equal(session.auctionBids, 2);
    assert.equal(session.auctionFloor, 4);
    const outbid = await adminDb.collection(`users/${bob.uid}/inbox`).where("kind", "==", "outbid").get();
    assert.equal(outbid.size, 1);
    // The teacher doesn't bid; nobody bids once bidding has closed.
    await rejects(teacher.call("placeBid", { sessionId: "s1", amount: 9, name: "x" }), "functions/failed-precondition");
    await adminDb.doc("sessions/s1").update({ biddingClosesAt: inMinutes(-1) });
    await rejects(alice.call("placeBid", { sessionId: "s1", amount: 9, name: "Alice" }), "functions/failed-precondition");
  });

  test("settling spends the winners' holds, makes their seats and bookings, and records the teacher's share", async () => {
    const teacher = await client();
    const admin = await client({ admin: true });
    const [bob, carol] = [await client(), await client()];
    await auctionSession("s1", teacher.uid);
    for (const user of [bob, carol]) await adminDb.doc(`wallets/${user.uid}`).set({ balance: 10, held: 0 });
    await bob.call("placeBid", { sessionId: "s1", amount: 5, name: "Bob" });
    await carol.call("placeBid", { sessionId: "s1", amount: 0, name: "Carol" });

    await rejects(bob.call("settleAuctionNow", { sessionId: "s1" }), "functions/permission-denied");
    assert.deepEqual(await admin.call("settleAuctionNow", { sessionId: "s1" }), { won: 2 });
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [5, 0]);
    const seat = (await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).data();
    assert.equal(seat.paid, 5);
    assert.equal((await adminDb.doc(`users/${carol.uid}/bookings/s1`).get()).data().teacherId, teacher.uid);
    const balance = (await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data();
    assert.equal(balance.earned, 4);
    assert.equal((await adminDb.doc("sessions/s1").get()).data().auctionState, "settled");
    assert.deepEqual(await admin.call("settleAuctionNow", { sessionId: "s1" }), { won: 0 });

    // The teacher cancels: the credits spent come back and the share is reversed.
    await adminDb.doc("sessions/s1").update({ status: "cancelled" });
    await eventually(async () => assert.equal((await wallet(bob.uid)).balance, 10));
    await eventually(async () => assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 0));
    assert.equal((await adminDb.doc("sessions/s1").get()).data().auctionState, "refunded");
    const refund = await adminDb.collection(`users/${bob.uid}/inbox`).where("kind", "==", "refund").get();
    assert.equal(refund.size, 1);
    // The message says which session: its start.
    const startsAt = (await adminDb.doc("sessions/s1").get()).data().startsAt;
    assert.equal(refund.docs[0].data().startsAt.toMillis(), startsAt.toMillis());
  });

  test("a bidder who took a free seat meanwhile keeps it, and isn't charged for another", async () => {
    const teacher = await client();
    const admin = await client({ admin: true });
    const bob = await client();
    await auctionSession("s1", teacher.uid);
    await adminDb.doc(`wallets/${bob.uid}`).set({ balance: 10, held: 0 });
    await bob.call("placeBid", { sessionId: "s1", amount: 3, name: "Bob" });
    // Bob books the free seat after bidding, as the app lets him.
    await adminDb.doc(`sessions/s1/seats/${bob.uid}`).set({ name: "Bob", bookedAt: Timestamp.now(), memorizedPages: 1 });
    await adminDb.doc("sessions/s1").update({ booked: 1 });

    assert.deepEqual(await admin.call("settleAuctionNow", { sessionId: "s1" }), { won: 0 });
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]);
    assert.equal((await adminDb.doc(`sessions/s1/bids/${bob.uid}`).get()).data().status, "released");
    assert.equal((await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).data().paid, undefined);
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).exists, false);
  });

  test("a bidder takes a free seat instead: the bid is let go and its credits come back, in one call", async () => {
    const teacher = await client();
    const bob = await client();
    const carol = await client();
    await auctionSession("s1", teacher.uid, { seats: 1, auctionSeats: 1 });
    await adminDb.doc(`wallets/${bob.uid}`).set({ balance: 10, held: 0 });
    await adminDb.doc(`wallets/${carol.uid}`).set({ balance: 10, held: 0 });
    await bob.call("placeBid", { sessionId: "s1", amount: 4, name: "Bob" });
    assert.equal((await adminDb.doc("sessions/s1").get()).data().auctionFloor, 5);

    assert.deepEqual(await bob.call("takeFreeSeat", { sessionId: "s1", name: "Bob", memorizedPages: 3 }), { released: 4 });
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]);
    assert.equal((await adminDb.doc(`sessions/s1/bids/${bob.uid}`).get()).data().status, "released");
    assert.equal((await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).data().memorizedPages, 3);
    assert.equal((await adminDb.doc(`users/${bob.uid}/bookings/s1`).get()).data().teacherId, teacher.uid);
    const session = (await adminDb.doc("sessions/s1").get()).data();
    assert.deepEqual([session.booked, session.auctionBids, session.auctionFloor], [1, 0, 0]);
    // The seat is his now: no bidding beside it, no second seat, and the last free seat is gone for others.
    await rejects(bob.call("placeBid", { sessionId: "s1", amount: 1, name: "Bob" }), "functions/failed-precondition");
    await rejects(bob.call("takeFreeSeat", { sessionId: "s1", name: "Bob" }), "functions/failed-precondition");
    await rejects(carol.call("takeFreeSeat", { sessionId: "s1", name: "Carol" }), "functions/failed-precondition");
    // Settling finds no bid to charge him for.
    const admin = await client({ admin: true });
    assert.deepEqual(await admin.call("settleAuctionNow", { sessionId: "s1" }), { won: 0 });
    assert.equal((await wallet(bob.uid)).balance, 10);
  });

  test("taking a free seat needs a named account and an open session", async () => {
    const teacher = await client();
    const anonymous = await client({ anonymous: true });
    const bob = await client();
    await auctionSession("s1", teacher.uid, { status: "cancelled" });
    await rejects(anonymous.call("takeFreeSeat", { sessionId: "s1" }), "functions/permission-denied");
    await rejects(bob.call("takeFreeSeat", { sessionId: "s1" }), "functions/failed-precondition");
    await rejects(bob.call("takeFreeSeat", { sessionId: "nope" }), "functions/not-found");
    await rejects(teacher.call("takeFreeSeat", { sessionId: "s1" }), "functions/failed-precondition");
  });

  test("cancelling while bidding is open releases every hold", async () => {
    const teacher = await client();
    const bob = await client();
    await auctionSession("s1", teacher.uid);
    await adminDb.doc(`wallets/${bob.uid}`).set({ balance: 10, held: 0 });
    await bob.call("placeBid", { sessionId: "s1", amount: 4, name: "Bob" });
    await adminDb.doc("sessions/s1").update({ status: "cancelled" });
    await eventually(async () => assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]));
    assert.equal((await adminDb.doc(`sessions/s1/bids/${bob.uid}`).get()).data().status, "released");
    assert.equal((await adminDb.doc("sessions/s1").get()).data().auctionState, "cancelled");
    const message = (await adminDb.collection(`users/${bob.uid}/inbox`).where("kind", "==", "cancelled").get()).docs[0].data();
    assert.equal(message.amount, 4);
    assert.equal(message.startsAt.toMillis(), (await adminDb.doc("sessions/s1").get()).data().startsAt.toMillis());
  });

  test("a deleted account's wallet goes with it, and its application in any state", async () => {
    const bob = await client();
    await adminDb.doc(`wallets/${bob.uid}`).set({ balance: 10, held: 0 });
    await adminDb.doc(`wallets/${bob.uid}/ledger/l1`).set({ kind: "purchase", amount: 10 });
    await adminDb.doc(`teacherApplications/${bob.uid}`).set({ name: "Bob", status: "approved", note: "" });
    await adminAuth.deleteUser(bob.uid);
    await eventually(async () => assert.equal((await adminDb.doc(`wallets/${bob.uid}`).get()).exists, false));
    assert.equal((await adminDb.collection(`wallets/${bob.uid}/ledger`).get()).size, 0);
    await eventually(async () => assert.equal((await adminDb.doc(`teacherApplications/${bob.uid}`).get()).exists, false));
  });
});
