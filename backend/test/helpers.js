// Shared by the functions' tests: signed-in clients and an admin handle, all on the local emulators.
import { getApps as getAdminApps, initializeApp as initializeAdmin } from "firebase-admin/app";
import { getAuth as getAdminAuth } from "firebase-admin/auth";
import { getFirestore as getAdminFirestore, Timestamp } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, GoogleAuthProvider, signInAnonymously, signInWithCredential } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { createHash } from "node:crypto";

export const PROJECT = "demo-aqra";
export const REGION = "europe-west1";

if (!getAdminApps().length) initializeAdmin({ projectId: PROJECT });
/** Firestore with no rules, for seeding and checking. */
export const adminDb = getAdminFirestore();
export const adminAuth = getAdminAuth();

let count = 0;
const apps = [];

/** A client signed in as a new Google account (named), or anonymously, or as an administrator; returns its uid and
 * a callable maker. */
export async function client({ anonymous = false, email, admin = false } = {}) {
  const app = initializeApp({ projectId: PROJECT, apiKey: "test" }, `client-${++count}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const functions = getFunctions(app, REGION);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  const address = email ?? `user${count}-${Date.now()}@example.com`;
  const credential = anonymous
    ? await signInAnonymously(auth)
    : await signInWithCredential(auth, GoogleAuthProvider.credential(JSON.stringify({ sub: address, email: address, email_verified: true })));
  if (admin) {
    await adminAuth.setCustomUserClaims(credential.user.uid, { admin: true });
    await credential.user.getIdToken(true);
  }
  return {
    uid: credential.user.uid,
    call: async (name, data) => (await httpsCallable(functions, name)(data)).data,
  };
}

/** A client that never signed in: its calls reach the functions with no auth. */
export function signedOut() {
  const app = initializeApp({ projectId: PROJECT, apiKey: "test" }, `client-${++count}`);
  apps.push(app);
  const functions = getFunctions(app, REGION);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  return { call: async (name, data) => (await httpsCallable(functions, name)(data)).data };
}

export async function closeClients() {
  await Promise.all(apps.splice(0).map((app) => deleteApp(app)));
}

/** The functions emulator's address for HTTPS functions: /<project>/<region>/<name>. */
export const FUNCTIONS_URL = `http://127.0.0.1:5001/${PROJECT}/${REGION}`;

/** Runs a scheduled function now. Without the Pub/Sub emulator the functions emulator doesn't schedule it, but it
 * still serves it over HTTP as a background trigger, keyed `<region>-<name>-<generation>` (the generation is 0
 * unless the emulator reloaded its triggers). The call returns once the function has finished. */
export async function runSchedule(name) {
  for (let generation = 0; generation < 10; generation++) {
    const response = await fetch(`http://127.0.0.1:5001/functions/projects/${PROJECT}/triggers/${REGION}-${name}-${generation}`, { method: "POST" });
    if (response.status === 404) continue;
    // 204: the emulator has its background triggers turned off, so nothing ran.
    if (response.status !== 200) throw new Error(`${name}: ${response.status} ${await response.text()}`);
    return;
  }
  throw new Error(`${name}: the functions emulator doesn't serve it`);
}

/** The App Store account token the app attaches to a purchase, as functions/src/credits.ts derives it from the uid
 * (the first 16 bytes of its SHA-256, with the UUID version and variant bits set). */
export function accountToken(uid) {
  const bytes = createHash("sha256").update(uid, "utf8").digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** Clears Firestore between tests, so no test starts with another's data. With a delete trigger on sessions, the
 * emulator's clear can leave a deleted session's bids and seats behind under a parent that no longer exists, and the
 * triggers the last test (or the clear itself) set off may still write for a moment afterwards: it clears, waits, and
 * clears again until a pass finds nothing. */
export async function clearFirestore() {
  for (let pass = 0; pass < 10; pass++) {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
    for (const collection of await adminDb.listCollections()) await adminDb.recursiveDelete(collection);
    await new Promise((resolve) => setTimeout(resolve, 600));
    if ((await adminDb.listCollections()).length === 0) return;
  }
}

export const inMinutes = (minutes) => Timestamp.fromDate(new Date(Date.now() + minutes * 60_000));

/** Expects a callable to fail with a code, e.g. "functions/permission-denied". */
export async function rejects(promise, code) {
  try {
    await promise;
  } catch (error) {
    if (code && error.code !== code) throw new Error(`Expected ${code}, got ${error.code}: ${error.message}`);
    return error;
  }
  throw new Error(`Expected a failure${code ? ` (${code})` : ""}, but it succeeded.`);
}
