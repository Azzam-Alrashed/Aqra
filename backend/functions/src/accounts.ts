// When an account is deleted, its wallet and ledger go with it (the app can't delete them: only functions write
// wallets). Purchases stay, as the record of what was sold; an active bid without a wallet wins no seat.
import * as functionsV1 from "firebase-functions/v1";
import { db } from "./admin.js";

export const onAccountDeleted = functionsV1.region("me-central2").auth.user().onDelete(async (user) => {
  const wallet = db.doc(`wallets/${user.uid}`);
  const ledger = await wallet.collection("ledger").get();
  const refs = [...ledger.docs.map((doc) => doc.ref), wallet];
  for (let start = 0; start < refs.length; start += 400) {
    const batch = db.batch();
    refs.slice(start, start + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
});
