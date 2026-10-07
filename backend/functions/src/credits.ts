// Buying credits: an App Store consumable, credited once its signed transaction is verified (docs/SRS.md PAY-02).
// Production and sandbox purchases are verified against Apple's root certificates, kept in functions/certs; a
// purchase from Xcode's local StoreKit testing is accepted only on the emulators.
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { Timestamp } from "firebase-admin/firestore";
import { defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { readdirSync, readFileSync } from "node:fs";
import { db } from "./admin.js";
import { policy } from "./policy.js";
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

/** The environment a signed transaction says it comes from, read before it's verified to pick the verifier. */
function claimedEnvironment(jws: string): string | undefined {
  try {
    return JSON.parse(Buffer.from(jws.split(".")[1], "base64url").toString("utf8")).environment;
  } catch {
    return undefined;
  }
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

  const environment = claimedEnvironment(jws);
  const rules = await policy();
  let verifier: SignedDataVerifier;
  if (environment === Environment.XCODE) {
    if (!isEmulator() && !rules.allowLocalStoreKit) throw new HttpsError("permission-denied", "Test purchases aren't accepted here.");
    verifier = new SignedDataVerifier([], false, Environment.XCODE, bundleId.value());
  } else if (environment === Environment.SANDBOX || environment === Environment.PRODUCTION) {
    const certificates = rootCertificates();
    if (!certificates.length) throw new HttpsError("failed-precondition", "App Store verification isn't set up.");
    const appId = appAppleId.value() ? Number(appAppleId.value()) : undefined;
    verifier = new SignedDataVerifier(certificates, true, environment as Environment, bundleId.value(), appId);
  } else {
    throw new HttpsError("invalid-argument", "That isn't an App Store transaction.");
  }

  let transaction;
  try {
    transaction = await verifier.verifyAndDecodeTransaction(jws);
  } catch {
    throw new HttpsError("permission-denied", "The purchase couldn't be verified.");
  }
  const credits = rules.creditPacks[transaction.productId ?? ""];
  if (!credits || !transaction.transactionId) throw new HttpsError("invalid-argument", "That isn't a credit pack.");
  if (transaction.revocationDate) throw new HttpsError("failed-precondition", "That purchase was refunded.");

  // Credited once, whoever asks again: the purchase's record is the lock.
  return db.runTransaction(async (tx) => {
    const purchaseRef = db.doc(`purchases/${transaction.transactionId}`);
    const purchase = await tx.get(purchaseRef);
    const wallet = await readWallet(tx, uid);
    if (purchase.exists) {
      if (purchase.get("uid") !== uid) throw new HttpsError("permission-denied", "That purchase belongs to another account.");
      return { credits, balance: wallet.balance, alreadyRedeemed: true };
    }
    tx.create(purchaseRef, {
      uid, productId: transaction.productId, credits, environment, purchasedAt: Timestamp.fromMillis(transaction.purchaseDate ?? Date.now()),
      redeemedAt: Timestamp.now(),
    });
    move(tx, uid, "purchase", { balance: credits }, credits, { productId: transaction.productId, transactionId: transaction.transactionId });
    return { credits, balance: wallet.balance + credits, alreadyRedeemed: false };
  });
});
