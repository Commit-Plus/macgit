import { getAuth } from "firebase-admin/auth";
import {
  DocumentData,
  DocumentReference,
  Firestore,
  Timestamp,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";

export const DEVICE_ACCESS_SCHEMA_VERSION = 1;
export const DEVICE_SESSION_VERSION = 1;

export type DeviceRevocationReason =
  | "signedOut"
  | "replaced"
  | "planDowngrade"
  | "userRevoked"
  | "accountDeleted";

export interface CommitPlusDeviceMetadata {
  deviceID: string;
  platform: "macOS";
  modelFamily: string;
  osVersion: string;
  appVersion: string;
}

export interface AccountDeviceSummary extends CommitPlusDeviceMetadata {
  status: "active" | "revoked";
  createdAtMillis: number;
  lastSeenAtMillis: number;
  revokedAtMillis?: number;
  revokedReason?: DeviceRevocationReason;
}

export interface DeviceAccessSummarySnapshot {
  exists: boolean;
  data?: unknown;
}

export interface DeviceAccessTransaction {
  readEntitlement(): Promise<unknown>;
  readSummary(): Promise<DeviceAccessSummarySnapshot>;
  readDevices(deviceIDs: readonly string[]): Promise<Map<string, unknown>>;
  writeSummary(activeDeviceIDs: readonly string[], nowMillis: number): void;
  activateDevice(
    device: CommitPlusDeviceMetadata,
    createdAtMillis: number,
    nowMillis: number,
  ): void;
  revokeDevice(
    deviceID: string,
    reason: DeviceRevocationReason,
    nowMillis: number,
  ): void;
}

export interface DeviceAccessDependencies {
  runTransaction<T>(
    operation: (transaction: DeviceAccessTransaction) => Promise<T>,
  ): Promise<T>;
  createCustomToken(
    uid: string,
    claims: Record<string, string | number>,
  ): Promise<string>;
  now(): number;
}

export interface ActiveDeviceAccess {
  status: "active";
  limit: number;
  device: AccountDeviceSummary;
  devices: AccountDeviceSummary[];
  customToken: string;
}

export interface DeviceLimitReached {
  status: "limitReached";
  limit: number;
  devices: AccountDeviceSummary[];
}

export type DeviceClaimResult = ActiveDeviceAccess | DeviceLimitReached;

interface DeviceTransactionResult {
  status: "active" | "limitReached";
  limit: number;
  devices: AccountDeviceSummary[];
  device?: AccountDeviceSummary;
}

export class DeviceAccessDataError extends Error {}

export function deviceLimitForEntitlement(data: unknown): number {
  if (!isRecord(data)) return 1;
  return data.plan === "pro" && data.access === "active" ? 3 : 1;
}

export function validateDeviceMetadata(data: unknown): CommitPlusDeviceMetadata {
  if (!isRecord(data)) {
    throw new DeviceAccessDataError("Device information is missing.");
  }
  const allowedKeys = new Set([
    "deviceID",
    "platform",
    "modelFamily",
    "osVersion",
    "appVersion",
  ]);
  if (Object.keys(data).some((key) => !allowedKeys.has(key))) {
    throw new DeviceAccessDataError("Device information contains an unsupported field.");
  }

  const deviceID = boundedString(data.deviceID, "deviceID", 36);
  if (!isUUID(deviceID)) {
    throw new DeviceAccessDataError("The device identifier is invalid.");
  }
  if (data.platform !== "macOS") {
    throw new DeviceAccessDataError("The device platform is unsupported.");
  }

  return {
    deviceID,
    platform: "macOS",
    modelFamily: boundedString(data.modelFamily, "modelFamily", 80),
    osVersion: boundedString(data.osVersion, "osVersion", 40),
    appVersion: boundedString(data.appVersion, "appVersion", 40),
  };
}

export async function claimDeviceSlot(
  uid: string,
  device: CommitPlusDeviceMetadata,
  dependencies: DeviceAccessDependencies = productionDeviceAccessDependencies(uid),
): Promise<DeviceClaimResult> {
  const transactionResult = await dependencies.runTransaction(async (transaction) => {
    const entitlement = await transaction.readEntitlement();
    const summary = await transaction.readSummary();
    const activeDeviceIDs = activeDeviceIDsFromSummary(summary);
    const requestedDeviceIDs = unique([...activeDeviceIDs, device.deviceID]);
    const rawDevices = await transaction.readDevices(requestedDeviceIDs);
    const devices = decodeDevices(requestedDeviceIDs, rawDevices);
    const limit = deviceLimitForEntitlement(entitlement);
    const nowMillis = dependencies.now();
    const retainedIDs = retainedActiveDeviceIDs(activeDeviceIDs, devices, limit);
    const revokedIDs = activeDeviceIDs.filter((deviceID) => !retainedIDs.includes(deviceID));

    for (const revokedID of revokedIDs) {
      transaction.revokeDevice(revokedID, "planDowngrade", nowMillis);
    }

    if (retainedIDs.includes(device.deviceID)) {
      const existing = devices.get(device.deviceID);
      const createdAtMillis = existing?.createdAtMillis ?? nowMillis;
      transaction.writeSummary(retainedIDs, nowMillis);
      transaction.activateDevice(device, createdAtMillis, nowMillis);

      const activeDevice = activeSummary(device, createdAtMillis, nowMillis);
      const updatedDevices = activeSummaries(
        retainedIDs,
        new Map(devices).set(device.deviceID, activeDevice),
      );
      return activeTransactionResult(limit, activeDevice, updatedDevices);
    }

    if (retainedIDs.length >= limit) {
      if (revokedIDs.length > 0) {
        transaction.writeSummary(retainedIDs, nowMillis);
      }
      return limitTransactionResult(limit, activeSummaries(retainedIDs, devices));
    }

    const nextActiveIDs = [...retainedIDs, device.deviceID];
    const existing = devices.get(device.deviceID);
    const createdAtMillis = existing?.createdAtMillis ?? nowMillis;
    transaction.writeSummary(nextActiveIDs, nowMillis);
    transaction.activateDevice(device, createdAtMillis, nowMillis);

    const activeDevice = activeSummary(device, createdAtMillis, nowMillis);
    const updatedDevices = new Map(devices).set(device.deviceID, activeDevice);
    return activeTransactionResult(
      limit,
      activeDevice,
      activeSummaries(nextActiveIDs, updatedDevices),
    );
  });

  return attachCustomToken(uid, transactionResult, dependencies);
}

export async function replaceDeviceSlot(
  uid: string,
  replacingDeviceID: string,
  device: CommitPlusDeviceMetadata,
  dependencies: DeviceAccessDependencies = productionDeviceAccessDependencies(uid),
): Promise<DeviceClaimResult> {
  if (!isUUID(replacingDeviceID)) {
    throw new DeviceAccessDataError("The device selected for replacement is invalid.");
  }
  if (replacingDeviceID === device.deviceID) {
    return claimDeviceSlot(uid, device, dependencies);
  }

  const transactionResult = await dependencies.runTransaction(async (transaction) => {
    const entitlement = await transaction.readEntitlement();
    const summary = await transaction.readSummary();
    const activeDeviceIDs = activeDeviceIDsFromSummary(summary);
    const requestedDeviceIDs = unique([
      ...activeDeviceIDs,
      replacingDeviceID,
      device.deviceID,
    ]);
    const rawDevices = await transaction.readDevices(requestedDeviceIDs);
    const devices = decodeDevices(requestedDeviceIDs, rawDevices);
    const limit = deviceLimitForEntitlement(entitlement);
    const nowMillis = dependencies.now();
    const retainedIDs = retainedActiveDeviceIDs(activeDeviceIDs, devices, limit);

    if (!activeDeviceIDs.includes(replacingDeviceID)) {
      return limitTransactionResult(limit, activeSummaries(retainedIDs, devices));
    }

    const nextActiveIDs = retainedIDs
      .filter((deviceID) => deviceID !== replacingDeviceID && deviceID !== device.deviceID)
      .slice(0, Math.max(0, limit - 1));
    nextActiveIDs.push(device.deviceID);

    for (const activeDeviceID of activeDeviceIDs) {
      if (nextActiveIDs.includes(activeDeviceID)) continue;
      transaction.revokeDevice(
        activeDeviceID,
        activeDeviceID === replacingDeviceID ? "replaced" : "planDowngrade",
        nowMillis,
      );
    }

    const existing = devices.get(device.deviceID);
    const createdAtMillis = existing?.createdAtMillis ?? nowMillis;
    transaction.writeSummary(nextActiveIDs, nowMillis);
    transaction.activateDevice(device, createdAtMillis, nowMillis);

    const activeDevice = activeSummary(device, createdAtMillis, nowMillis);
    const updatedDevices = new Map(devices).set(device.deviceID, activeDevice);
    return activeTransactionResult(
      limit,
      activeDevice,
      activeSummaries(nextActiveIDs, updatedDevices),
    );
  });

  return attachCustomToken(uid, transactionResult, dependencies);
}

export async function releaseDeviceSlot(
  uid: string,
  deviceID: string,
  reason: DeviceRevocationReason,
  dependencies: DeviceAccessDependencies = productionDeviceAccessDependencies(uid),
): Promise<void> {
  if (!isUUID(deviceID)) {
    throw new DeviceAccessDataError("The device identifier is invalid.");
  }

  await dependencies.runTransaction(async (transaction) => {
    await transaction.readEntitlement();
    const summary = await transaction.readSummary();
    const activeDeviceIDs = activeDeviceIDsFromSummary(summary);
    await transaction.readDevices([deviceID]);
    if (!activeDeviceIDs.includes(deviceID)) return;

    const nowMillis = dependencies.now();
    transaction.writeSummary(
      activeDeviceIDs.filter((activeID) => activeID !== deviceID),
      nowMillis,
    );
    transaction.revokeDevice(deviceID, reason, nowMillis);
  });
}

export async function heartbeatDevice(
  uid: string,
  device: CommitPlusDeviceMetadata,
  dependencies: DeviceAccessDependencies = productionDeviceAccessDependencies(uid),
): Promise<void> {
  await dependencies.runTransaction(async (transaction) => {
    await transaction.readEntitlement();
    const summary = await transaction.readSummary();
    const activeDeviceIDs = activeDeviceIDsFromSummary(summary);
    const rawDevices = await transaction.readDevices([device.deviceID]);
    const devices = decodeDevices([device.deviceID], rawDevices);
    if (!activeDeviceIDs.includes(device.deviceID)) {
      throw new DeviceAccessDataError("This Mac is no longer active for the account.");
    }

    const nowMillis = dependencies.now();
    const createdAtMillis = devices.get(device.deviceID)?.createdAtMillis ?? nowMillis;
    transaction.activateDevice(device, createdAtMillis, nowMillis);
  });
}

export async function reconcileDeviceLimit(
  uid: string,
  dependencies: DeviceAccessDependencies = productionDeviceAccessDependencies(uid),
): Promise<void> {
  await dependencies.runTransaction(async (transaction) => {
    const entitlement = await transaction.readEntitlement();
    const summary = await transaction.readSummary();
    const activeDeviceIDs = activeDeviceIDsFromSummary(summary);
    const rawDevices = await transaction.readDevices(activeDeviceIDs);
    const devices = decodeDevices(activeDeviceIDs, rawDevices);
    const limit = deviceLimitForEntitlement(entitlement);
    const retainedIDs = retainedActiveDeviceIDs(activeDeviceIDs, devices, limit);
    const revokedIDs = activeDeviceIDs.filter((deviceID) => !retainedIDs.includes(deviceID));
    if (revokedIDs.length === 0) return;

    const nowMillis = dependencies.now();
    transaction.writeSummary(retainedIDs, nowMillis);
    for (const revokedID of revokedIDs) {
      transaction.revokeDevice(revokedID, "planDowngrade", nowMillis);
    }
  });
}

export async function listAccountDevices(
  uid: string,
  firestore: Firestore = getFirestore(),
): Promise<{ limit: number; devices: AccountDeviceSummary[] }> {
  const summaryReference = firestore.doc(`users/${uid}/deviceAccess/summary`);
  const entitlementReference = firestore.doc(`entitlements/${uid}`);
  const [summarySnapshot, entitlementSnapshot] = await Promise.all([
    summaryReference.get(),
    entitlementReference.get(),
  ]);
  const activeDeviceIDs = activeDeviceIDsFromSummary({
    exists: summarySnapshot.exists,
    data: summarySnapshot.data(),
  });
  const snapshots = activeDeviceIDs.length === 0
    ? []
    : await firestore.getAll(
      ...activeDeviceIDs.map((deviceID) => firestore.doc(`users/${uid}/devices/${deviceID}`)),
    );
  const rawDevices = new Map<string, unknown>();
  for (const snapshot of snapshots) {
    rawDevices.set(snapshot.id, snapshot.data());
  }

  return {
    limit: deviceLimitForEntitlement(entitlementSnapshot.data()),
    devices: activeSummaries(
      activeDeviceIDs,
      decodeDevices(activeDeviceIDs, rawDevices),
    ),
  };
}

export function productionDeviceAccessDependencies(
  uid: string,
  firestore: Firestore = getFirestore(),
): DeviceAccessDependencies {
  return {
    runTransaction: (operation) => firestore.runTransaction(async (transaction) => {
      const adapter = new FirestoreDeviceAccessTransaction(uid, firestore, transaction);
      return operation(adapter);
    }),
    createCustomToken: (tokenUID, claims) => getAuth().createCustomToken(tokenUID, claims),
    now: Date.now,
  };
}

class FirestoreDeviceAccessTransaction implements DeviceAccessTransaction {
  private readonly entitlementReference: DocumentReference<DocumentData>;
  private readonly summaryReference: DocumentReference<DocumentData>;

  constructor(
    private readonly uid: string,
    private readonly firestore: Firestore,
    private readonly transaction: Transaction,
  ) {
    this.entitlementReference = firestore.doc(`entitlements/${uid}`);
    this.summaryReference = firestore.doc(`users/${uid}/deviceAccess/summary`);
  }

  async readEntitlement(): Promise<unknown> {
    return (await this.transaction.get(this.entitlementReference)).data();
  }

  async readSummary(): Promise<DeviceAccessSummarySnapshot> {
    const snapshot = await this.transaction.get(this.summaryReference);
    return { exists: snapshot.exists, data: snapshot.data() };
  }

  async readDevices(deviceIDs: readonly string[]): Promise<Map<string, unknown>> {
    const uniqueDeviceIDs = unique(deviceIDs);
    const snapshots = await Promise.all(uniqueDeviceIDs.map((deviceID) =>
      this.transaction.get(this.deviceReference(deviceID))
    ));
    return new Map(snapshots.map((snapshot) => [snapshot.id, snapshot.data()]));
  }

  writeSummary(activeDeviceIDs: readonly string[], nowMillis: number): void {
    this.transaction.set(this.summaryReference, {
      schemaVersion: DEVICE_ACCESS_SCHEMA_VERSION,
      activeDeviceIDs: [...activeDeviceIDs],
      updatedAt: Timestamp.fromMillis(nowMillis),
    });
  }

  activateDevice(
    device: CommitPlusDeviceMetadata,
    createdAtMillis: number,
    nowMillis: number,
  ): void {
    this.transaction.set(this.deviceReference(device.deviceID), {
      schemaVersion: DEVICE_ACCESS_SCHEMA_VERSION,
      status: "active",
      platform: device.platform,
      modelFamily: device.modelFamily,
      osVersion: device.osVersion,
      appVersion: device.appVersion,
      createdAt: Timestamp.fromMillis(createdAtMillis),
      lastSeenAt: Timestamp.fromMillis(nowMillis),
    });
  }

  revokeDevice(
    deviceID: string,
    reason: DeviceRevocationReason,
    nowMillis: number,
  ): void {
    this.transaction.set(this.deviceReference(deviceID), {
      schemaVersion: DEVICE_ACCESS_SCHEMA_VERSION,
      status: "revoked",
      revokedAt: Timestamp.fromMillis(nowMillis),
      revokedReason: reason,
    }, { merge: true });
  }

  private deviceReference(deviceID: string): DocumentReference<DocumentData> {
    return this.firestore.doc(`users/${this.uid}/devices/${deviceID}`);
  }
}

async function attachCustomToken(
  uid: string,
  result: DeviceTransactionResult,
  dependencies: DeviceAccessDependencies,
): Promise<DeviceClaimResult> {
  if (result.status === "limitReached" || !result.device) {
    return {
      status: "limitReached",
      limit: result.limit,
      devices: result.devices,
    };
  }

  const customToken = await dependencies.createCustomToken(uid, {
    commitPlusDeviceID: result.device.deviceID,
    commitPlusDeviceSessionVersion: DEVICE_SESSION_VERSION,
  });
  return {
    status: "active",
    limit: result.limit,
    device: result.device,
    devices: result.devices,
    customToken,
  };
}

function activeDeviceIDsFromSummary(summary: DeviceAccessSummarySnapshot): string[] {
  if (!summary.exists) return [];
  if (!isRecord(summary.data)
      || summary.data.schemaVersion !== DEVICE_ACCESS_SCHEMA_VERSION
      || !Array.isArray(summary.data.activeDeviceIDs)) {
    throw new DeviceAccessDataError("The account device registry is malformed.");
  }

  const deviceIDs = summary.data.activeDeviceIDs;
  if (!deviceIDs.every((value) => typeof value === "string" && isUUID(value))) {
    throw new DeviceAccessDataError("The account device registry contains an invalid device.");
  }
  if (new Set(deviceIDs).size !== deviceIDs.length || deviceIDs.length > 3) {
    throw new DeviceAccessDataError("The account device registry is inconsistent.");
  }
  return [...deviceIDs];
}

function decodeDevices(
  deviceIDs: readonly string[],
  rawDevices: ReadonlyMap<string, unknown>,
): Map<string, AccountDeviceSummary> {
  const result = new Map<string, AccountDeviceSummary>();
  for (const deviceID of deviceIDs) {
    result.set(deviceID, decodeDevice(deviceID, rawDevices.get(deviceID)));
  }
  return result;
}

function decodeDevice(deviceID: string, data: unknown): AccountDeviceSummary {
  if (!isRecord(data)) {
    return placeholderDevice(deviceID);
  }

  const status = data.status === "revoked" ? "revoked" : "active";
  const createdAtMillis = timestampMillis(data.createdAt) ?? 0;
  const lastSeenAtMillis = timestampMillis(data.lastSeenAt) ?? createdAtMillis;
  const result: AccountDeviceSummary = {
    deviceID,
    platform: "macOS",
    modelFamily: optionalBoundedString(data.modelFamily, 80) ?? "Mac",
    osVersion: optionalBoundedString(data.osVersion, 40) ?? "Unknown",
    appVersion: optionalBoundedString(data.appVersion, 40) ?? "Unknown",
    status,
    createdAtMillis,
    lastSeenAtMillis,
  };
  const revokedAtMillis = timestampMillis(data.revokedAt);
  if (revokedAtMillis !== undefined) result.revokedAtMillis = revokedAtMillis;
  if (isRevocationReason(data.revokedReason)) result.revokedReason = data.revokedReason;
  return result;
}

function placeholderDevice(deviceID: string): AccountDeviceSummary {
  return {
    deviceID,
    platform: "macOS",
    modelFamily: "Mac",
    osVersion: "Unknown",
    appVersion: "Unknown",
    status: "active",
    createdAtMillis: 0,
    lastSeenAtMillis: 0,
  };
}

function retainedActiveDeviceIDs(
  activeDeviceIDs: readonly string[],
  devices: ReadonlyMap<string, AccountDeviceSummary>,
  limit: number,
): string[] {
  return [...activeDeviceIDs]
    .sort((leftID, rightID) => compareDevices(
      devices.get(leftID) ?? placeholderDevice(leftID),
      devices.get(rightID) ?? placeholderDevice(rightID),
    ))
    .slice(0, limit);
}

function activeSummaries(
  activeDeviceIDs: readonly string[],
  devices: ReadonlyMap<string, AccountDeviceSummary>,
): AccountDeviceSummary[] {
  return activeDeviceIDs
    .map((deviceID) => devices.get(deviceID) ?? placeholderDevice(deviceID))
    .map((device) => ({ ...device, status: "active" as const }))
    .sort(compareDevices);
}

function compareDevices(left: AccountDeviceSummary, right: AccountDeviceSummary): number {
  if (left.lastSeenAtMillis !== right.lastSeenAtMillis) {
    return right.lastSeenAtMillis - left.lastSeenAtMillis;
  }
  if (left.createdAtMillis !== right.createdAtMillis) {
    return right.createdAtMillis - left.createdAtMillis;
  }
  return left.deviceID.localeCompare(right.deviceID);
}

function activeSummary(
  device: CommitPlusDeviceMetadata,
  createdAtMillis: number,
  lastSeenAtMillis: number,
): AccountDeviceSummary {
  return {
    ...device,
    status: "active",
    createdAtMillis,
    lastSeenAtMillis,
  };
}

function activeTransactionResult(
  limit: number,
  device: AccountDeviceSummary,
  devices: AccountDeviceSummary[],
): DeviceTransactionResult {
  return { status: "active", limit, device, devices };
}

function limitTransactionResult(
  limit: number,
  devices: AccountDeviceSummary[],
): DeviceTransactionResult {
  return { status: "limitReached", limit, devices };
}

function boundedString(value: unknown, name: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new DeviceAccessDataError(`Device field '${name}' must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maximumLength) {
    throw new DeviceAccessDataError(`Device field '${name}' has an invalid length.`);
  }
  return trimmed;
}

function optionalBoundedString(value: unknown, maximumLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= maximumLength ? trimmed : undefined;
}

function timestampMillis(value: unknown): number | undefined {
  if (value instanceof Timestamp) return value.toMillis();
  if (isRecord(value) && typeof value.toMillis === "function") {
    const result = value.toMillis();
    return typeof result === "number" && Number.isFinite(result) ? result : undefined;
  }
  return undefined;
}

function isRevocationReason(value: unknown): value is DeviceRevocationReason {
  return value === "signedOut"
    || value === "replaced"
    || value === "planDowngrade"
    || value === "userRevoked"
    || value === "accountDeleted";
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function unique(values: readonly string[]): string[] {
  return [...new Set(values)];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
