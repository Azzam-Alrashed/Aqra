// Set up once, before any function is defined: the Admin SDK, and where the functions run.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";

// Beside the database, in Dammam. Every function module imports this file first, so the options apply to all.
setGlobalOptions({ region: "me-central2", maxInstances: 10 });

initializeApp();

export const db = getFirestore();
