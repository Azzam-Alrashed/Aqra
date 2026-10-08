// Set up once, before any function is defined: the Admin SDK, and where the functions run.
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";

// Beside the database and files, in Belgium. Every function module imports this file first, so the options apply to all.
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

// Tests may load the functions alongside an app of their own.
if (!getApps().length) initializeApp();

export const db = getFirestore();
