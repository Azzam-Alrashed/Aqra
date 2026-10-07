// Aqra's administration, from the command line: vetting teachers, administrators, payouts and the server policy.
//
//   npm run admin -- <command> [--emulator] [options]
//
// With --emulator it talks to the local emulators (project demo-aqra); without it, to the real project aqra-quran
// with your Google credentials (`gcloud auth application-default login`, or GOOGLE_APPLICATION_CREDENTIALS).
//
// Commands:
//   applications [--status submitted|interview|approved|rejected]   list applications to teach
//   interview --uid <uid> [--note "..."]                           reviewed: the team will arrange the interview
//   approve --uid <uid> [--note "..."]                             make the applicant a vetted teacher
//   reject --uid <uid> --note "..."                                decline, with the reason the applicant sees
//   revoke-teacher --uid <uid>                                     stop a teacher (vetted: false)
//   grant-admin --email <email> | --uid <uid>                      give the admin claim (sign out and in to take effect)
//   revoke-admin --email <email> | --uid <uid>
//   payout --teacher <uid> --amount <credits> --reference "..."    record a bank transfer to a teacher
//   balance --teacher <uid>                                        a teacher's earnings, payouts and balance
//   policy [--set key=value ...]                                   show or change config/policy
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";

const argv = process.argv.slice(2);
const command = argv[0];
const flags = {};
const sets = [];
for (let i = 1; i < argv.length; i++) {
  if (!argv[i].startsWith("--")) continue;
  const key = argv[i].slice(2);
  const value = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
  if (key === "set") sets.push(value);
  else flags[key] = value;
}

if (flags.emulator) {
  process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
  initializeApp({ projectId: "demo-aqra" });
} else {
  initializeApp({ credential: applicationDefault(), projectId: "aqra-quran" });
}
const db = getFirestore();
const auth = getAuth();

function fail(message) {
  console.error(message);
  process.exit(2);
}

async function uidFromFlags() {
  if (flags.uid) return flags.uid;
  if (flags.email) return (await auth.getUserByEmail(flags.email)).uid;
  fail("Give --uid <uid> or --email <email>.");
}

/** Tells the user, in their in-app inbox. */
async function notify(uid, message) {
  await db.collection(`users/${uid}/inbox`).add({ ...message, at: Timestamp.now(), readAt: null });
}

async function setStatus(uid, status, note) {
  const ref = db.doc(`teacherApplications/${uid}`);
  const snapshot = await ref.get();
  if (!snapshot.exists) fail(`No application from ${uid}.`);
  await ref.update({ status, note: note ?? snapshot.get("note") ?? "", updatedAt: Timestamp.now() });
  await notify(uid, { kind: "application", status, note: note ?? "" });
  return snapshot.data();
}

const commands = {
  async applications() {
    let query = db.collection("teacherApplications");
    if (flags.status) query = query.where("status", "==", flags.status);
    const snapshot = await query.get();
    if (snapshot.empty) return console.log("No applications.");
    for (const doc of snapshot.docs) {
      const a = doc.data();
      console.log(`${doc.id}  [${a.status}]  ${a.name} · ${a.city} · ${a.riwayah}`);
      console.log(`    ijazah from ${a.ijazahFrom}${a.ijazahDetails ? ` — ${a.ijazahDetails}` : ""}`);
      console.log(`    contact ${a.contact} · files ${(a.files ?? []).join(", ")}`);
      if (a.note) console.log(`    note: ${a.note}`);
    }
  },

  async interview() {
    const uid = await uidFromFlags();
    await setStatus(uid, "interview", flags.note);
    console.log(`${uid}: interview.`);
  },

  async approve() {
    const uid = await uidFromFlags();
    const application = await setStatus(uid, "approved", flags.note);
    await db.doc(`teachers/${uid}`).set({
      name: application.name, city: application.city ?? "", line: application.line ?? "", vetted: true,
      createdAt: Timestamp.now(),
    }, { merge: true });
    console.log(`${uid}: approved, and is now a vetted teacher.`);
  },

  async reject() {
    const uid = await uidFromFlags();
    if (!flags.note) fail("Give --note with the reason the applicant will see.");
    await setStatus(uid, "rejected", flags.note);
    console.log(`${uid}: rejected.`);
  },

  async "revoke-teacher"() {
    const uid = await uidFromFlags();
    await db.doc(`teachers/${uid}`).update({ vetted: false });
    console.log(`${uid}: no longer a vetted teacher.`);
  },

  async "grant-admin"() {
    const uid = await uidFromFlags();
    const user = await auth.getUser(uid);
    await auth.setCustomUserClaims(uid, { ...(user.customClaims ?? {}), admin: true });
    console.log(`${uid}: administrator (after signing in again).`);
  },

  async "revoke-admin"() {
    const uid = await uidFromFlags();
    const user = await auth.getUser(uid);
    const { admin, ...claims } = user.customClaims ?? {};
    await auth.setCustomUserClaims(uid, claims);
    console.log(`${uid}: no longer an administrator.`);
  },

  async payout() {
    const teacher = flags.teacher || fail("Give --teacher <uid>.");
    const amount = Number(flags.amount);
    if (!Number.isFinite(amount) || amount <= 0) fail("Give --amount <credits>, more than zero.");
    if (!flags.reference) fail("Give --reference with the bank transfer's reference.");
    await db.runTransaction(async (tx) => {
      const balanceRef = db.doc(`teacherBalances/${teacher}`);
      const balance = (await tx.get(balanceRef)).data() ?? { earned: 0, paidOut: 0 };
      if (balance.earned - balance.paidOut < amount) fail(`Only ${balance.earned - balance.paidOut} credits are due.`);
      tx.set(balanceRef, { paidOut: FieldValue.increment(amount), updatedAt: Timestamp.now() }, { merge: true });
      tx.create(balanceRef.collection("entries").doc(), {
        kind: "payout", amount: -amount, reference: flags.reference, at: Timestamp.now(),
      });
    });
    await notify(teacher, { kind: "payout", amount });
    console.log(`Recorded a payout of ${amount} credits to ${teacher}.`);
  },

  async balance() {
    const teacher = flags.teacher || fail("Give --teacher <uid>.");
    const balance = (await db.doc(`teacherBalances/${teacher}`).get()).data() ?? { earned: 0, paidOut: 0 };
    console.log(`earned ${balance.earned ?? 0} · paid out ${balance.paidOut ?? 0} · due ${(balance.earned ?? 0) - (balance.paidOut ?? 0)}`);
    const entries = await db.collection(`teacherBalances/${teacher}/entries`).orderBy("at", "desc").limit(20).get();
    for (const entry of entries.docs) {
      const e = entry.data();
      console.log(`  ${e.at.toDate().toISOString().slice(0, 16)}  ${e.kind.padEnd(7)} ${String(e.amount).padStart(6)}  ${e.sessionId ?? e.reference ?? ""}`);
    }
  },

  async policy() {
    const ref = db.doc("config/policy");
    if (sets.length) {
      const changes = {};
      for (const pair of sets) {
        const [key, ...rest] = String(pair).split("=");
        const raw = rest.join("=");
        changes[key] = raw === "true" ? true : raw === "false" ? false : Number.isNaN(Number(raw)) ? raw : Number(raw);
      }
      await ref.set(changes, { merge: true });
    }
    console.log(JSON.stringify((await ref.get()).data() ?? {}, null, 2));
  },
};

if (!commands[command]) {
  fail(`Usage: npm run admin -- <${Object.keys(commands).join("|")}> [--emulator] [options]`);
}
await commands[command]();
process.exit(0);
