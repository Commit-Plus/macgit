import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  DeviceAccessDataError,
  claimDeviceSlot,
  heartbeatDevice,
  listAccountDevices,
  reconcileDeviceLimit,
  releaseDeviceSlot,
  replaceDeviceSlot,
  validateDeviceMetadata,
} from "./device-access.js";

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
  deleteCollection(path: string): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

function productionDependencies(): AccountDeletionDependencies {
  return {
    deleteDocument: async (path) => {
      await getFirestore().doc(path).delete();
    },
    deleteCollection: async (path) => {
      const firestore = getFirestore();
      while (true) {
        const snapshot = await firestore.collection(path).limit(400).get();
        if (snapshot.empty) return;
        const batch = firestore.batch();
        for (const document of snapshot.docs) batch.delete(document.ref);
        await batch.commit();
      }
    },
    deleteUser: (uid) => getAuth().deleteUser(uid),
  };
}

export async function deleteAccountData(
  uid: string,
  dependencies: AccountDeletionDependencies = productionDependencies(),
): Promise<void> {
  await Promise.all([
    dependencies.deleteCollection(`users/${uid}/devices`),
    dependencies.deleteDocument(`users/${uid}/deviceAccess/summary`),
  ]);

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

export const claimCommitPlusDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = authenticatedUID(request.auth?.uid);
  try {
    const device = validateDeviceMetadata(request.data);
    return await claimDeviceSlot(uid, device);
  } catch (error) {
    throw deviceAccessHttpsError(error);
  }
});

export const replaceCommitPlusDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = authenticatedUID(request.auth?.uid);
  try {
    const data = request.data as { replacingDeviceID?: unknown; device?: unknown } | undefined;
    if (typeof data?.replacingDeviceID !== "string") {
      throw new DeviceAccessDataError("Choose an active Mac to replace.");
    }
    const device = validateDeviceMetadata(data.device);
    return await replaceDeviceSlot(uid, data.replacingDeviceID, device);
  } catch (error) {
    throw deviceAccessHttpsError(error);
  }
});

export const releaseCommitPlusDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = authenticatedUID(request.auth?.uid);
  const claimedDeviceID = request.auth?.token.commitPlusDeviceID;
  if (typeof claimedDeviceID !== "string") {
    throw new HttpsError("permission-denied", "This Commit+ session is not bound to a Mac.");
  }

  try {
    await releaseDeviceSlot(uid, claimedDeviceID, "signedOut");
    return { released: true };
  } catch (error) {
    throw deviceAccessHttpsError(error);
  }
});

export const heartbeatCommitPlusDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = authenticatedUID(request.auth?.uid);
  const claimedDeviceID = request.auth?.token.commitPlusDeviceID;
  try {
    const device = validateDeviceMetadata(request.data);
    if (claimedDeviceID !== device.deviceID) {
      throw new HttpsError("permission-denied", "This Commit+ session belongs to another Mac.");
    }
    await heartbeatDevice(uid, device);
    return { active: true };
  } catch (error) {
    throw deviceAccessHttpsError(error);
  }
});

export const listCommitPlusDevices = onCall({ invoker: "public" }, async (request) => {
  const uid = authenticatedUID(request.auth?.uid);
  try {
    return await listAccountDevices(uid);
  } catch (error) {
    throw deviceAccessHttpsError(error);
  }
});

export const reconcileCommitPlusDeviceLimit = onDocumentWritten(
  "entitlements/{uid}",
  async (event) => {
    const uid = event.params.uid;
    if (typeof uid !== "string" || uid.length === 0) return;
    await reconcileDeviceLimit(uid);
  },
);

function authenticatedUID(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to manage Commit+ devices.");
  }
  return uid;
}

function deviceAccessHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof DeviceAccessDataError) {
    return new HttpsError("failed-precondition", error.message);
  }
  console.error("Commit+ device access failed", error);
  return new HttpsError("internal", "Commit+ could not update account device access.");
}
