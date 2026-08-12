import { readFileSync } from "node:fs";
import { after, afterEach, before, beforeEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";

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

const deviceIDs = {
  "user-a": "00000000-0000-4000-8000-000000000001",
  "user-b": "00000000-0000-4000-8000-000000000002",
};

beforeEach(async () => {
  await environment.withSecurityRulesDisabled(async (admin) => {
    for (const [uid, deviceID] of Object.entries(deviceIDs)) {
      await setDoc(device(uid, deviceID, admin), validDeviceRecord());
    }
  });
});

function deviceContext(uid, deviceID = deviceIDs[uid]) {
  return environment.authenticatedContext(uid, {
    commitPlusDeviceID: deviceID,
    commitPlusDeviceSessionVersion: 1,
  });
}

function settings(uid, context) {
  return doc(context.firestore(), `users/${uid}/settings/app`);
}

function entitlement(uid, context) {
  return doc(context.firestore(), `entitlements/${uid}`);
}

function releaseFeaturePolicy(context) {
  return doc(context.firestore(), "featurePolicies/release");
}

function gitProviderAccount(uid, connectionID, context) {
  return doc(context.firestore(), `users/${uid}/gitProviderAccounts/${connectionID}`);
}

function repositoryBookmark(uid, bookmarkID, context) {
  return doc(context.firestore(), `users/${uid}/repositoryBookmarks/${bookmarkID}`);
}

function device(uid, deviceID, context) {
  return doc(context.firestore(), `users/${uid}/devices/${deviceID}`);
}

function validDeviceRecord(overrides = {}) {
  return {
    schemaVersion: 1,
    status: "active",
    platform: "macOS",
    modelFamily: "MacBook Pro",
    osVersion: "26.2",
    appVersion: "1.0.4",
    createdAt: serverTimestamp(),
    lastSeenAt: serverTimestamp(),
    ...overrides,
  };
}

function validSettings() {
  return {
    schemaVersion: 1,
    appearance: "dark",
    showToolbarButtonText: true,
    showSubmodules: false,
    showSubtrees: true,
    showHeaderBranchButton: true,
    showHeaderMergeButton: false,
    showHeaderStashButton: true,
    showHeaderRemoteButton: false,
    showHeaderFinderButton: true,
    showHeaderEditorButton: true,
    showHeaderTerminalButton: false,
    historyBranchFilter: "branch:origin/feature/login",
    historyIncludeRemotes: true,
    autoFetchEnabled: true,
    refreshOnAppActive: false,
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
    transportProtocol: "https",
    connectedAt: serverTimestamp(),
    lastValidatedAt: serverTimestamp(),
  };
}

function validRepositoryBookmark() {
  return {
    schemaVersion: 1,
    canonicalKey: "github.com/openai/codex",
    name: "codex",
    provider: "github",
    host: "github.com",
    ownerPath: "openai",
    remoteURL: "https://github.com/openai/codex.git",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

describe("Firestore ownership rules", () => {
  test("a user can read and write only their own settings", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");

    await assertSucceeds(setDoc(settings("user-a", userA), validSettings()));
    await assertSucceeds(getDoc(settings("user-a", userA)));
    await assertFails(getDoc(settings("user-a", userB)));
    await assertFails(setDoc(settings("user-a", userB), validSettings()));
  });

  test("settings reject missing and unknown fields", async () => {
    const userA = deviceContext("user-a");
    const optionalFields = new Set([
      "appearance",
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderEditorButton",
      "showHeaderTerminalButton",
      "historyBranchFilter",
      "historyIncludeRemotes",
      "autoFetchEnabled",
      "refreshOnAppActive",
    ]);

    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      unexpected: true,
    }));

    for (const key of Object.keys(validSettings())) {
      if (optionalFields.has(key)) continue;
      const missingField = validSettings();
      delete missingField[key];
      await assertFails(setDoc(settings("user-a", userA), missingField));
    }
  });

  test("settings reject unsupported schema versions and every wrong field type", async () => {
    const userA = deviceContext("user-a");
    const invalidValues = {
      schemaVersion: 2,
      appearance: true,
      showToolbarButtonText: "true",
      showSubmodules: "false",
      showSubtrees: 1,
      historyBranchFilter: 123,
      historyIncludeRemotes: "true",
      updatedAt: "now",
    };

    for (const [key, value] of Object.entries(invalidValues)) {
      await assertFails(setDoc(settings("user-a", userA), {
        ...validSettings(),
        [key]: value,
      }));
    }
  });

  test("settings accept optional settings fields", async () => {
    const userA = deviceContext("user-a");

    await assertSucceeds(setDoc(settings("user-a", userA), validSettings()));
  });

  test("settings reject wrong type for optional settings fields", async () => {
    const userA = deviceContext("user-a");

    for (const key of [
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderEditorButton",
      "showHeaderTerminalButton",
      "historyIncludeRemotes",
      "autoFetchEnabled",
      "refreshOnAppActive",
    ]) {
      await assertFails(setDoc(settings("user-a", userA), {
        ...validSettings(),
        [key]: "true",
      }));
    }

    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      historyBranchFilter: 123,
    }));
    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      historyBranchFilter: "branch:",
    }));
    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      appearance: "sepia",
    }));
  });

  test("settings accept legacy documents without header button fields", async () => {
    const userA = deviceContext("user-a");
    const legacy = validSettings();
    for (const key of [
      "appearance",
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderEditorButton",
      "showHeaderTerminalButton",
      "historyBranchFilter",
      "historyIncludeRemotes",
      "autoFetchEnabled",
      "refreshOnAppActive",
    ]) {
      delete legacy[key];
    }

    await assertSucceeds(setDoc(settings("user-a", userA), legacy));
  });

  test("a user can read only their own entitlement", async () => {
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), {
        plan: "pro",
        access: "active",
        billingStatus: "active",
      });
    });
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");

    await assertSucceeds(getDoc(entitlement("user-a", userA)));
    await assertFails(getDoc(entitlement("user-a", userB)));
  });

  test("a user can read and write only their own Git provider metadata", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
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
    const userA = deviceContext("user-a");
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

  test("Git provider metadata accepts HTTPS and SSH transport protocols", async () => {
    const userA = deviceContext("user-a");

    await assertSucceeds(setDoc(
      gitProviderAccount("user-a", "connection-https", userA),
      {
        ...validGitProviderAccount(),
        transportProtocol: "https",
      },
    ));
    await assertSucceeds(setDoc(
      gitProviderAccount("user-a", "connection-ssh", userA),
      {
        ...validGitProviderAccount(),
        transportProtocol: "ssh",
      },
    ));
  });

  test("a user can read and write only their own repository bookmarks", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
    const ownBookmark = repositoryBookmark("user-a", "bookmark-1", userA);

    await assertSucceeds(setDoc(ownBookmark, validRepositoryBookmark()));
    await assertSucceeds(getDoc(ownBookmark));
    await assertFails(getDoc(repositoryBookmark("user-a", "bookmark-1", userB)));
    await assertFails(setDoc(
      repositoryBookmark("user-a", "bookmark-1", userB),
      validRepositoryBookmark(),
    ));
    await assertSucceeds(deleteDoc(ownBookmark));
  });

  test("repository bookmarks reject local paths, secrets, and malformed metadata", async () => {
    const userA = deviceContext("user-a");
    const bookmark = repositoryBookmark("user-a", "bookmark-1", userA);

    for (const invalid of [
      { ...validRepositoryBookmark(), localPath: "/Users/test/Project/codex" },
      { ...validRepositoryBookmark(), accessToken: "must-not-be-stored" },
      { ...validRepositoryBookmark(), provider: "unknown" },
      { ...validRepositoryBookmark(), remoteURL: "file:///Users/test/codex" },
      { ...validRepositoryBookmark(), name: "" },
    ]) {
      await assertFails(setDoc(bookmark, invalid));
    }
  });

  test("Git provider metadata rejects unsupported transport protocols", async () => {
    const userA = deviceContext("user-a");

    await assertFails(setDoc(
      gitProviderAccount("user-a", "connection-1", userA),
      {
        ...validGitProviderAccount(),
        transportProtocol: "token",
      },
    ));
  });

  test("clients cannot create update or delete entitlements", async () => {
    const userA = deviceContext("user-a");
    await assertFails(setDoc(entitlement("user-a", userA), { plan: "pro" }));

    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), { plan: "free" });
    });

    await assertFails(setDoc(entitlement("user-a", userA), { plan: "pro" }));
    await assertFails(deleteDoc(entitlement("user-a", userA)));
  });

  test("all clients can read but cannot write the release feature policy", async () => {
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(releaseFeaturePolicy(admin), {
        schemaVersion: 1,
        revision: 1,
        features: {},
      });
    });

    const userA = deviceContext("user-a");
    const guest = environment.unauthenticatedContext();

    await assertSucceeds(getDoc(releaseFeaturePolicy(userA)));
    await assertSucceeds(getDoc(releaseFeaturePolicy(guest)));
    await assertFails(setDoc(releaseFeaturePolicy(userA), { revision: 2 }));
    await assertFails(setDoc(releaseFeaturePolicy(guest), { revision: 2 }));
    await assertFails(deleteDoc(releaseFeaturePolicy(userA)));
  });

  test("unauthenticated clients are denied", async () => {
    const guest = environment.unauthenticatedContext();
    await assertFails(getDoc(settings("user-a", guest)));
    await assertFails(getDoc(entitlement("user-a", guest)));
  });

  test("plain and malformed Firebase sessions cannot access account cloud data", async () => {
    const plain = environment.authenticatedContext("user-a");
    const wrongDevice = deviceContext(
      "user-a",
      "00000000-0000-4000-8000-000000000099",
    );
    const wrongVersion = environment.authenticatedContext("user-a", {
      commitPlusDeviceID: deviceIDs["user-a"],
      commitPlusDeviceSessionVersion: 2,
    });

    for (const context of [plain, wrongDevice, wrongVersion]) {
      await assertFails(getDoc(settings("user-a", context)));
      await assertFails(getDoc(entitlement("user-a", context)));
      await assertFails(setDoc(settings("user-a", context), validSettings()));
    }
  });

  test("a revoked Mac can observe its own record but cannot access sync or entitlement", async () => {
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(
        device("user-a", deviceIDs["user-a"], admin),
        validDeviceRecord({ status: "revoked", revokedReason: "replaced" }),
      );
    });
    const userA = deviceContext("user-a");

    await assertSucceeds(getDoc(device("user-a", deviceIDs["user-a"], userA)));
    await assertFails(getDoc(settings("user-a", userA)));
    await assertFails(getDoc(entitlement("user-a", userA)));
  });

  test("device records are server-owned, self-readable only, and never listable", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
    const ownDevice = device("user-a", deviceIDs["user-a"], userA);

    await assertSucceeds(getDoc(ownDevice));
    await assertFails(getDoc(device("user-a", deviceIDs["user-a"], userB)));
    await assertFails(setDoc(ownDevice, validDeviceRecord({ modelFamily: "Forged Mac" })));
    await assertFails(deleteDoc(ownDevice));
    await assertFails(getDocs(collection(userA.firestore(), "users/user-a/devices")));
  });
});
