// Makes an account on the local emulators a vetted teacher, with a sample session tomorrow, so the teacher's
// side of the app can be tried without a real account. Run `npm run emulators` first, sign the app in to the
// emulator (Account → "Sign in to the emulator"), then:
//
//   npm run seed -- --email teacher@example.com --name "الشيخ أحمد" --city "الدمام" --line "إجازة برواية حفص"
//
// or `--uid <uid>` instead of `--email`. Nothing here touches the real project: it talks only to 127.0.0.1.
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, setDoc, Timestamp } from "firebase/firestore";

const PROJECT = "demo-aqra";
const AUTH = "http://127.0.0.1:9099";
const FIRESTORE = { host: "127.0.0.1", port: 8080 };

const args = Object.fromEntries(
  process.argv.slice(2).flatMap((arg, i, all) => (arg.startsWith("--") ? [[arg.slice(2), all[i + 1] ?? ""]] : [])),
);

if (!args.email && !args.uid) {
  console.error("Usage: npm run seed -- --email <email> | --uid <uid> [--name ...] [--city ...] [--line ...]");
  process.exit(2);
}

/** Finds the uid of an account on the Auth emulator by its email. */
async function uidOf(email) {
  const response = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:query`, {
    method: "POST",
    headers: { Authorization: "Bearer owner", "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  if (!response.ok) throw new Error(`The Auth emulator answered ${response.status}. Is it running on ${AUTH}?`);
  const { userInfo = [] } = await response.json();
  const user = userInfo.find((u) => u.email === email);
  if (!user) throw new Error(`No account with the email ${email} on the Auth emulator. Sign the app in first.`);
  return user.localId;
}

const uid = args.uid || (await uidOf(args.email));
const name = args.name || "الشيخ أحمد";
const city = args.city || "الدمام";
const line = args.line || "إجازة برواية حفص عن عاصم";

const tomorrow = new Date();
tomorrow.setDate(tomorrow.getDate() + 1);
tomorrow.setHours(20, 0, 0, 0);
const sessionId = `seed-${tomorrow.toISOString().slice(0, 10)}`;

const env = await initializeTestEnvironment({ projectId: PROJECT, firestore: FIRESTORE });
try {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `teachers/${uid}`), { name, city, line, vetted: true, createdAt: Timestamp.now() });
    await setDoc(doc(db, `sessions/${sessionId}`), {
      teacherId: uid, teacherName: name, startsAt: Timestamp.fromDate(tomorrow), place: "جامع الملك فهد",
      seats: 5, booked: 0, kind: "inPerson", status: "open", createdAt: Timestamp.now(),
    });
  });
} finally {
  await env.cleanup();
}

console.log(`Teacher ${name} (${uid}) is vetted, with the session ${sessionId} tomorrow at 20:00.`);
