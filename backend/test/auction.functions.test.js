// Credits and the seat auction (functions/src/credits.ts, auction.ts, accounts.ts). Run with `npm run test:functions`.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, beforeEach, describe, test } from "node:test";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  accountToken, adminAuth, adminDb, clearFirestore, client, closeClients, FUNCTIONS_URL, inMinutes, rejects, runSchedule,
} from "./helpers.js";

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

/** A JWS nobody signed, as Xcode's StoreKit testing makes them; the functions trust it only on the emulators. */
function unsignedJWS(payload) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return [encode({ alg: "ES256", typ: "JWT" }), encode(payload), "c2lnbmF0dXJl"].join(".");
}

/** A signed transaction as Xcode's StoreKit testing makes it: not signed by Apple, in the Xcode environment, carrying
 * the account token the app attaches for `uid`. */
function xcodeTransaction(uid, overrides = {}) {
  const now = Date.now();
  return unsignedJWS({
    transactionId: `${now}${Math.random()}`.replace(".", ""), originalTransactionId: "1", bundleId: "com.azzamalrashed.aqra",
    productId: "aqra.credits.10", purchaseDate: now, originalPurchaseDate: now, quantity: 1, type: "Consumable",
    inAppOwnershipType: "PURCHASED", signedDate: now, environment: "Xcode", transactionReason: "PURCHASE", storefront: "SAU",
    storefrontId: "143479", price: 10000, currency: "SAR", ...(uid ? { appAccountToken: accountToken(uid) } : {}), ...overrides,
  });
}

/** An App Store Server Notification (version 2) about a transaction, as Apple would send it for the Xcode environment. */
function notification(type, signedTransactionInfo, { environment = "Xcode" } = {}) {
  return unsignedJWS({
    notificationType: type, notificationUUID: randomUUID(), version: "2.0", signedDate: Date.now(),
    data: { environment, bundleId: "com.azzamalrashed.aqra", bundleVersion: "1", signedTransactionInfo },
  });
}

/** Posts to the notifications endpoint, as Apple does. */
async function notify(signedPayload, init = {}) {
  return fetch(`${FUNCTIONS_URL}/appStoreNotifications`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ signedPayload }), ...init,
  });
}

const transactionId = (jws) => JSON.parse(Buffer.from(jws.split(".")[1], "base64url").toString()).transactionId;

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
    const jws = xcodeTransaction(alice.uid);
    const first = await alice.call("redeemPurchase", { signedTransaction: jws });
    assert.deepEqual(first, { credits: 10, balance: 10, alreadyRedeemed: false });
    const again = await alice.call("redeemPurchase", { signedTransaction: jws });
    assert.equal(again.alreadyRedeemed, true);
    assert.equal((await wallet(alice.uid)).balance, 10);
    const ledger = await adminDb.collection(`wallets/${alice.uid}/ledger`).get();
    assert.equal(ledger.size, 1);
    assert.equal(ledger.docs[0].data().kind, "purchase");

    // Another account can't redeem it: the purchase carries Alice's token, and is hers once credited.
    const bob = await client();
    await rejects(bob.call("redeemPurchase", { signedTransaction: jws }), "functions/permission-denied");
    await adminDb.doc(`purchases/${transactionId(jws)}`).update({ uid: bob.uid });
    await rejects(alice.call("redeemPurchase", { signedTransaction: jws }), "functions/permission-denied");
  });

  test("a purchase without its account's token, or with another's, isn't redeemed", async () => {
    const alice = await client();
    const bob = await client();
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(undefined) }), "functions/permission-denied");
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(bob.uid) }), "functions/permission-denied");
    // The token is a UUID in any letter case.
    const upper = xcodeTransaction(alice.uid, { appAccountToken: accountToken(alice.uid).toUpperCase() });
    assert.equal((await alice.call("redeemPurchase", { signedTransaction: upper })).credits, 10);
  });

  test("not for an anonymous account, an unknown product, another app or a refunded purchase", async () => {
    const anonymous = await client({ anonymous: true });
    await rejects(anonymous.call("redeemPurchase", { signedTransaction: xcodeTransaction(anonymous.uid) }), "functions/permission-denied");
    const alice = await client();
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(alice.uid, { productId: "aqra.gold" }) }), "functions/invalid-argument");
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(alice.uid, { bundleId: "com.other" }) }), "functions/permission-denied");
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(alice.uid, { revocationDate: Date.now() }) }), "functions/failed-precondition");
    await rejects(alice.call("redeemPurchase", { signedTransaction: "not-a-jws" }), "functions/invalid-argument");
  });

  test("aSandboxPurchaseIsRefusedInProduction", async () => {
    // Apple's sandbox (TestFlight, App Review) is refused unless the policy allows it; allowed, its purchases are
    // verified like production ones, which needs Apple's root certificates (not on the emulators).
    const alice = await client();
    const sandbox = xcodeTransaction(alice.uid, { environment: "Sandbox" });
    await rejects(alice.call("redeemPurchase", { signedTransaction: sandbox }), "functions/permission-denied");
    await adminDb.doc("config/policy").set({ allowSandboxPurchases: true });
    await rejects(alice.call("redeemPurchase", { signedTransaction: sandbox }), "functions/failed-precondition");
    await adminDb.doc("config/policy").delete();
    await rejects(alice.call("redeemPurchase", { signedTransaction: sandbox }), "functions/permission-denied");
    // A production purchase, too, waits for the certificates; an unknown environment is no App Store transaction.
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(alice.uid, { environment: "Production" }) }), "functions/failed-precondition");
    await rejects(alice.call("redeemPurchase", { signedTransaction: xcodeTransaction(alice.uid, { environment: "Elsewhere" }) }), "functions/invalid-argument");
  });
});

describe("appStoreNotifications", () => {
  test("aRefundNotificationClawsBackCredits", async () => {
    const alice = await client();
    const jws = xcodeTransaction(alice.uid);
    await alice.call("redeemPurchase", { signedTransaction: jws });
    assert.equal((await wallet(alice.uid)).balance, 10);

    const refunded = xcodeTransaction(alice.uid, { transactionId: transactionId(jws), revocationDate: Date.now(), revocationReason: 0 });
    const response = await notify(notification("REFUND", refunded));
    assert.equal(response.status, 200);
    assert.equal((await wallet(alice.uid)).balance, 0);
    const ledger = await adminDb.collection(`wallets/${alice.uid}/ledger`).where("kind", "==", "clawback").get();
    assert.equal(ledger.size, 1);
    assert.deepEqual([ledger.docs[0].data().amount, ledger.docs[0].data().transactionId], [10, transactionId(jws)]);
    const purchase = (await adminDb.doc(`purchases/${transactionId(jws)}`).get()).data();
    assert.ok(purchase.revokedAt);
    assert.equal(purchase.revocation, "REFUND");
    // Delivered again: nothing is taken twice. Redeemed again by the app: refused.
    assert.equal((await notify(notification("REFUND", refunded))).status, 200);
    assert.equal((await wallet(alice.uid)).balance, 0);
    assert.equal((await adminDb.collection(`wallets/${alice.uid}/ledger`).get()).size, 2);
    await rejects(alice.call("redeemPurchase", { signedTransaction: jws }), "functions/failed-precondition");
  });

  test("a revoked purchase never credited can't be redeemed afterwards; other notifications are acknowledged", async () => {
    const alice = await client();
    const jws = xcodeTransaction(alice.uid);
    assert.equal((await notify(notification("REVOKE", jws))).status, 200);
    await rejects(alice.call("redeemPurchase", { signedTransaction: jws }), "functions/failed-precondition");
    assert.equal((await wallet(alice.uid)).balance, 0);
    // Apple's TEST notification, and types this app has no use for.
    assert.equal((await notify(unsignedJWS({ notificationType: "TEST", notificationUUID: randomUUID(), version: "2.0", signedDate: Date.now(),
      data: { environment: "Xcode", bundleId: "com.azzamalrashed.aqra" } }))).status, 200);
    assert.equal((await notify(notification("ONE_TIME_CHARGE", xcodeTransaction(alice.uid)))).status, 200);
    // Spending the credits first leaves the balance below zero: the debt is recorded, not forgiven.
    const bought = xcodeTransaction(alice.uid);
    await alice.call("redeemPurchase", { signedTransaction: bought });
    await adminDb.doc(`wallets/${alice.uid}`).update({ balance: 4 });
    assert.equal((await notify(notification("REFUND", xcodeTransaction(alice.uid, { transactionId: transactionId(bought), revocationDate: Date.now() })))).status, 200);
    assert.equal((await wallet(alice.uid)).balance, -6);
  });

  test("only verified payloads: another app's, an unsigned production one, or no payload at all", async () => {
    const alice = await client();
    assert.equal((await fetch(`${FUNCTIONS_URL}/appStoreNotifications`)).status, 405);
    assert.equal((await notify(undefined)).status, 400);
    assert.equal((await notify("not-a-jws")).status, 400);
    const otherApp = unsignedJWS({ notificationType: "REFUND", notificationUUID: randomUUID(), version: "2.0", signedDate: Date.now(),
      data: { environment: "Xcode", bundleId: "com.other", signedTransactionInfo: xcodeTransaction(alice.uid) } });
    assert.equal((await notify(otherApp)).status, 401);
    // A sandbox or production notification is verified against Apple's certificates, which the emulators don't have.
    assert.equal((await notify(notification("REFUND", xcodeTransaction(alice.uid), { environment: "Sandbox" }))).status, 503);
    assert.equal((await notify(notification("REFUND", xcodeTransaction(alice.uid), { environment: "Production" }))).status, 503);
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
    const booking = (await adminDb.doc(`users/${carol.uid}/bookings/s1`).get()).data();
    assert.deepEqual([booking.teacherId, booking.paid], [teacher.uid, 0]);
    assert.equal((await adminDb.doc(`users/${bob.uid}/bookings/s1`).get()).data().paid, 5);
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

  test("aZeroBidWithoutAWalletWinsAnAuctionSeat", async () => {
    const teacher = await client();
    const admin = await client({ admin: true });
    const [alice, bob, carol] = [await client(), await client(), await client()];
    await auctionSession("s1", teacher.uid, { auctionSeats: 3 });
    // Alice never bought credits: her free bid gives her an empty wallet, which marks her as still here.
    assert.equal((await adminDb.doc(`wallets/${alice.uid}`).get()).exists, false);
    await alice.call("placeBid", { sessionId: "s1", amount: 0, name: "Alice" });
    assert.deepEqual([(await wallet(alice.uid)).balance, (await wallet(alice.uid)).held], [0, 0]);
    assert.equal((await adminDb.doc(`wallets/${alice.uid}`).get()).exists, true);
    assert.equal((await adminDb.collection(`wallets/${alice.uid}/ledger`).get()).size, 0);
    // Bob's bid predates wallets for free bids; Carol bid, then deleted her account.
    for (const user of [bob, carol]) {
      await adminDb.doc(`sessions/s1/bids/${user.uid}`).set({ name: "x", amount: 0, at: Timestamp.now(), status: "active", memorizedPages: 0 });
    }
    await adminAuth.deleteUser(carol.uid);

    assert.deepEqual(await admin.call("settleAuctionNow", { sessionId: "s1" }), { won: 2 });
    assert.equal((await adminDb.doc(`sessions/s1/seats/${alice.uid}`).get()).data().paid, 0);
    assert.equal((await adminDb.doc(`users/${alice.uid}/bookings/s1`).get()).data().teacherId, teacher.uid);
    assert.equal((await adminDb.doc(`sessions/s1/bids/${alice.uid}`).get()).data().status, "won");
    assert.equal((await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).exists, true);
    assert.equal((await adminDb.doc(`wallets/${bob.uid}`).get()).exists, true);
    assert.equal((await adminDb.doc(`sessions/s1/bids/${carol.uid}`).get()).data().status, "released");
    assert.equal((await adminDb.doc(`sessions/s1/seats/${carol.uid}`).get()).exists, false);
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).exists, false);
  });

  test("aCancelledSessionIsNeverSettled", async () => {
    // The teacher cancelled, but the cancellation's trigger never ran: the holds are still open when bidding closes.
    const teacher = await client();
    const admin = await client({ admin: true });
    const bob = await client();
    await auctionSession("s1", teacher.uid, { status: "cancelled", biddingClosesAt: inMinutes(-5) });
    await adminDb.doc(`wallets/${bob.uid}`).set({ balance: 6, held: 4 });
    await adminDb.doc(`sessions/s1/bids/${bob.uid}`).set({ name: "Bob", amount: 4, at: Timestamp.now(), status: "active", memorizedPages: 0 });

    assert.deepEqual(await admin.call("settleAuctionNow", { sessionId: "s1" }), { won: 0 });
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [6, 4]);
    assert.equal((await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).exists, false);
    assert.equal((await adminDb.doc("sessions/s1").get()).data().auctionState, "open");
    // The scheduled run finds it and releases the holds instead of charging them.
    await runSchedule("settleAuctions");
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]);
    assert.equal((await adminDb.doc(`sessions/s1/bids/${bob.uid}`).get()).data().status, "released");
    assert.equal((await adminDb.doc("sessions/s1").get()).data().auctionState, "cancelled");
    assert.equal((await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).exists, false);
  });

  test("settleAuctionsContinuesPastAFailure", async () => {
    const teacher = await client();
    const [bob, carol] = [await client(), await client()];
    for (const user of [bob, carol]) await adminDb.doc(`wallets/${user.uid}`).set({ balance: 10, held: 0 });
    // A session with no start (nothing the apps write; a corrupt record) fails to settle: its winner's booking can't
    // be made. It comes first, and the healthy session after it is settled all the same.
    await auctionSession("broken", teacher.uid, { biddingClosesAt: inMinutes(60) });
    await bob.call("placeBid", { sessionId: "broken", amount: 2, name: "Bob" });
    await adminDb.doc("sessions/broken").update({ startsAt: FieldValue.delete(), biddingClosesAt: inMinutes(-10) });
    await auctionSession("fine", teacher.uid, { biddingClosesAt: inMinutes(60) });
    await carol.call("placeBid", { sessionId: "fine", amount: 3, name: "Carol" });
    await adminDb.doc("sessions/fine").update({ biddingClosesAt: inMinutes(-5) });
    // Not yet due: left alone.
    await auctionSession("later", teacher.uid, { biddingClosesAt: inMinutes(30) });

    await runSchedule("settleAuctions");
    assert.equal((await adminDb.doc("sessions/fine").get()).data().auctionState, "settled");
    assert.equal((await adminDb.doc(`sessions/fine/seats/${carol.uid}`).get()).data().paid, 3);
    assert.deepEqual([(await wallet(carol.uid)).balance, (await wallet(carol.uid)).held], [7, 0]);
    assert.equal((await adminDb.doc("sessions/broken").get()).data().auctionState, "open");
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [8, 2]);
    assert.equal((await adminDb.doc("sessions/later").get()).data().auctionState, "open");
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

  test("cancelling while bidding is open releases every hold, once per event", async () => {
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
    // The trigger's event is recorded with its work, so a second delivery would find it and do nothing.
    const events = await adminDb.collection("functionEvents").where("sessionId", "==", "s1").get();
    assert.equal(events.size, 1);
    assert.equal(events.docs[0].data().trigger, "onSessionChanged");
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

describe("giving a seat back", () => {
  test("a free seat goes back with the student's copy and the count, which never drops below zero", async () => {
    const teacher = await client();
    const bob = await client();
    await auctionSession("s1", teacher.uid, { seats: 2 });
    await bob.call("takeFreeSeat", { sessionId: "s1", name: "Bob", memorizedPages: 3 });
    assert.equal((await adminDb.doc("sessions/s1").get()).data().booked, 1);

    assert.deepEqual(await bob.call("giveBackSeat", { sessionId: "s1" }), { refunded: 0 });
    assert.equal((await adminDb.doc(`sessions/s1/seats/${bob.uid}`).get()).exists, false);
    assert.equal((await adminDb.doc(`users/${bob.uid}/bookings/s1`).get()).exists, false);
    assert.equal((await adminDb.doc("sessions/s1").get()).data().booked, 0);
    // Again, with nothing left: nothing happens, and the count stays at zero.
    assert.deepEqual(await bob.call("giveBackSeat", { sessionId: "s1" }), { refunded: 0 });
    assert.equal((await adminDb.doc("sessions/s1").get()).data().booked, 0);
    // A seat whose count was already lost: the count stays at zero rather than going below it.
    await adminDb.doc(`sessions/s1/seats/${bob.uid}`).set({ name: "Bob", bookedAt: Timestamp.now(), memorizedPages: 3 });
    assert.deepEqual(await bob.call("giveBackSeat", { sessionId: "s1" }), { refunded: 0 });
    assert.equal((await adminDb.doc("sessions/s1").get()).data().booked, 0);
    // A booking whose session is gone: the copy goes.
    await adminDb.doc(`users/${bob.uid}/bookings/gone`).set({ teacherId: teacher.uid, teacherName: "x", startsAt: inMinutes(60), place: "" });
    assert.deepEqual(await bob.call("giveBackSeat", { sessionId: "gone" }), { refunded: 0 });
    assert.equal((await adminDb.doc(`users/${bob.uid}/bookings/gone`).get()).exists, false);
    await rejects(bob.call("giveBackSeat", {}), "functions/invalid-argument");
  });

  test("a seat won at auction is refunded when given back in time, with the teacher's share reversed; late, the credits stay", async () => {
    const teacher = await client();
    const admin = await client({ admin: true });
    const [bob, carol] = [await client(), await client()];
    for (const user of [bob, carol]) await adminDb.doc(`wallets/${user.uid}`).set({ balance: 10, held: 0 });
    // Tomorrow's session: Bob wins with 5 and gives the seat back a day ahead.
    await auctionSession("early", teacher.uid, { auctionSeats: 1 });
    await bob.call("placeBid", { sessionId: "early", amount: 5, name: "Bob" });
    await admin.call("settleAuctionNow", { sessionId: "early" });
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 4);
    // Not through the rules' path: the function is the only way.
    assert.deepEqual(await bob.call("giveBackSeat", { sessionId: "early" }), { refunded: 5 });
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]);
    assert.equal((await adminDb.doc(`sessions/early/seats/${bob.uid}`).get()).exists, false);
    assert.equal((await adminDb.doc(`users/${bob.uid}/bookings/early`).get()).exists, false);
    const early = (await adminDb.doc("sessions/early").get()).data();
    assert.deepEqual([early.auctionWon, early.booked, early.auctionState], [0, 0, "settled"]);
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 0);
    const reversal = await adminDb.collection(`teacherBalances/${teacher.uid}/entries`).where("kind", "==", "reversal").get();
    assert.deepEqual([reversal.size, reversal.docs[0].data().amount, reversal.docs[0].data().reason], [1, -4, "seatGivenBack"]);
    const refund = await adminDb.collection(`wallets/${bob.uid}/ledger`).where("kind", "==", "refund").get();
    assert.deepEqual([refund.docs[0].data().amount, refund.docs[0].data().reason], [5, "seatGivenBack"]);
    // Cancelling afterwards refunds nobody twice.
    await adminDb.doc("sessions/early").update({ status: "cancelled" });
    await eventually(async () => assert.equal((await adminDb.doc("sessions/early").get()).data().auctionState, "refunded"));
    assert.equal((await wallet(bob.uid)).balance, 10);

    // A session in half an hour: Carol wins with 3 and gives the seat back too late for a refund.
    await auctionSession("late", teacher.uid, { auctionSeats: 1, startsAt: inMinutes(30), biddingClosesAt: inMinutes(5) });
    await carol.call("placeBid", { sessionId: "late", amount: 3, name: "Carol" });
    await admin.call("settleAuctionNow", { sessionId: "late" });
    assert.deepEqual(await carol.call("giveBackSeat", { sessionId: "late" }), { refunded: 0 });
    assert.deepEqual([(await wallet(carol.uid)).balance, (await wallet(carol.uid)).held], [7, 0]);
    assert.equal((await adminDb.doc(`sessions/late/seats/${carol.uid}`).get()).exists, false);
    assert.equal((await adminDb.doc(`users/${carol.uid}/bookings/late`).get()).exists, false);
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 2.4);
  });

  test("the teacher gives a student's seat back, which always refunds; nobody else does", async () => {
    const teacher = await client();
    const admin = await client({ admin: true });
    const [bob, stranger] = [await client(), await client()];
    await adminDb.doc(`wallets/${bob.uid}`).set({ balance: 10, held: 0 });
    await auctionSession("late", teacher.uid, { auctionSeats: 1, startsAt: inMinutes(30), biddingClosesAt: inMinutes(5) });
    await bob.call("placeBid", { sessionId: "late", amount: 4, name: "Bob" });
    await admin.call("settleAuctionNow", { sessionId: "late" });
    await rejects(stranger.call("giveBackSeat", { sessionId: "late", studentUid: bob.uid }), "functions/permission-denied");
    assert.deepEqual(await teacher.call("giveBackSeat", { sessionId: "late", studentUid: bob.uid }), { refunded: 4 });
    assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]);
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 0);
    assert.equal((await adminDb.doc(`sessions/late/seats/${bob.uid}`).get()).exists, false);
    // In a cancelled session, the cancellation refunded already: only the student's copy goes.
    await auctionSession("cancelled", teacher.uid, { status: "cancelled", auctionState: "refunded" });
    await adminDb.doc(`sessions/cancelled/seats/${bob.uid}`).set({ name: "Bob", bookedAt: Timestamp.now(), memorizedPages: 1, paid: 2 });
    await adminDb.doc(`users/${bob.uid}/bookings/cancelled`).set({ teacherId: teacher.uid, teacherName: "x", startsAt: inMinutes(60), place: "" });
    assert.deepEqual(await bob.call("giveBackSeat", { sessionId: "cancelled" }), { refunded: 0 });
    assert.equal((await adminDb.doc(`users/${bob.uid}/bookings/cancelled`).get()).exists, false);
    assert.equal((await wallet(bob.uid)).balance, 10);
  });
});

describe("a session deleted outright", () => {
  test("releases the holds, refunds the paid seats, tells everyone and clears what's left", async () => {
    const teacher = await client();
    const admin = await client({ admin: true });
    const [bob, carol] = [await client(), await client()];
    for (const user of [bob, carol]) await adminDb.doc(`wallets/${user.uid}`).set({ balance: 10, held: 0 });
    // Bidding open, with Bob's hold.
    await auctionSession("open", teacher.uid);
    await bob.call("placeBid", { sessionId: "open", amount: 4, name: "Bob" });
    // Settled, with Carol's paid seat and the teacher's share.
    await auctionSession("settled", teacher.uid, { auctionSeats: 1 });
    await carol.call("placeBid", { sessionId: "settled", amount: 5, name: "Carol" });
    await admin.call("settleAuctionNow", { sessionId: "settled" });
    assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 4);

    await adminDb.doc("sessions/open").delete();
    await adminDb.doc("sessions/settled").delete();
    await eventually(async () => assert.deepEqual([(await wallet(bob.uid)).balance, (await wallet(bob.uid)).held], [10, 0]));
    await eventually(async () => assert.equal((await wallet(carol.uid)).balance, 10));
    await eventually(async () => assert.equal((await adminDb.doc(`teacherBalances/${teacher.uid}`).get()).data().earned, 0));
    assert.equal((await adminDb.collection("sessions/open/bids").get()).size, 0);
    assert.equal((await adminDb.collection("sessions/settled/seats").get()).size, 0);
    assert.equal((await adminDb.collection("sessions/settled/bids").get()).size, 0);
    assert.equal((await adminDb.doc(`users/${carol.uid}/bookings/settled`).get()).exists, false);
    assert.equal((await adminDb.collection(`users/${bob.uid}/inbox`).where("kind", "==", "cancelled").get()).size, 1);
    assert.equal((await adminDb.collection(`users/${carol.uid}/inbox`).where("kind", "==", "refund").get()).size, 1);
    const events = await adminDb.collection("functionEvents").where("trigger", "==", "onSessionDeleted").get();
    assert.equal(events.size, 2);
  });
});
