import { readFileSync } from "node:fs";
import { after, afterEach, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc } from "firebase/firestore";

const projectId = "macgit-rules-test";
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

afterEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function settings(uid, context) {
  return doc(context.firestore(), `users/${uid}/settings/app`);
}

function entitlement(uid, context) {
  return doc(context.firestore(), `entitlements/${uid}`);
}

function gitProviderAccount(uid, connectionID, context) {
  return doc(context.firestore(), `users/${uid}/gitProviderAccounts/${connectionID}`);
}

function validSettings() {
  return {
    schemaVersion: 1,
    showToolbarButtonText: true,
    showSubmodules: false,
    showSubtrees: true,
    updatedAt: serverTimestamp(),
  };
}

function validGitProviderAccount() {
  return {
    schemaVersion: 1,
    provider: "github",
    hostURL: "https://github.com",
    providerUserID: "583231",
    username: "octocat",
    displayName: "The Octocat",
    avatarURL: "https://avatars.githubusercontent.com/u/583231",
    scopes: ["repo", "read:user"],
    permissions: {},
    tokenStatus: "valid",
    connectedAt: serverTimestamp(),
    lastValidatedAt: serverTimestamp(),
  };
}

describe("Firestore ownership rules", () => {
  test("a user can read and write only their own settings", async () => {
    const userA = environment.authenticatedContext("user-a");
    const userB = environment.authenticatedContext("user-b");

    await assertSucceeds(setDoc(settings("user-a", userA), validSettings()));
    await assertSucceeds(getDoc(settings("user-a", userA)));
    await assertFails(getDoc(settings("user-a", userB)));
    await assertFails(setDoc(settings("user-a", userB), validSettings()));
  });

  test("settings reject missing and unknown fields", async () => {
    const userA = environment.authenticatedContext("user-a");

    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      unexpected: true,
    }));

    for (const key of Object.keys(validSettings())) {
      const missingField = validSettings();
      delete missingField[key];
      await assertFails(setDoc(settings("user-a", userA), missingField));
    }
  });

  test("settings reject unsupported schema versions and every wrong field type", async () => {
    const userA = environment.authenticatedContext("user-a");
    const invalidValues = {
      schemaVersion: 2,
      showToolbarButtonText: "true",
      showSubmodules: "false",
      showSubtrees: 1,
      updatedAt: "now",
    };

    for (const [key, value] of Object.entries(invalidValues)) {
      await assertFails(setDoc(settings("user-a", userA), {
        ...validSettings(),
        [key]: value,
      }));
    }
  });

  test("a user can read only their own entitlement", async () => {
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), {
        plan: "pro",
        access: "active",
        billingStatus: "active",
      });
    });
    const userA = environment.authenticatedContext("user-a");
    const userB = environment.authenticatedContext("user-b");

    await assertSucceeds(getDoc(entitlement("user-a", userA)));
    await assertFails(getDoc(entitlement("user-a", userB)));
  });

  test("a user can read and write only their own Git provider metadata", async () => {
    const userA = environment.authenticatedContext("user-a");
    const userB = environment.authenticatedContext("user-b");
    const ownAccount = gitProviderAccount("user-a", "connection-1", userA);

    await assertSucceeds(setDoc(ownAccount, validGitProviderAccount()));
    await assertSucceeds(getDoc(ownAccount));
    await assertFails(getDoc(gitProviderAccount("user-a", "connection-1", userB)));
    await assertFails(setDoc(
      gitProviderAccount("user-a", "connection-1", userB),
      validGitProviderAccount(),
    ));
  });

  test("Git provider metadata rejects secrets and unsupported providers", async () => {
    const userA = environment.authenticatedContext("user-a");
    const account = gitProviderAccount("user-a", "connection-1", userA);

    await assertFails(setDoc(account, {
      ...validGitProviderAccount(),
      accessToken: "must-not-be-stored",
    }));
    await assertFails(setDoc(account, {
      ...validGitProviderAccount(),
      provider: "bitbucket",
    }));
  });

  test("clients cannot create update or delete entitlements", async () => {
    const userA = environment.authenticatedContext("user-a");
    await assertFails(setDoc(entitlement("user-a", userA), { plan: "pro" }));

    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), { plan: "free" });
    });

    await assertFails(setDoc(entitlement("user-a", userA), { plan: "pro" }));
    await assertFails(deleteDoc(entitlement("user-a", userA)));
  });

  test("unauthenticated clients are denied", async () => {
    const guest = environment.unauthenticatedContext();
    await assertFails(getDoc(settings("user-a", guest)));
    await assertFails(getDoc(entitlement("user-a", guest)));
  });
});
