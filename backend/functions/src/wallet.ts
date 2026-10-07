// The credits wallet: a balance and the credits held for active bids, with a ledger of every movement. Written only
// here, inside the callers' transactions (docs/SRS.md PAY-03).
import { DocumentReference, FieldValue, Timestamp, Transaction } from "firebase-admin/firestore";
import { db } from "./admin.js";

export type LedgerKind = "purchase" | "hold" | "release" | "spend" | "refund";

export interface Wallet {
  balance: number;
  held: number;
}

export const walletRef = (uid: string) => db.doc(`wallets/${uid}`) as DocumentReference;

export async function readWallet(tx: Transaction, uid: string): Promise<Wallet> {
  const data = (await tx.get(walletRef(uid))).data();
  return { balance: data?.balance ?? 0, held: data?.held ?? 0 };
}

/** Moves credits: `balance` and `held` change by the given amounts, and the ledger keeps the entry. */
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
