// The video calls' room tokens (functions/src/video.ts). Run with `npm run test:functions`.
import assert from "node:assert/strict";
import { after, beforeEach, describe, test } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import { TokenVerifier } from "livekit-server-sdk";
import { adminDb, clearFirestore, client, closeClients, inMinutes, rejects, signedOut } from "./helpers.js";

const verifier = new TokenVerifier("devkey", "secret");

async function session(id, teacherId, overrides = {}) {
  await adminDb.doc(`sessions/${id}`).set({
    teacherId, teacherName: "الشيخ أحمد", startsAt: inMinutes(10), place: "", seats: 5, booked: 0, kind: "video",
    status: "open", createdAt: Timestamp.now(), ...overrides,
  });
}

async function seat(sessionId, uid) {
  await adminDb.doc(`sessions/${sessionId}/seats/${uid}`).set({ name: "Alice", bookedAt: Timestamp.now(), memorizedPages: 20 });
}

beforeEach(clearFirestore);
after(closeClients);

describe("joinCall", () => {
  test("the teacher and a student with a seat get tokens for the session's room", async () => {
    const teacher = await client();
    const student = await client();
    await session("s1", teacher.uid);
    await seat("s1", student.uid);

    const forTeacher = await teacher.call("joinCall", { sessionId: "s1" });
    assert.equal(forTeacher.room, "session-s1");
    assert.equal(forTeacher.isTeacher, true);
    const teacherClaims = await verifier.verify(forTeacher.token);
    assert.equal(teacherClaims.sub, teacher.uid);
    assert.equal(teacherClaims.video.room, "session-s1");
    assert.equal(teacherClaims.video.roomAdmin, true);

    const forStudent = await student.call("joinCall", { sessionId: "s1" });
    const studentClaims = await verifier.verify(forStudent.token);
    assert.equal(studentClaims.sub, student.uid);
    assert.equal(studentClaims.name, "Alice");
    assert.equal(studentClaims.video.canPublish, true);
    assert.ok(!studentClaims.video.roomAdmin);
    assert.equal(forStudent.teacherId, teacher.uid);
    // The token lasts the policy's three hours, give or take the call's own time.
    const lifetime = studentClaims.exp - Math.floor(Date.now() / 1000);
    assert.ok(lifetime > 3 * 3600 - 60 && lifetime <= 3 * 3600, `token lifetime ${lifetime}s`);
  });

  test("nobody without a seat", async () => {
    const teacher = await client();
    const stranger = await client();
    await session("s1", teacher.uid);
    await rejects(stranger.call("joinCall", { sessionId: "s1" }), "functions/permission-denied");
    await rejects(stranger.call("joinCall", { sessionId: "missing" }), "functions/not-found");
    await rejects(stranger.call("joinCall", {}), "functions/invalid-argument");
  });

  test("joinCallRefusesTheSignedOut", async () => {
    const teacher = await client();
    await session("s1", teacher.uid);
    await rejects(signedOut().call("joinCall", { sessionId: "s1" }), "functions/unauthenticated");
    // Nor does anyone signed out bid, book or give back through the functions.
    await rejects(signedOut().call("placeBid", { sessionId: "s1", amount: 0 }), "functions/unauthenticated");
    await rejects(signedOut().call("takeFreeSeat", { sessionId: "s1" }), "functions/unauthenticated");
    await rejects(signedOut().call("giveBackSeat", { sessionId: "s1" }), "functions/unauthenticated");
    await rejects(signedOut().call("redeemPurchase", { signedTransaction: "x" }), "functions/unauthenticated");
  });

  test("only open video sessions, and only within the call's window", async () => {
    const teacher = await client();
    await session("inPerson", teacher.uid, { kind: "inPerson", place: "المسجد" });
    await session("cancelled", teacher.uid, { status: "cancelled" });
    await session("tomorrow", teacher.uid, { startsAt: inMinutes(24 * 60) });
    await session("over", teacher.uid, { startsAt: inMinutes(-4 * 60) });
    for (const id of ["inPerson", "cancelled", "tomorrow", "over"]) {
      await rejects(teacher.call("joinCall", { sessionId: id }), "functions/failed-precondition");
    }
    await session("started", teacher.uid, { startsAt: inMinutes(-60) });
    assert.equal((await teacher.call("joinCall", { sessionId: "started" })).room, "session-started");
  });
});
