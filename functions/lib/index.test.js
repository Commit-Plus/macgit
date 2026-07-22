"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = require("node:test");
const index_js_1 = require("./index.js");
(0, node_test_1.test)("account deletion removes owned documents and auth user", async () => {
    const deletedDocuments = [];
    const deletedUsers = [];
    const dependencies = {
        async deleteDocument(path) { deletedDocuments.push(path); },
        async deleteUser(uid) { deletedUsers.push(uid); },
    };
    await (0, index_js_1.deleteAccountData)("user-a", dependencies);
    strict_1.default.deepEqual(deletedDocuments.sort(), [
        "entitlements/user-a",
        "users/user-a/settings/app",
    ]);
    strict_1.default.deepEqual(deletedUsers, ["user-a"]);
});
(0, node_test_1.test)("account deletion is idempotent when the auth user is already absent", async () => {
    const dependencies = {
        async deleteDocument() { },
        async deleteUser() {
            throw { code: "auth/user-not-found" };
        },
    };
    await strict_1.default.doesNotReject((0, index_js_1.deleteAccountData)("user-a", dependencies));
});
(0, node_test_1.test)("unexpected auth deletion failures propagate", async () => {
    const dependencies = {
        async deleteDocument() { },
        async deleteUser() {
            throw new Error("auth unavailable");
        },
    };
    await strict_1.default.rejects((0, index_js_1.deleteAccountData)("user-a", dependencies), /auth unavailable/);
});
//# sourceMappingURL=index.test.js.map