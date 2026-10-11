// The server's rules, in one place (docs/SRS.md §3.7). Defaults live here; administrators override any of them in
// the `config/policy` document (`npm run admin -- policy --set key=value`), read at most once a minute.
//
// Not here, because nothing on the server reads them at run time: when bidding closes (3 hours before a session, or
// 30 minutes before one sooner than 3½ hours; a session under an hour away offers free seats only) and the one free
// seat a session must keep. Those are fixed in the session rules (firestore.rules) and in both apps' session editors
// (iOS TasmeeStore.biddingClosesAt, Android TasmeeSession.biddingClosesAt): changing them means changing all three.
import { db } from "./admin.js";

export interface Policy {
  /** Video: how long before a session its call opens, and how long after its start it stays open. */
  joinOpensMinutesBefore: number;
  joinClosesHoursAfter: number;
  /** How long a room token lasts. */
  tokenTTLHours: number;
  /** The seat auction: the least a first bid may be, and how much a bid must beat the lowest held bid by. */
  minBid: number;
  minIncrement: number;
  /** The share of a won seat's price the app keeps; the teacher earns the rest. */
  commissionRate: number;
  /** A seat won at auction and given back by its student at least this long before the session is refunded in full,
   * and the teacher's share reversed; given back later, the credits stay spent. A teacher removing a student always
   * refunds them. */
  seatRefundCutoffMinutes: number;
  /** Credits in each pack, by App Store product id. */
  creditPacks: Record<string, number>;
  /** Credit purchases made in Apple's sandbox (TestFlight, App Review) — turned on for a review, off otherwise, so
   * nobody fills a wallet with test money. Purchases signed by Xcode's StoreKit testing are accepted only on the
   * emulators, whatever the policy. */
  allowSandboxPurchases: boolean;
}

export const defaultPolicy: Policy = {
  joinOpensMinutesBefore: 15,
  joinClosesHoursAfter: 3,
  tokenTTLHours: 3,
  minBid: 0,
  minIncrement: 1,
  commissionRate: 0.2,
  seatRefundCutoffMinutes: 60,
  creditPacks: { "aqra.credits.10": 10, "aqra.credits.30": 30, "aqra.credits.60": 60 },
  allowSandboxPurchases: false,
};

let cached: { policy: Policy; at: number } | undefined;

/** On the emulators the policy is read every time, so a test that changes it sees the change at once. */
const cacheFor = process.env.FUNCTIONS_EMULATOR === "true" ? 0 : 60_000;

export async function policy(): Promise<Policy> {
  if (cached && Date.now() - cached.at < cacheFor) return cached.policy;
  const overrides = (await db.doc("config/policy").get()).data() ?? {};
  const merged = { ...defaultPolicy, ...overrides } as Policy;
  cached = { policy: merged, at: Date.now() };
  return merged;
}

/** Forgets the cached policy (tests change it between cases). */
export function resetPolicyCache() {
  cached = undefined;
}
