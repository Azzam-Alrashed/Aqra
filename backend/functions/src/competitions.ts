// Teacher-run competitions rest on verified evidence: a student's score is the pages their teacher heard clean,
// counted here from the teacher's own tasmee' records, never reported by the student's app (docs/SRS.md SOC-04).
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { db } from "./admin.js";
import pages from "./pageAyahs.json" with { type: "json" };

/** Each page's first and last ayah (0…6235), from scripts/generate-page-ayahs.py. */
const pageAyahs = pages as [number, number][];

/** The pages heard with no stumble on them. */
export function cleanPages(pages: number[], stumbles: number[]): number {
  return [...new Set(pages)].filter((page) => {
    const range = pageAyahs[page - 1];
    return range && !stumbles.some((ayah) => ayah >= range[0] && ayah <= range[1]);
  }).length;
}

export const onTasmeeRecorded = onDocumentCreated("users/{uid}/tasmee/{recordId}", async (event) => {
  const record = event.data?.data();
  if (!record || (record.kind ?? "sheikh") !== "sheikh") return;
  const uid = event.params.uid;
  const at = (record.at as Timestamp).toMillis();

  // The student hears of it in their inbox.
  await db.collection(`users/${uid}/inbox`).add({
    kind: "tasmee", teacherName: record.teacherName ?? "", pages: (record.pages ?? []).length, at: Timestamp.now(), readAt: null,
  });

  const competitions = await db.collection("competitions")
    .where("kind", "==", "teacher").where("ownerUid", "==", record.teacherId).where("memberUids", "array-contains", uid)
    .get();
  const clean = cleanPages(record.pages ?? [], record.stumbles ?? []);
  for (const competition of competitions.docs) {
    const { startsAt, endsAt } = competition.data();
    if (at < (startsAt as Timestamp).toMillis() || at > (endsAt as Timestamp).toMillis()) continue;
    await competition.ref.collection("members").doc(uid).set({
      score: FieldValue.increment(clean), updatedAt: Timestamp.now(),
    }, { merge: true });
  }
});
