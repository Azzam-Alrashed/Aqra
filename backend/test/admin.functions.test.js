// The administration script (scripts/admin.mjs), run against the emulators. Run with `npm run test:functions`.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { after, beforeEach, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { adminDb, clearFirestore, closeClients } from "./helpers.js";

beforeEach(clearFirestore);
after(closeClients);

const script = fileURLToPath(new URL("../scripts/admin.mjs", import.meta.url));

/** Runs `npm run admin -- <args> --emulator` and gives back its exit code and output. */
function admin(...args) {
  return new Promise((resolve) => {
    execFile(process.execPath, [script, ...args, "--emulator"], { env: { ...process.env } }, (error, stdout, stderr) => {
      resolve({ code: error ? error.code : 0, stdout, stderr });
    });
  });
}

describe("admin payout", () => {
  test("payoutRefusesMoreThanDueWhenFieldsAreMissing", async () => {
    // Earned, never paid out: the functions write `earned` alone.
    await adminDb.doc("teacherBalances/t1").set({ earned: 3 });
    let result = await admin("payout", "--teacher", "t1", "--amount", "5", "--reference", "bank-1");
    assert.equal(result.code, 2, result.stdout + result.stderr);
    assert.match(result.stderr, /Only 3 credits are due/);
    // Only ever reversed: no `earned` at all.
    await adminDb.doc("teacherBalances/t2").set({ paidOut: 0 });
    result = await admin("payout", "--teacher", "t2", "--amount", "1", "--reference", "bank-2");
    assert.equal(result.code, 2);
    assert.match(result.stderr, /Only 0 credits are due/);
    // No balance at all.
    result = await admin("payout", "--teacher", "t3", "--amount", "1", "--reference", "bank-3");
    assert.equal(result.code, 2);
    assert.match(result.stderr, /Only 0 credits are due/);
    assert.equal((await adminDb.doc("teacherBalances/t3").get()).exists, false);
    assert.equal((await adminDb.collection("teacherBalances/t1/entries").get()).size, 0);
  });

  test("a payout within what's due is recorded, and told", async () => {
    await adminDb.doc("teacherBalances/t1").set({ earned: 8 });
    const result = await admin("payout", "--teacher", "t1", "--amount", "5", "--reference", "bank-1");
    assert.equal(result.code, 0, result.stdout + result.stderr);
    const balance = (await adminDb.doc("teacherBalances/t1").get()).data();
    assert.deepEqual([balance.earned, balance.paidOut], [8, 5]);
    const entries = await adminDb.collection("teacherBalances/t1/entries").get();
    assert.equal(entries.size, 1);
    assert.deepEqual([entries.docs[0].data().kind, entries.docs[0].data().amount, entries.docs[0].data().reference], ["payout", -5, "bank-1"]);
    const inbox = await adminDb.collection("users/t1/inbox").get();
    assert.equal(inbox.docs[0].data().kind, "payout");
    // The rest, and not a credit more.
    const again = await admin("payout", "--teacher", "t1", "--amount", "4", "--reference", "bank-2");
    assert.equal(again.code, 2);
    assert.match(again.stderr, /Only 3 credits are due/);
    const shown = await admin("balance", "--teacher", "t1");
    assert.match(shown.stdout, /earned 8 · paid out 5 · due 3/);
  });
});
