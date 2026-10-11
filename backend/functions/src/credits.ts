// Buying credits: an App Store consumable, credited once its signed transaction is verified (docs/SRS.md PAY-02).
// Production and sandbox purchases are verified against Apple's root certificates, kept in functions/certs; the
// sandbox (TestFlight, App Review) is accepted only while the policy allows it; a purchase from Xcode's local StoreKit
// testing is accepted only on the emulators. A purchase is redeemed only by the account that made it: the app
// attaches the account's token to every purchase. Apple's refunds and revocations arrive as App Store Server
// Notifications and take the credits back (PAY-05).
import { Environment, JWSTransactionDecodedPayload, NotificationTypeV2, SignedDataVerifier } from "@apple/app-store-server-library";
import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineString } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { db } from "./admin.js";
import { Policy, policy } from "./policy.js";
import { move, readWallet } from "./wallet.js";

const bundleId = defineString("APPLE_BUNDLE_ID", { default: "com.azzamalrashed.aqra" });
/** The app's App Store id, once it's created in App Store Connect (required to verify production purchases). */
const appAppleId = defineString("APPLE_APP_ID", { default: "" });

const isEmulator = () => process.env.FUNCTIONS_EMULATOR === "true";

function rootCertificates(): Buffer[] {
  const directory = new URL("../certs/", import.meta.url);
  try {
    return readdirSync(directory).filter((name) => name.endsWith(".cer")).map((name) => readFileSync(new URL(name, directory)));
  } catch {
    return [];
  }
}

/** What a JWS claims, read before it's verified (to pick the verifier) and never trusted on its own. */
function claimed(jws: string): Record<string, any> | undefined {
  try {
    return JSON.parse(Buffer.from(jws.split(".")[1], "base64url").toString("utf8"));
  } catch {
    return undefined;
  }
}

/** The verifier for the environment a signed payload claims to come from. Xcode's StoreKit testing signs nothing, so
 * it's trusted only on the emulators, whatever the policy says. The sandbox is Apple's test store: its purchases are
 * accepted only while `allowSandboxPurchases` is on (a notification taking credits back is always heard). Production
 * needs Apple's root certificates in functions/certs. */
export function verifierFor(environment: unknown, rules: Policy, { notification = false } = {}): SignedDataVerifier {
  if (environment === Environment.XCODE) {
    if (!isEmulator()) throw new HttpsError("permission-denied", "Test purchases aren't accepted here.");
    return new SignedDataVerifier([], false, Environment.XCODE, bundleId.value());
  }
  if (environment === Environment.SANDBOX || environment === Environment.PRODUCTION) {
    if (environment === Environment.SANDBOX && !notification && !rules.allowSandboxPurchases) {
      throw new HttpsError("permission-denied", "Sandbox purchases aren't accepted here.");
    }
    const certificates = rootCertificates();
    if (!certificates.length) throw new HttpsError("failed-precondition", "App Store verification isn't set up.");
    // The app id is checked in production only; the sandbox doesn't carry it.
    const appId = environment === Environment.PRODUCTION && appAppleId.value() ? Number(appAppleId.value()) : undefined;
    return new SignedDataVerifier(certificates, true, environment, bundleId.value(), appId);
  }
  throw new HttpsError("invalid-argument", "That isn't an App Store transaction.");
}

/** The token the app attaches to a purchase (StoreKit's `appAccountToken`), so a purchase is redeemed only by the
 * account that made it: a UUID made from the account's uid, the first 16 bytes of its SHA-256 with the UUID version
 * and variant bits set. The iOS app derives it the same way (WalletStore.accountToken). */
export function accountToken(uid: string): string {
  const bytes = createHash("sha256").update(uid, "utf8").digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export interface RedeemResult {
  credits: number;
  balance: number;
  /** Whether this transaction had been credited already (the app retried); nothing was added twice. */
  alreadyRedeemed: boolean;
}

export const redeemPurchase = onCall(async (request): Promise<RedeemResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (request.auth?.token.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("permission-denied", "Credits need a signed-in account.");
  }
  const jws = request.data?.signedTransaction;
  if (typeof jws !== "string") throw new HttpsError("invalid-argument", "Which purchase?");

  const rules = await policy();
  const environment = claimed(jws)?.environment;
  const verifier = verifierFor(environment, rules);
  let transaction: JWSTransactionDecodedPayload;
  try {
    transaction = await verifier.verifyAndDecodeTransaction(jws);
  } catch {
    throw new HttpsError("permission-denied", "The purchase couldn't be verified.");
  }
  const credits = rules.creditPacks[transaction.productId ?? ""];
  if (!credits || !transaction.transactionId) throw new HttpsError("invalid-argument", "That isn't a credit pack.");
  if (transaction.revocationDate) throw new HttpsError("failed-precondition", "That purchase was refunded.");
  if ((transaction.appAccountToken ?? "").toLowerCase() !== accountToken(uid)) {
    throw new HttpsError("permission-denied", "That purchase was made by another account.");
  }

  // Credited once, whoever asks again: the purchase's record is the lock.
  return db.runTransaction(async (tx) => {
    const purchaseRef = db.doc(`purchases/${transaction.transactionId}`);
    const purchase = await tx.get(purchaseRef);
    const wallet = await readWallet(tx, uid);
    if (purchase.exists) {
      if (purchase.get("revokedAt")) throw new HttpsError("failed-precondition", "That purchase was refunded.");
      if (purchase.get("uid") !== uid) throw new HttpsError("permission-denied", "That purchase belongs to another account.");
      return { credits, balance: wallet.balance, alreadyRedeemed: true };
    }
    tx.create(purchaseRef, {
      uid, productId: transaction.productId, credits, environment, purchasedAt: Timestamp.fromMillis(transaction.purchaseDate ?? Date.now()),
      redeemedAt: Timestamp.now(), revokedAt: null,
    });
    move(tx, uid, "purchase", { balance: credits }, credits, { productId: transaction.productId, transactionId: transaction.transactionId });
    return { credits, balance: wallet.balance + credits, alreadyRedeemed: false };
  });
});

export interface ClawbackResult {
  uid?: string;
  /** The credits taken back now; 0 when the purchase was never credited or was taken back already. */
  credits: number;
}

/** Takes back the credits a refunded or revoked purchase brought, once: the purchase's record remembers it. A
 * purchase never credited is recorded as revoked, so it can't be redeemed afterwards. The balance may go below zero
 * when the credits were spent meanwhile; the next purchase pays the difference first. */
export async function clawBack(transactionId: string, details: { type: string; environment?: string; productId?: string; revokedAt: Timestamp }): Promise<ClawbackResult> {
  return db.runTransaction(async (tx) => {
    const purchaseRef = db.doc(`purchases/${transactionId}`);
    const purchase = await tx.get(purchaseRef);
    if (!purchase.exists) {
      tx.create(purchaseRef, {
        uid: null, productId: details.productId ?? null, credits: 0, environment: details.environment ?? null, redeemedAt: null,
        revokedAt: details.revokedAt, revocation: details.type,
      });
      return { credits: 0 };
    }
    const uid = purchase.get("uid") as string | undefined;
    if (purchase.get("revokedAt") || !uid) return { uid, credits: 0 };
    const credits = (purchase.get("credits") as number) ?? 0;
    const wallet = await readWallet(tx, uid);
    tx.update(purchaseRef, { revokedAt: details.revokedAt, revocation: details.type });
    // A deleted account has no wallet left to take from.
    if (wallet.exists && credits > 0) {
      move(tx, uid, "clawback", { balance: -credits }, credits, { transactionId, productId: purchase.get("productId"), revocation: details.type });
    }
    return { uid, credits: wallet.exists ? credits : 0 };
  });
}

/** App Store Server Notifications, version 2: App Store Connect sends them to this function's URL
 * (https://europe-west1-aqra-quran.cloudfunctions.net/appStoreNotifications, for production and for the sandbox).
 * A REFUND or REVOKE takes back the credits the purchase brought; everything else is acknowledged and ignored. Apple
 * retries a notification that isn't answered with 200. */
export const appStoreNotifications = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("POST only");
    return;
  }
  const signedPayload = request.body?.signedPayload;
  if (typeof signedPayload !== "string") {
    response.status(400).send("A signedPayload is expected");
    return;
  }
  const payload = claimed(signedPayload);
  if (!payload) {
    response.status(400).send("Not a JWS");
    return;
  }
  const environment = payload.data?.environment ?? payload.summary?.environment;
  let verifier: SignedDataVerifier;
  try {
    verifier = verifierFor(environment, await policy(), { notification: true });
  } catch (error) {
    logger.warn("appStoreNotifications: refused", { environment, reason: (error as Error).message });
    response.status(error instanceof HttpsError && error.code === "failed-precondition" ? 503 : 403).send((error as Error).message);
    return;
  }
  try {
    const notification = await verifier.verifyAndDecodeNotification(signedPayload);
    const type = notification.notificationType ?? "";
    if (type !== NotificationTypeV2.REFUND && type !== NotificationTypeV2.REVOKE) {
      logger.info(`appStoreNotifications: ${type || "untyped"} acknowledged`, { uuid: notification.notificationUUID, subtype: notification.subtype });
      response.status(200).send("OK");
      return;
    }
    const signedTransaction = notification.data?.signedTransactionInfo;
    if (!signedTransaction) {
      response.status(400).send("No transaction");
      return;
    }
    const transaction = await verifier.verifyAndDecodeTransaction(signedTransaction);
    if (!transaction.transactionId) {
      response.status(400).send("No transaction id");
      return;
    }
    const result = await clawBack(transaction.transactionId, {
      type, environment: notification.data?.environment, productId: transaction.productId,
      revokedAt: Timestamp.fromMillis(transaction.revocationDate ?? Date.now()),
    });
    logger.info(`appStoreNotifications: ${type} handled`, {
      uuid: notification.notificationUUID, transactionId: transaction.transactionId, uid: result.uid, credits: result.credits,
    });
    response.status(200).send("OK");
  } catch (error) {
    logger.warn("appStoreNotifications: a payload that didn't verify", { environment, reason: String(error) });
    response.status(401).send("Not verified");
  }
});
