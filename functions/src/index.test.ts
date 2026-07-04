import assert from "node:assert/strict";
import { test } from "node:test";
import { AccountDeletionDependencies, deleteAccountData } from "./index.js";

test("account deletion removes owned documents and auth user", async () => {
  const deletedDocuments: string[] = [];
  const deletedUsers: string[] = [];
  const dependencies: AccountDeletionDependencies = {
    async deleteDocument(path) { deletedDocuments.push(path); },
    async deleteUser(uid) { deletedUsers.push(uid); },
  };

  await deleteAccountData("user-a", dependencies);

  assert.deepEqual(deletedDocuments.sort(), [
    "entitlements/user-a",
    "users/user-a/settings/app",
  ]);
  assert.deepEqual(deletedUsers, ["user-a"]);
});

test("account deletion is idempotent when the auth user is already absent", async () => {
  const dependencies: AccountDeletionDependencies = {
    async deleteDocument() {},
    async deleteUser() {
      throw { code: "auth/user-not-found" };
    },
  };

  await assert.doesNotReject(deleteAccountData("user-a", dependencies));
});

test("unexpected auth deletion failures propagate", async () => {
  const dependencies: AccountDeletionDependencies = {
    async deleteDocument() {},
    async deleteUser() {
      throw new Error("auth unavailable");
    },
  };

  await assert.rejects(deleteAccountData("user-a", dependencies), /auth unavailable/);
});
