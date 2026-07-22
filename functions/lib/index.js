"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteAccount = void 0;
exports.deleteAccountData = deleteAccountData;
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
(0, app_1.initializeApp)();
function productionDependencies() {
    return {
        deleteDocument: async (path) => {
            await (0, firestore_1.getFirestore)().doc(path).delete();
        },
        deleteUser: (uid) => (0, auth_1.getAuth)().deleteUser(uid),
    };
}
async function deleteAccountData(uid, dependencies = productionDependencies()) {
    await Promise.all([
        dependencies.deleteDocument(`users/${uid}/settings/app`),
        dependencies.deleteDocument(`entitlements/${uid}`),
    ]);
    try {
        await dependencies.deleteUser(uid);
    }
    catch (error) {
        const code = error.code;
        if (code !== "auth/user-not-found")
            throw error;
    }
}
exports.deleteAccount = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in again before deleting the account.");
    }
    const authTime = Number(request.auth?.token.auth_time ?? 0);
    if (Math.floor(Date.now() / 1000) - authTime > 300) {
        throw new https_1.HttpsError("failed-precondition", "Recent authentication is required.");
    }
    await deleteAccountData(uid);
    return { deleted: true };
});
//# sourceMappingURL=index.js.map