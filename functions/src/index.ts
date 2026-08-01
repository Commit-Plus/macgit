import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();

export interface WebSignInTokenDependencies {
  createCustomToken(uid: string): Promise<string>;
}

function webSignInTokenDependencies(): WebSignInTokenDependencies {
  return {
    createCustomToken: (uid) => getAuth().createCustomToken(uid),
  };
}

export async function createWebSignInTokenForUser(
  uid: string,
  dependencies: WebSignInTokenDependencies = webSignInTokenDependencies(),
): Promise<string> {
  return dependencies.createCustomToken(uid);
}

export const createWebSignInToken = onCall({ invoker: "public" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before opening Commit+ on the web.");
  }

  return { customToken: await createWebSignInTokenForUser(uid) };
});

export interface AccountDeletionDependencies {
  deleteDocument(path: string): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

function productionDependencies(): AccountDeletionDependencies {
  return {
    deleteDocument: async (path) => {
      await getFirestore().doc(path).delete();
    },
    deleteUser: (uid) => getAuth().deleteUser(uid),
  };
}

export async function deleteAccountData(
  uid: string,
  dependencies: AccountDeletionDependencies = productionDependencies(),
): Promise<void> {
  await Promise.all([
    dependencies.deleteDocument(`users/${uid}/settings/app`),
    dependencies.deleteDocument(`entitlements/${uid}`),
  ]);

  try {
    await dependencies.deleteUser(uid);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code !== "auth/user-not-found") throw error;
  }
}

export const deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in again before deleting the account.");
  }

  const authTime = Number(request.auth?.token.auth_time ?? 0);
  if (Math.floor(Date.now() / 1000) - authTime > 300) {
    throw new HttpsError("failed-precondition", "Recent authentication is required.");
  }

  await deleteAccountData(uid);
  return { deleted: true };
});
