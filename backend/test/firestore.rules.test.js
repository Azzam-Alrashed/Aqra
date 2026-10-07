// The security rules: who may read and write what. Run with `npm run test:rules` (starts the Firestore emulator).
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, doc, getDoc, getDocs, increment, query, setDoc, Timestamp, updateDoc, where, writeBatch,
} from "firebase/firestore";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-aqra",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});

beforeEach(async () => env.clearFirestore());
after(async () => env.cleanup());

const inDays = (days) => Timestamp.fromDate(new Date(Date.now() + days * 86_400_000));

/** A user who signed in with Apple or Google. */
const named = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "google.com" } }).firestore();
/** An anonymous account, which every install starts as. */
const anon = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();

/** A vetted teacher, an unvetted one, and three of the teacher's sessions: open, past and cancelled. */
async function seed() {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "teachers/teacher"), { name: "الشيخ أحمد", city: "الدمام", line: "إجازة برواية حفص", vetted: true });
    await setDoc(doc(db, "teachers/unvetted"), { name: "x", city: "y", line: "z", vetted: false });
    const session = (startsAt, status = "open") => ({
      teacherId: "teacher", teacherName: "الشيخ أحمد", startsAt, place: "جامع الملك فهد", seats: 2, booked: 0,
      kind: "inPerson", status, createdAt: Timestamp.now(),
    });
    await setDoc(doc(db, "sessions/open"), session(inDays(1)));
    await setDoc(doc(db, "sessions/past"), session(inDays(-1)));
    await setDoc(doc(db, "sessions/cancelled"), session(inDays(1), "cancelled"));
  });
}

/** Books a seat the way the app does: the seat, the student's copy and the count, in one write. */
function book(db, uid, sessionId, extra = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, `sessions/${sessionId}/seats/${uid}`), { bookedAt: Timestamp.now(), name: "Alice", memorizedPages: 40, ...extra });
  batch.set(doc(db, `users/${uid}/bookings/${sessionId}`), { teacherId: "teacher", teacherName: "x", startsAt: inDays(1), place: "y" });
  batch.update(doc(db, `sessions/${sessionId}`), { booked: increment(1) });
  return batch.commit();
}

function cancelBooking(db, uid, sessionId) {
  const batch = writeBatch(db);
  batch.delete(doc(db, `sessions/${sessionId}/seats/${uid}`));
  batch.delete(doc(db, `users/${uid}/bookings/${sessionId}`));
  batch.update(doc(db, `sessions/${sessionId}`), { booked: increment(-1) });
  return batch.commit();
}

const tasmee = (overrides = {}) => ({
  teacherId: "teacher", teacherName: "الشيخ أحمد", sessionId: "open", at: Timestamp.now(), pages: [1, 2], stumbles: [7],
  appliedAt: null, ...overrides,
});

describe("progress", () => {
  test("a user reads and writes their own progress", async () => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertSucceeds(setDoc(doc(alice, "users/alice"), { updatedAt: Timestamp.now() }));
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
    await assertFails(getDoc(doc(stranger, "teachers/teacher")));
    await assertFails(getDoc(doc(stranger, "sessions/open")));
  });

  test("everything else is closed", async () => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertFails(setDoc(doc(alice, "teachers/alice"), { name: "x" }));
    await assertFails(getDoc(doc(alice, "anything/else")));
  });
});

describe("teachers", () => {
  beforeEach(seed);

  test("anyone signed in sees the teachers, anonymous included", async () => {
    await assertSucceeds(getDoc(doc(anon("alice"), "teachers/teacher")));
    await assertSucceeds(getDocs(query(collection(named("alice"), "teachers"), where("vetted", "==", true))));
  });

  test("a teacher edits their own name, city and line, and nothing else", async () => {
    const teacher = named("teacher");
    await assertSucceeds(updateDoc(doc(teacher, "teachers/teacher"), { name: "أحمد", city: "الخبر", line: "..." }));
    await assertFails(updateDoc(doc(teacher, "teachers/teacher"), { vetted: false }));
    await assertFails(updateDoc(doc(teacher, "teachers/teacher"), { name: "x", extra: true }));
    await assertFails(updateDoc(doc(named("unvetted"), "teachers/unvetted"), { vetted: true }));
    await assertFails(updateDoc(doc(named("alice"), "teachers/teacher"), { name: "x" }));
  });

  test("nobody creates or deletes a teacher from the app", async () => {
    const teacher = named("teacher");
    await assertFails(setDoc(doc(teacher, "teachers/teacher2"), { name: "x", city: "y", line: "z", vetted: true }));
    await assertFails(deleteDoc(doc(teacher, "teachers/teacher")));
  });
});

describe("sessions", () => {
  beforeEach(seed);

  const newSession = (overrides = {}) => ({
    teacherId: "teacher", teacherName: "الشيخ أحمد", startsAt: inDays(2), place: "المسجد", seats: 5, booked: 0,
    kind: "inPerson", status: "open", createdAt: Timestamp.now(), ...overrides,
  });

  test("a vetted teacher creates an upcoming session of their own", async () => {
    await assertSucceeds(setDoc(doc(named("teacher"), "sessions/new"), newSession()));
  });

  test("nobody else creates one, and not in the past or already booked", async () => {
    await assertFails(setDoc(doc(named("unvetted"), "sessions/a"), newSession({ teacherId: "unvetted" })));
    await assertFails(setDoc(doc(named("alice"), "sessions/b"), newSession({ teacherId: "alice" })));
    await assertFails(setDoc(doc(named("alice"), "sessions/c"), newSession()));
    await assertFails(setDoc(doc(named("teacher"), "sessions/d"), newSession({ startsAt: inDays(-1) })));
    await assertFails(setDoc(doc(named("teacher"), "sessions/e"), newSession({ booked: 1 })));
    await assertFails(setDoc(doc(named("teacher"), "sessions/f"), newSession({ seats: 0 })));
    await assertFails(setDoc(doc(named("teacher"), "sessions/g"), newSession({ status: "cancelled" })));
    await assertFails(setDoc(doc(named("teacher"), "sessions/h"), newSession({ kind: "video" })));
  });

  test("everyone signed in reads sessions", async () => {
    await assertSucceeds(getDoc(doc(anon("alice"), "sessions/open")));
    await assertSucceeds(getDocs(query(collection(named("alice"), "sessions"), where("teacherId", "==", "teacher"))));
  });

  test("the teacher changes or cancels their own session, and no one else does", async () => {
    const teacher = named("teacher");
    await assertSucceeds(updateDoc(doc(teacher, "sessions/open"), { place: "البيت", seats: 3 }));
    await assertSucceeds(updateDoc(doc(teacher, "sessions/open"), { status: "cancelled" }));
    await assertFails(updateDoc(doc(teacher, "sessions/open"), { teacherId: "alice" }));
    await assertFails(updateDoc(doc(teacher, "sessions/open"), { status: "done" }));
    await assertFails(updateDoc(doc(named("alice"), "sessions/open"), { place: "x" }));
    await assertFails(updateDoc(doc(named("unvetted"), "sessions/open"), { place: "x" }));
    await assertSucceeds(deleteDoc(doc(teacher, "sessions/past")));
    await assertFails(deleteDoc(doc(named("alice"), "sessions/open")));
  });
});

describe("seats", () => {
  beforeEach(seed);

  test("a signed-in student books a seat, with their copy and the count in one write", async () => {
    await assertSucceeds(book(named("alice"), "alice", "open"));
    await env.withSecurityRulesDisabled(async (context) => {
      const session = await getDoc(doc(context.firestore(), "sessions/open"));
      if (session.data().booked !== 1) throw new Error(`booked is ${session.data().booked}`);
    });
  });

  test("an anonymous account can't book", async () => {
    await assertFails(book(anon("bob"), "bob", "open"));
  });

  test("a student books only for themselves, only in open upcoming sessions, with only the expected fields", async () => {
    const alice = named("alice");
    await assertFails(book(alice, "bob", "open"));
    await assertFails(book(alice, "alice", "past"));
    await assertFails(book(alice, "alice", "cancelled"));
    await assertFails(book(alice, "alice", "open", { progress: "all of it" }));
    await assertSucceeds(book(alice, "alice", "open", { juzSummary: "٣٠، ٢٩" }));
  });

  test("the count only moves with a seat, by one, and never past the seats", async () => {
    const alice = named("alice");
    await assertFails(updateDoc(doc(alice, "sessions/open"), { booked: increment(1) }));
    await assertFails(updateDoc(doc(alice, "sessions/open"), { booked: increment(-1) }));
    const twice = writeBatch(alice);
    twice.set(doc(alice, "sessions/open/seats/alice"), { bookedAt: Timestamp.now(), name: "Alice", memorizedPages: 1 });
    twice.update(doc(alice, "sessions/open"), { booked: increment(2) });
    await assertFails(twice.commit());
    await assertSucceeds(book(alice, "alice", "open"));
    await assertSucceeds(book(named("bob"), "bob", "open"));
    await assertFails(book(named("carol"), "carol", "open"));
  });

  test("the student and the teacher see the seat; another student doesn't", async () => {
    await assertSucceeds(book(named("alice"), "alice", "open"));
    await assertSucceeds(getDoc(doc(named("alice"), "sessions/open/seats/alice")));
    await assertSucceeds(getDocs(collection(named("teacher"), "sessions/open/seats")));
    await assertFails(getDoc(doc(named("bob"), "sessions/open/seats/alice")));
    await assertFails(getDocs(collection(named("bob"), "sessions/open/seats")));
  });

  test("a booking is cancelled by the student at any time, or by the teacher", async () => {
    await assertSucceeds(book(named("alice"), "alice", "open"));
    await assertSucceeds(cancelBooking(named("alice"), "alice", "open"));
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "sessions/past/seats/alice"), { bookedAt: Timestamp.now(), name: "Alice", memorizedPages: 1 });
      await updateDoc(doc(context.firestore(), "sessions/past"), { booked: 1 });
    });
    await assertSucceeds(cancelBooking(named("alice"), "alice", "past"));
    await assertSucceeds(book(named("bob"), "bob", "open"));
    await assertSucceeds(deleteDoc(doc(named("teacher"), "sessions/open/seats/bob")));
    await assertSucceeds(updateDoc(doc(named("teacher"), "sessions/open"), { booked: 0 }));
    await assertFails(deleteDoc(doc(named("carol"), "sessions/open/seats/bob")));
  });

  test("a seat isn't edited once booked", async () => {
    await assertSucceeds(book(named("alice"), "alice", "open"));
    await assertFails(updateDoc(doc(named("alice"), "sessions/open/seats/alice"), { name: "Someone else" }));
  });
});

describe("bookings", () => {
  test("only the student reads and writes their bookings", async () => {
    const alice = named("alice");
    await assertSucceeds(setDoc(doc(alice, "users/alice/bookings/open"), { teacherId: "teacher" }));
    await assertSucceeds(getDoc(doc(alice, "users/alice/bookings/open")));
    await assertFails(getDoc(doc(named("bob"), "users/alice/bookings/open")));
    await assertFails(getDoc(doc(named("teacher"), "users/alice/bookings/open")));
  });
});

describe("tasmee' records", () => {
  beforeEach(async () => {
    await seed();
    await book(named("alice"), "alice", "open");
  });

  test("the session's teacher records a tasmee' for a student who booked", async () => {
    await assertSucceeds(setDoc(doc(named("teacher"), "users/alice/tasmee/t1"), tasmee()));
  });

  test("nobody else records one, and not without a seat", async () => {
    await assertFails(setDoc(doc(named("alice"), "users/alice/tasmee/t1"), tasmee()));
    await assertFails(setDoc(doc(named("unvetted"), "users/alice/tasmee/t1"), tasmee({ teacherId: "unvetted" })));
    await assertFails(setDoc(doc(named("teacher"), "users/bob/tasmee/t1"), tasmee()));
    await assertFails(setDoc(doc(named("teacher"), "users/alice/tasmee/t1"), tasmee({ sessionId: "past" })));
    await assertFails(setDoc(doc(named("teacher"), "users/alice/tasmee/t1"), tasmee({ teacherId: "alice" })));
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "teachers/other"), { name: "x", city: "y", line: "z", vetted: true });
      await setDoc(doc(context.firestore(), "sessions/others"), {
        teacherId: "other", teacherName: "x", startsAt: inDays(1), place: "y", seats: 1, booked: 0,
        kind: "inPerson", status: "open", createdAt: Timestamp.now(),
      });
    });
    await assertFails(setDoc(doc(named("other"), "users/alice/tasmee/t1"), tasmee({ teacherId: "other", sessionId: "open" })));
    await assertFails(setDoc(doc(named("other"), "users/alice/tasmee/t1"), tasmee({ teacherId: "other", sessionId: "others" })));
  });

  test("a record is complete and starts unapplied", async () => {
    const teacher = named("teacher");
    const { appliedAt, ...missing } = tasmee();
    await assertFails(setDoc(doc(teacher, "users/alice/tasmee/t1"), missing));
    await assertFails(setDoc(doc(teacher, "users/alice/tasmee/t1"), tasmee({ appliedAt: Timestamp.now() })));
    await assertFails(setDoc(doc(teacher, "users/alice/tasmee/t1"), tasmee({ pages: "1,2" })));
    await assertFails(setDoc(doc(teacher, "users/alice/tasmee/t1"), tasmee({ extra: true })));
  });

  test("the student marks it applied, and changes nothing else", async () => {
    await assertSucceeds(setDoc(doc(named("teacher"), "users/alice/tasmee/t1"), tasmee()));
    const alice = named("alice");
    await assertFails(updateDoc(doc(alice, "users/alice/tasmee/t1"), { pages: [1] }));
    await assertFails(updateDoc(doc(alice, "users/alice/tasmee/t1"), { appliedAt: "now" }));
    await assertSucceeds(updateDoc(doc(alice, "users/alice/tasmee/t1"), { appliedAt: Timestamp.now() }));
    await assertFails(updateDoc(doc(named("teacher"), "users/alice/tasmee/t1"), { appliedAt: Timestamp.now() }));
  });

  test("the student and the teacher read it; the student deletes it", async () => {
    await assertSucceeds(setDoc(doc(named("teacher"), "users/alice/tasmee/t1"), tasmee()));
    await assertSucceeds(getDoc(doc(named("alice"), "users/alice/tasmee/t1")));
    await assertSucceeds(getDocs(query(collection(named("alice"), "users/alice/tasmee"), where("appliedAt", "==", null))));
    await assertSucceeds(getDoc(doc(named("teacher"), "users/alice/tasmee/t1")));
    await assertSucceeds(getDocs(query(collection(named("teacher"), "users/alice/tasmee"), where("teacherId", "==", "teacher"))));
    await assertFails(getDoc(doc(named("bob"), "users/alice/tasmee/t1")));
    await assertFails(deleteDoc(doc(named("teacher"), "users/alice/tasmee/t1")));
    await assertSucceeds(deleteDoc(doc(named("alice"), "users/alice/tasmee/t1")));
  });
});
