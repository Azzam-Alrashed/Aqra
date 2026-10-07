// Teacher-run competitions' scores (functions/src/competitions.ts). Run with `npm run test:functions`.
import assert from "node:assert/strict";
import { after, beforeEach, describe, test } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import { adminDb, clearFirestore, closeClients, inMinutes } from "./helpers.js";

beforeEach(clearFirestore);
after(closeClients);

/** Waits until a check passes, for the trigger to have run. */
async function eventually(check, timeout = 10_000) {
  const start = Date.now();
  for (;;) {
    try {
      return await check();
    } catch (error) {
      if (Date.now() - start > timeout) throw error;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
  }
}

const record = (overrides = {}) => ({
  teacherId: "teacher", teacherName: "الشيخ أحمد", sessionId: "s1", at: Timestamp.now(), pages: [1, 2, 3],
  stumbles: [8], appliedAt: null, ...overrides,
});

describe("onTasmeeRecorded", () => {
  test("a teacher's record scores the clean pages in that teacher's running competitions, and tells the student", async () => {
    await adminDb.doc("competitions/t1").set({
      kind: "teacher", metric: "cleanPages", ownerUid: "teacher", title: "x", ownerName: "x", memberUids: ["teacher", "bob"],
      startsAt: inMinutes(-60), endsAt: inMinutes(60 * 24), createdAt: Timestamp.now(),
    });
    await adminDb.doc("competitions/other").set({
      kind: "teacher", metric: "cleanPages", ownerUid: "someoneElse", title: "x", ownerName: "x", memberUids: ["someoneElse", "bob"],
      startsAt: inMinutes(-60), endsAt: inMinutes(60 * 24), createdAt: Timestamp.now(),
    });
    // Ayah 8 is on page 2: pages 1 and 3 are clean.
    await adminDb.collection("users/bob/tasmee").add(record());
    await eventually(async () => {
      const member = await adminDb.doc("competitions/t1/members/bob").get();
      assert.equal(member.data()?.score, 2);
    });
    await adminDb.collection("users/bob/tasmee").add(record({ pages: [4], stumbles: [] }));
    await eventually(async () => assert.equal((await adminDb.doc("competitions/t1/members/bob").get()).data()?.score, 3));
    assert.equal((await adminDb.doc("competitions/other/members/bob").get()).exists, false);
    const inbox = await adminDb.collection("users/bob/inbox").get();
    assert.equal(inbox.size, 2);
    assert.equal(inbox.docs[0].data().kind, "tasmee");
  });

  test("a peer's record, or one outside the competition's dates, doesn't count", async () => {
    await adminDb.doc("competitions/t1").set({
      kind: "teacher", metric: "cleanPages", ownerUid: "teacher", title: "x", ownerName: "x", memberUids: ["teacher", "bob"],
      startsAt: inMinutes(60), endsAt: inMinutes(60 * 24), createdAt: Timestamp.now(),
    });
    await adminDb.collection("users/bob/tasmee").add(record({ kind: "peer" }));
    await adminDb.collection("users/bob/tasmee").add(record());
    await eventually(async () => assert.equal((await adminDb.collection("users/bob/inbox").get()).size, 1));
    await new Promise((resolve) => setTimeout(resolve, 500));
    assert.equal((await adminDb.doc("competitions/t1/members/bob").get()).exists, false);
  });
});
