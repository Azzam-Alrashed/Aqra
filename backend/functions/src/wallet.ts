// The credits wallet: a balance and the credits held for active bids, with a ledger of every movement. Written only
// here, inside the callers' transactions (docs/SRS.md PAY-03).
import { DocumentReference, FieldValue, Timestamp, Transaction } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { db } from "./admin.js";

/** `clawback`: credits taken back because the App Store refunded or revoked the purchase that brought them. */
export type LedgerKind = "purchase" | "hold" | "release" | "spend" | "refund" | "clawback";

export interface Wallet {
  balance: number;
  held: number;
  /** Whether the wallet document exists: a student who never bought credits, and never bid, has none. */
  exists: boolean;
}

export const walletRef = (uid: string) => db.doc(`wallets/${uid}`) as DocumentReference;

export async function readWallet(tx: Transaction, uid: string): Promise<Wallet> {
  const snapshot = await tx.get(walletRef(uid));
  const data = snapshot.data();
  return { balance: data?.balance ?? 0, held: data?.held ?? 0, exists: snapshot.exists };
}

/** Makes an empty wallet for a student who has none yet (a 0 bid holds nothing, but the bidder must have a wallet:
 * settlement takes a missing wallet for a deleted account). Only for a wallet just read as missing, and never in the
 * same transaction as `move` on it. */
export function createWallet(tx: Transaction, uid: string) {
  tx.create(walletRef(uid), { balance: 0, held: 0, createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
}

/** Moves credits: `balance` and `held` change by the given amounts, and the ledger keeps the entry. Makes the wallet
 * if it doesn't exist yet. */
export function move(tx: Transaction, uid: string, kind: LedgerKind, change: { balance?: number; held?: number },
                     amount: number, details: Record<string, unknown> = {}) {
  tx.set(walletRef(uid), {
    balance: FieldValue.increment(change.balance ?? 0), held: FieldValue.increment(change.held ?? 0), updatedAt: Timestamp.now(),
  }, { merge: true });
  tx.create(walletRef(uid).collection("ledger").doc(), { kind, amount, at: Timestamp.now(), ...details });
}

/** Tells a user, in their in-app inbox. */
export function notify(tx: Transaction, uid: string, message: Record<string, unknown>) {
  tx.create(db.collection(`users/${uid}/inbox`).doc(), { ...message, at: Timestamp.now(), readAt: null });
}

/** Whether the account still exists: a bidder whose wallet is missing may have deleted their account (the wallet
 * went with it), or never have had one. */
export async function accountExists(uid: string): Promise<boolean> {
  try {
    await getAuth().getUser(uid);
    return true;
  } catch (error) {
    if ((error as { code?: string }).code === "auth/user-not-found") return false;
    throw error;
  }
}
