// The server's rules, in one place (docs/SRS.md §3.7). Defaults live here; administrators override any of them in
// the `config/policy` document (`npm run admin -- policy --set key=value`), read at most once a minute.
import { db } from "./admin.js";

export interface Policy {
  /** Video: how long before a session its call opens, and how long after its start it stays open. */
  joinOpensMinutesBefore: number;
  joinClosesHoursAfter: number;
  /** How long a room token lasts. */
  tokenTTLHours: number;
  /** The seat auction. */
  minFreeSeats: number;
  minBid: number;
  minIncrement: number;
  biddingClosesBeforeHours: number;
  /** The share of a won seat's price the app keeps; the teacher earns the rest. */
  commissionRate: number;
  /** Credits in each pack, by App Store product id. */
  creditPacks: Record<string, number>;
  /** Accept purchases signed by Xcode's local StoreKit testing (development only). */
  allowLocalStoreKit: boolean;
}

export const defaultPolicy: Policy = {
  joinOpensMinutesBefore: 15,
  joinClosesHoursAfter: 3,
  tokenTTLHours: 3,
  minFreeSeats: 1,
  minBid: 0,
  minIncrement: 1,
  biddingClosesBeforeHours: 3,
  commissionRate: 0.2,
  creditPacks: { "aqra.credits.10": 10, "aqra.credits.30": 30, "aqra.credits.60": 60 },
  allowLocalStoreKit: false,
};

let cached: { policy: Policy; at: number } | undefined;

export async function policy(): Promise<Policy> {
  if (cached && Date.now() - cached.at < 60_000) return cached.policy;
  const overrides = (await db.doc("config/policy").get()).data() ?? {};
  const merged = { ...defaultPolicy, ...overrides } as Policy;
  cached = { policy: merged, at: Date.now() };
  return merged;
}

/** Forgets the cached policy (tests change it between cases). */
export function resetPolicyCache() {
  cached = undefined;
}
