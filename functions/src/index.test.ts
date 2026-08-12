import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AccountDeletionDependencies,
  createWebSignInTokenForUser,
  deleteAccountData,
  WebSignInTokenDependencies,
} from "./index.js";

test("web sign-in token is created for the authenticated Firebase user", async () => {
  const requestedUIDs: string[] = [];
  const dependencies: WebSignInTokenDependencies = {
    async createCustomToken(uid) {
      requestedUIDs.push(uid);
      return "custom-token";
    },
  };

  const token = await createWebSignInTokenForUser("user-a", dependencies);

  assert.equal(token, "custom-token");
  assert.deepEqual(requestedUIDs, ["user-a"]);
});

test("account deletion removes owned documents and auth user", async () => {
  const deletedDocuments: string[] = [];
  const deletedUsers: string[] = [];
  const dependencies: AccountDeletionDependencies = {
    async deleteDocument(path) { deletedDocuments.push(path); },
    async deleteCollection(path) { deletedCollections.push(path); },
    async deleteUser(uid) { deletedUsers.push(uid); },
  };
  const deletedCollections: string[] = [];

  await deleteAccountData("user-a", dependencies);

  assert.deepEqual(deletedDocuments.sort(), [
    "entitlements/user-a",
    "users/user-a/deviceAccess/summary",
    "users/user-a/settings/app",
  ]);
  assert.deepEqual(deletedCollections, ["users/user-a/devices"]);
  assert.deepEqual(deletedUsers, ["user-a"]);
});

test("account deletion is idempotent when the auth user is already absent", async () => {
  const dependencies: AccountDeletionDependencies = {
    async deleteDocument() {},
    async deleteCollection() {},
    async deleteUser() {
      throw { code: "auth/user-not-found" };
    },
  };

  await assert.doesNotReject(deleteAccountData("user-a", dependencies));
});

test("unexpected auth deletion failures propagate", async () => {
  const dependencies: AccountDeletionDependencies = {
    async deleteDocument() {},
    async deleteCollection() {},
    async deleteUser() {
      throw new Error("auth unavailable");
    },
  };

  await assert.rejects(deleteAccountData("user-a", dependencies), /auth unavailable/);
});
