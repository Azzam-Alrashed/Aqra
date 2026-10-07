// Shared by the functions' tests: signed-in clients and an admin handle, all on the local emulators.
import { getApps as getAdminApps, initializeApp as initializeAdmin } from "firebase-admin/app";
import { getFirestore as getAdminFirestore, Timestamp } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, GoogleAuthProvider, signInAnonymously, signInWithCredential } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";

export const PROJECT = "demo-aqra";
export const REGION = "me-central2";

if (!getAdminApps().length) initializeAdmin({ projectId: PROJECT });
/** Firestore with no rules, for seeding and checking. */
export const adminDb = getAdminFirestore();

let count = 0;
const apps = [];

/** A client signed in as a new Google account (named), or anonymously; returns its uid and a callable maker. */
export async function client({ anonymous = false, email } = {}) {
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
  return {
    uid: credential.user.uid,
    call: async (name, data) => (await httpsCallable(functions, name)(data)).data,
  };
}

export async function closeClients() {
  await Promise.all(apps.splice(0).map((app) => deleteApp(app)));
}

/** Clears Firestore between tests. */
export async function clearFirestore() {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
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
