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
/** An administrator: a signed-in user with the `admin` claim. */
const admin = (uid = "admin") => env.authenticatedContext(uid, { admin: true, firebase: { sign_in_provider: "google.com" } }).firestore();

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
    await assertFails(setDoc(doc(named("teacher"), "sessions/h"), newSession({ kind: "auction" })));
    await assertFails(setDoc(doc(named("teacher"), "sessions/i"), newSession({ seats: 31 })));
  });

  test("a session can be by video", async () => {
    await assertSucceeds(setDoc(doc(named("teacher"), "sessions/call"), newSession({ kind: "video", place: "" })));
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

  test("the teacher never sets fewer seats than the students who booked", async () => {
    await assertSucceeds(book(named("alice"), "alice", "open"));
    await assertSucceeds(book(named("bob"), "bob", "open"));
    await assertFails(updateDoc(doc(named("teacher"), "sessions/open"), { seats: 1 }));
    await assertSucceeds(updateDoc(doc(named("teacher"), "sessions/open"), { seats: 4 }));
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

  test("the teacher may classify mistakes and count it as a stage test", async () => {
    const teacher = named("teacher");
    await assertSucceeds(setDoc(doc(teacher, "users/alice/tasmee/t1"), tasmee({
      kind: "sheikh", mistakes: [{ ayah: 7, type: "hesitation" }], test: { stage: 10, allowedMistakesPerPage: 1 },
    })));
    await assertFails(setDoc(doc(teacher, "users/alice/tasmee/t2"), tasmee({ kind: "peer" })));
    await assertFails(setDoc(doc(teacher, "users/alice/tasmee/t3"), tasmee({ mistakes: "7:hesitation" })));
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

describe("peer tasmee'", () => {
  const request = (overrides = {}) => ({
    studentUid: "alice", studentName: "Alice", startPage: 582, createdAt: Timestamp.now(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 60_000)), ...overrides,
  });
  const peerRecord = (overrides = {}) => tasmee({ kind: "peer", teacherId: "bob", teacherName: "Bob", sessionId: "ABC234", ...overrides });

  test("a student, anonymous or not, creates a short-lived request for themselves", async () => {
    const { studentName, ...unnamed } = request();
    await assertSucceeds(setDoc(doc(anon("alice"), "peerRequests/ABC234"), unnamed));
    await assertSucceeds(setDoc(doc(named("alice"), "peerRequests/ABC235"), request()));
    await assertFails(setDoc(doc(named("alice"), "peerRequests/ABC236"), request({ studentUid: "bob" })));
    await assertFails(setDoc(doc(named("alice"), "peerRequests/ABC237"),
      request({ expiresAt: Timestamp.fromDate(new Date(Date.now() + 2 * 3_600_000)) })));
    await assertFails(setDoc(doc(named("alice"), "peerRequests/ABC238"), request({ expiresAt: inDays(-1) })));
    await assertFails(setDoc(doc(named("alice"), "peerRequests/ABC239"), request({ extra: 1 })));
  });

  test("a request is fetched by its code, never listed, never overwritten; its student withdraws it", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "peerRequests/ABC234"), request()));
    await assertSucceeds(getDoc(doc(anon("bob"), "peerRequests/ABC234")));
    await assertFails(getDocs(collection(named("bob"), "peerRequests")));
    await assertFails(setDoc(doc(named("bob"), "peerRequests/ABC234"), request({ studentUid: "bob" })));
    await assertFails(setDoc(doc(named("alice"), "peerRequests/ABC234"), request()));
    await assertFails(deleteDoc(doc(named("bob"), "peerRequests/ABC234")));
    await assertSucceeds(deleteDoc(doc(named("alice"), "peerRequests/ABC234")));
  });

  test("a friend with a valid code records a peer tasmee' into the student's account", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "peerRequests/ABC234"), request()));
    await assertSucceeds(setDoc(doc(anon("bob"), "users/alice/tasmee/p1"), peerRecord({ mistakes: [{ ayah: 7, type: "forgetting" }] })));
    await assertSucceeds(getDoc(doc(anon("bob"), "users/alice/tasmee/p1")));
  });

  test("not without the code, not for another student, not themselves, not expired, never verifying", async () => {
    await assertFails(setDoc(doc(named("bob"), "users/alice/tasmee/p1"), peerRecord()));
    await assertSucceeds(setDoc(doc(named("alice"), "peerRequests/ABC234"), request()));
    await assertFails(setDoc(doc(named("bob"), "users/carol/tasmee/p1"), peerRecord()));
    await assertFails(setDoc(doc(named("alice"), "users/alice/tasmee/p1"), peerRecord({ teacherId: "alice" })));
    await assertFails(setDoc(doc(named("bob"), "users/alice/tasmee/p1"), peerRecord({ teacherId: "carol" })));
    await assertFails(setDoc(doc(named("bob"), "users/alice/tasmee/p1"), peerRecord({ test: { stage: 1, allowedMistakesPerPage: 1 } })));
    await assertFails(setDoc(doc(named("bob"), "users/alice/tasmee/p1"), peerRecord({ kind: "sheikh" })));
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "peerRequests/OLD234"), request({ expiresAt: Timestamp.fromDate(new Date(Date.now() - 60_000)) }));
    });
    await assertFails(setDoc(doc(named("bob"), "users/alice/tasmee/p2"), peerRecord({ sessionId: "OLD234" })));
  });
});

describe("inbox", () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/alice/inbox/m1"), { kind: "outbid", at: Timestamp.now(), readAt: null });
    });
  });

  test("only its owner reads it, marks it read and deletes it; nobody writes it from the app", async () => {
    await assertSucceeds(getDoc(doc(named("alice"), "users/alice/inbox/m1")));
    await assertSucceeds(updateDoc(doc(named("alice"), "users/alice/inbox/m1"), { readAt: Timestamp.now() }));
    await assertFails(updateDoc(doc(named("alice"), "users/alice/inbox/m1"), { kind: "won" }));
    await assertFails(setDoc(doc(named("alice"), "users/alice/inbox/m2"), { kind: "won" }));
    await assertFails(getDoc(doc(named("bob"), "users/alice/inbox/m1")));
    await assertSucceeds(deleteDoc(doc(named("alice"), "users/alice/inbox/m1")));
  });
});

describe("teacher applications", () => {
  const application = (overrides = {}) => ({
    name: "أحمد", city: "الدمام", line: "", riwayah: "حفص عن عاصم", ijazahFrom: "الشيخ فلان", ijazahDetails: "",
    contact: "0500000000", files: ["ijazahs/alice/a.jpg"], status: "submitted", note: "", createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(), ...overrides,
  });

  test("a signed-in user applies for themselves, waiting for review", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "teacherApplications/alice"), application()));
    await assertFails(setDoc(doc(anon("bob"), "teacherApplications/bob"), application()));
    await assertFails(setDoc(doc(named("bob"), "teacherApplications/alice"), application()));
    await assertFails(setDoc(doc(named("bob"), "teacherApplications/bob"), application({ status: "approved" })));
    await assertFails(setDoc(doc(named("bob"), "teacherApplications/bob"), application({ note: "approve me" })));
    await assertFails(setDoc(doc(named("bob"), "teacherApplications/bob"), application({ files: ["1", "2", "3", "4", "5", "6"] })));
  });

  test("the applicant changes it while it waits, never its status; only they and administrators read it", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "teacherApplications/alice"), application()));
    await assertSucceeds(updateDoc(doc(named("alice"), "teacherApplications/alice"), { city: "الخبر", updatedAt: Timestamp.now() }));
    await assertFails(updateDoc(doc(named("alice"), "teacherApplications/alice"), { status: "approved" }));
    await assertFails(getDoc(doc(named("bob"), "teacherApplications/alice")));
    await assertSucceeds(getDoc(doc(admin(), "teacherApplications/alice")));
    await assertSucceeds(updateDoc(doc(admin(), "teacherApplications/alice"), { status: "interview", note: "نتواصل معك" }));
    await assertFails(updateDoc(doc(named("alice"), "teacherApplications/alice"), { city: "x", updatedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(named("alice"), "teacherApplications/alice")));
  });

  test("only an administrator makes or unmakes a teacher", async () => {
    await assertFails(setDoc(doc(named("alice"), "teachers/alice"), { name: "x", city: "y", line: "z", vetted: true }));
    await assertSucceeds(setDoc(doc(admin(), "teachers/alice"), { name: "x", city: "y", line: "z", vetted: true }));
    await assertSucceeds(updateDoc(doc(admin(), "teachers/alice"), { vetted: false }));
    await assertFails(updateDoc(doc(named("alice"), "teachers/alice"), { vetted: true }));
  });
});

describe("a teacher's student files", () => {
  test("only the teacher reads and writes their files and notes", async () => {
    const teacher = named("teacher");
    await assertSucceeds(setDoc(doc(teacher, "teachers/teacher/students/alice"), { name: "Alice", lastHeardAt: Timestamp.now(), notes: "" }));
    await assertSucceeds(setDoc(doc(teacher, "teachers/teacher/students/alice/records/r1"), tasmee()));
    await assertSucceeds(getDocs(collection(teacher, "teachers/teacher/students")));
    await assertFails(getDoc(doc(named("alice"), "teachers/teacher/students/alice")));
    await assertFails(getDocs(collection(named("alice"), "teachers/teacher/students/alice/records")));
    await assertFails(setDoc(doc(named("bob"), "teachers/teacher/students/bob"), { name: "Bob" }));
  });
});

describe("friends", () => {
  const invite = (overrides = {}) => ({
    ownerUid: "alice", ownerName: "Alice", createdAt: Timestamp.now(), expiresAt: inDays(7), ...overrides,
  });
  const friendship = (overrides = {}) => ({
    members: ["alice", "bob"], names: { alice: "Alice", bob: "Bob" }, inviteCode: "FRND23", createdAt: Timestamp.now(), ...overrides,
  });

  test("a named user invites for a week; the code is fetched, never listed", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "friendInvites/FRND23"), invite()));
    await assertFails(setDoc(doc(anon("carol"), "friendInvites/FRND24"), invite({ ownerUid: "carol" })));
    await assertFails(setDoc(doc(named("alice"), "friendInvites/FRND25"), invite({ ownerUid: "bob" })));
    await assertFails(setDoc(doc(named("alice"), "friendInvites/FRND26"), invite({ expiresAt: inDays(30) })));
    await assertSucceeds(getDoc(doc(named("bob"), "friendInvites/FRND23")));
    await assertFails(getDocs(collection(named("bob"), "friendInvites")));
    await assertSucceeds(getDocs(query(collection(named("alice"), "friendInvites"), where("ownerUid", "==", "alice"))));
    await assertFails(getDocs(query(collection(named("bob"), "friendInvites"), where("ownerUid", "==", "alice"))));
  });

  test("accepting a valid invitation makes a friendship both see; either ends it", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "friendInvites/FRND23"), invite()));
    await assertSucceeds(setDoc(doc(named("bob"), "friendships/alice_bob"), friendship()));
    await assertSucceeds(getDocs(query(collection(named("alice"), "friendships"), where("members", "array-contains", "alice"))));
    await assertFails(getDoc(doc(named("carol"), "friendships/alice_bob")));
    await assertSucceeds(deleteDoc(doc(named("alice"), "friendships/alice_bob")));
  });

  test("not without the inviter's code, not for others, not under another id, not anonymously", async () => {
    await assertFails(setDoc(doc(named("bob"), "friendships/alice_bob"), friendship()));
    await assertSucceeds(setDoc(doc(named("alice"), "friendInvites/FRND23"), invite()));
    await assertFails(setDoc(doc(named("carol"), "friendships/alice_bob"), friendship()));
    await assertFails(setDoc(doc(named("bob"), "friendships/bob_alice"), friendship()));
    await assertFails(setDoc(doc(anon("bob"), "friendships/alice_bob"), friendship()));
    await assertFails(setDoc(doc(named("alice"), "friendships/alice_bob"), friendship()));
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "friendInvites/OLD234"), invite({ expiresAt: inDays(-1) }));
    });
    await assertFails(setDoc(doc(named("bob"), "friendships/alice_bob"), friendship({ inviteCode: "OLD234" })));
  });
});

describe("competitions", () => {
  const competition = (overrides = {}) => ({
    kind: "friends", title: "رمضان", metric: "pagesRevised", ownerUid: "alice", ownerName: "Alice", startsAt: inDays(0),
    endsAt: inDays(7), memberUids: ["alice", "bob"], createdAt: Timestamp.now(), ...overrides,
  });
  const score = (overrides = {}) => ({ name: "Bob", score: 12, updatedAt: Timestamp.now(), ...overrides });

  test("a named user starts one with their friends; only members see it", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "competitions/c1"), competition()));
    await assertSucceeds(getDoc(doc(named("bob"), "competitions/c1")));
    await assertSucceeds(getDocs(query(collection(named("bob"), "competitions"), where("memberUids", "array-contains", "bob"))));
    await assertFails(getDoc(doc(named("carol"), "competitions/c1")));
    await assertFails(setDoc(doc(anon("carol"), "competitions/c2"), competition({ ownerUid: "carol", memberUids: ["carol"] })));
    await assertFails(setDoc(doc(named("alice"), "competitions/c3"), competition({ metric: "points" })));
    await assertFails(setDoc(doc(named("alice"), "competitions/c4"), competition({ memberUids: ["bob"] })));
    await assertFails(setDoc(doc(named("alice"), "competitions/c5"), competition({ endsAt: inDays(-1) })));
  });

  test("members report their own score in a friends' competition; members leave; the owner manages it", async () => {
    await assertSucceeds(setDoc(doc(named("alice"), "competitions/c1"), competition()));
    await assertSucceeds(setDoc(doc(named("bob"), "competitions/c1/members/bob"), score()));
    await assertFails(setDoc(doc(named("bob"), "competitions/c1/members/alice"), score({ name: "Alice" })));
    await assertFails(setDoc(doc(named("carol"), "competitions/c1/members/carol"), score({ name: "Carol" })));
    await assertFails(setDoc(doc(named("bob"), "competitions/c1/members/bob"), score({ score: -1 })));
    await assertSucceeds(getDocs(collection(named("alice"), "competitions/c1/members")));
    await assertFails(updateDoc(doc(named("bob"), "competitions/c1"), { title: "x" }));
    await assertFails(updateDoc(doc(named("bob"), "competitions/c1"), { memberUids: ["bob"] }));
    await assertSucceeds(updateDoc(doc(named("bob"), "competitions/c1"), { memberUids: ["alice"] }));
    await assertSucceeds(updateDoc(doc(named("alice"), "competitions/c1"), { title: "شعبان", memberUids: ["alice", "carol"] }));
    await assertFails(deleteDoc(doc(named("carol"), "competitions/c1")));
    await assertSucceeds(deleteDoc(doc(named("alice"), "competitions/c1/members/bob")));
    await assertSucceeds(deleteDoc(doc(named("alice"), "competitions/c1")));
  });

  test("only a vetted teacher starts one for their students, and nobody writes its scores from the app", async () => {
    await seed();
    const teacherCompetition = competition({ kind: "teacher", metric: "cleanPages", ownerUid: "teacher", ownerName: "x", memberUids: ["teacher", "bob"] });
    await assertSucceeds(setDoc(doc(named("teacher"), "competitions/t1"), teacherCompetition));
    await assertFails(setDoc(doc(named("alice"), "competitions/t2"), { ...teacherCompetition, ownerUid: "alice", memberUids: ["alice", "bob"] }));
    await assertFails(setDoc(doc(named("bob"), "competitions/t1/members/bob"), score()));
  });

  test("a khatmah's parts are made with it, claimed, finished and given back", async () => {
    const alice = named("alice");
    const batch = writeBatch(alice);
    batch.set(doc(alice, "competitions/k1"), competition({ kind: "khatmah", metric: "parts" }));
    for (let juz = 1; juz <= 30; juz++) batch.set(doc(alice, `competitions/k1/parts/${juz}`), { claimedBy: null, claimedName: "", done: false });
    await assertSucceeds(batch.commit());
    const bob = named("bob");
    await assertSucceeds(updateDoc(doc(bob, "competitions/k1/parts/5"), { claimedBy: "bob", claimedName: "Bob" }));
    await assertFails(updateDoc(doc(alice, "competitions/k1/parts/5"), { claimedBy: "alice", claimedName: "Alice" }));
    await assertFails(updateDoc(doc(alice, "competitions/k1/parts/5"), { done: true }));
    await assertSucceeds(updateDoc(doc(bob, "competitions/k1/parts/5"), { done: true }));
    await assertFails(updateDoc(doc(named("carol"), "competitions/k1/parts/6"), { claimedBy: "carol", claimedName: "Carol" }));
    await assertSucceeds(updateDoc(doc(alice, "competitions/k1/parts/6"), { claimedBy: "alice", claimedName: "Alice" }));
    await assertSucceeds(updateDoc(doc(alice, "competitions/k1/parts/6"), { claimedBy: null, claimedName: "", done: false }));
    await assertFails(setDoc(doc(bob, "competitions/k1/parts/31"), { claimedBy: null, claimedName: "", done: false }));
  });
});
