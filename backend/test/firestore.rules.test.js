// The security rules: each user reads and writes only their own progress, and nothing else is open.
// Run with `npm run test:rules` (starts the Firestore emulator).
import { readFileSync } from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-aqra",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});

beforeEach(async () => env.clearFirestore());
after(async () => env.cleanup());

test("a user reads and writes their own progress", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(setDoc(doc(alice, "users/alice/memory/block-00"), { ayahs: { 7: [1, 14, -1, 0, 0] } }));
  await assertSucceeds(getDoc(doc(alice, "users/alice/memory/block-00")));
  await assertSucceeds(setDoc(doc(alice, "users/alice/revision/state"), { json: "{}" }));
});

test("a user can't read or write another user's progress", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/bob/memory/block-00"), { ayahs: {} });
  });
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(getDoc(doc(alice, "users/bob/memory/block-00")));
  await assertFails(setDoc(doc(alice, "users/bob/memory/block-00"), { ayahs: {} }));
});

test("someone not signed in can't read or write anything", async () => {
  const stranger = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(stranger, "users/alice/memory/block-00")));
  await assertFails(setDoc(doc(stranger, "users/alice/memory/block-00"), { ayahs: {} }));
});

test("everything outside users/ is closed", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(alice, "teachers/alice"), { name: "x" }));
  await assertFails(getDoc(doc(alice, "anything/else")));
});
