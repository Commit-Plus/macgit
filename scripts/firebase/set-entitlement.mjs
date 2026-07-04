import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const [uid, mode] = process.argv.slice(2);
if (!uid || !["grant", "revoke"].includes(mode)) {
  throw new Error("Usage: node set-entitlement.mjs <firebase-uid> <grant|revoke>");
}

const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
initializeApp(
  emulator
    ? { projectId: process.env.GCLOUD_PROJECT ?? "macgit-local" }
    : { credential: applicationDefault() },
);

const active = mode === "grant";
await getFirestore().doc(`entitlements/${uid}`).set({
  plan: active ? "pro" : "free",
  access: active ? "active" : "inactive",
  billingStatus: active ? "active" : "none",
  source: "admin_test",
  cancelAtPeriodEnd: false,
  updatedAt: FieldValue.serverTimestamp(),
});

console.log(`${active ? "Granted" : "Revoked"} test Pro access for ${uid}.`);
