// The storage rules: a teacher applicant's copies of their ijazah, and the app's downloads. Run with
// `npm run test:rules`.
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteObject, getBytes, ref, uploadBytes } from "firebase/storage";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-aqra",
    storage: { rules: readFileSync(new URL("../storage.rules", import.meta.url), "utf8"), host: "127.0.0.1", port: 9199 },
  });
});

beforeEach(async () => env.clearStorage());
after(async () => env.cleanup());

const named = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "apple.com" } }).storage();
const anon = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).storage();
const admin = () => env.authenticatedContext("admin", { admin: true, firebase: { sign_in_provider: "google.com" } }).storage();

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const upload = (storage, path, contentType = "image/jpeg", bytes = jpeg) => uploadBytes(ref(storage, path), bytes, { contentType });

describe("ijazah uploads", () => {
  test("a signed-in applicant uploads an image or a PDF into their own folder", async () => {
    await assertSucceeds(upload(named("alice"), "ijazahs/alice/a.jpg"));
    await assertSucceeds(upload(named("alice"), "ijazahs/alice/b.pdf", "application/pdf"));
  });

  test("not anonymously, not into another's folder, not another kind of file, not too large, nowhere else", async () => {
    await assertFails(upload(anon("bob"), "ijazahs/bob/a.jpg"));
    await assertFails(upload(named("bob"), "ijazahs/alice/a.jpg"));
    await assertFails(upload(named("alice"), "ijazahs/alice/a.zip", "application/zip"));
    await assertFails(upload(named("alice"), "ijazahs/alice/big.jpg", "image/jpeg", new Uint8Array(10 * 1024 * 1024 + 1)));
    await assertFails(upload(named("alice"), "other/alice/a.jpg"));
  });

  test("the applicant and administrators read it; the applicant deletes it", async () => {
    await assertSucceeds(upload(named("alice"), "ijazahs/alice/a.jpg"));
    await assertSucceeds(getBytes(ref(named("alice"), "ijazahs/alice/a.jpg")));
    await assertSucceeds(getBytes(ref(admin(), "ijazahs/alice/a.jpg")));
    await assertFails(getBytes(ref(named("bob"), "ijazahs/alice/a.jpg")));
    await assertFails(deleteObject(ref(named("bob"), "ijazahs/alice/a.jpg")));
    await assertSucceeds(deleteObject(ref(named("alice"), "ijazahs/alice/a.jpg")));
  });
});

describe("the app's downloads", () => {
  test("anyone reads a model, signed in or not; no one writes one", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await uploadBytes(ref(context.storage(), "models/recitation/model.aar"), jpeg, { contentType: "application/octet-stream" });
    });
    await assertSucceeds(getBytes(ref(env.unauthenticatedContext().storage(), "models/recitation/model.aar")));
    await assertSucceeds(getBytes(ref(anon("bob"), "models/recitation/model.aar")));
    await assertFails(upload(named("alice"), "models/recitation/model.aar", "application/octet-stream"));
    await assertFails(upload(admin(), "models/recitation/other.aar", "application/octet-stream"));
    await assertFails(deleteObject(ref(admin(), "models/recitation/model.aar")));
  });
});
