import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const [mode] = process.argv.slice(2);
if (mode !== "release") {
  throw new Error("Usage: node set-feature-policy.mjs release");
}

const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
initializeApp(
  emulator
    ? { projectId: process.env.GCLOUD_PROJECT ?? "macgit-local" }
    : { credential: applicationDefault() },
);

const proOnly = {
  enabled: true,
  plans: {
    free: { enabled: false },
    pro: { enabled: true },
  },
};

await getFirestore().doc("featurePolicies/release").set({
  schemaVersion: 1,
  revision: 2,
  features: {
    privateRepositories: {
      enabled: true,
      plans: {
        free: { enabled: false, repositoryScope: "none" },
        pro: { enabled: true, repositoryScope: "all" },
      },
    },
    pullRequests: {
      enabled: true,
      plans: {
        free: { enabled: true, repositoryScope: "public" },
        pro: { enabled: true, repositoryScope: "all" },
      },
    },
    gitFlow: {
      enabled: true,
      plans: {
        free: { enabled: true, repositoryScope: "publicOrLocal" },
        pro: { enabled: true, repositoryScope: "all" },
      },
    },
    gitUndo: {
      enabled: true,
      plans: {
        free: { enabled: true, repositoryScope: "publicOrLocal" },
        pro: { enabled: true, repositoryScope: "all" },
      },
    },
    aiCommitMessage: proOnly,
    repositoryChat: proOnly,
    aiConflictResolution: proOnly,
    aiBringYourOwnKey: proOnly,
  },
  updatedAt: FieldValue.serverTimestamp(),
});

console.log("Published release feature policy revision 2.");
