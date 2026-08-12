import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import {
  CommitPlusDeviceMetadata,
  DeviceAccessDataError,
  DeviceAccessDependencies,
  DeviceAccessSummarySnapshot,
  DeviceAccessTransaction,
  DeviceRevocationReason,
  claimDeviceSlot,
  deviceLimitForEntitlement,
  heartbeatDevice,
  reconcileDeviceLimit,
  releaseDeviceSlot,
  replaceDeviceSlot,
  validateDeviceMetadata,
} from "./device-access.js";

const deviceA = makeDevice("00000000-0000-4000-8000-000000000001", "MacBook Pro");
const deviceB = makeDevice("00000000-0000-4000-8000-000000000002", "Mac mini");
const deviceC = makeDevice("00000000-0000-4000-8000-000000000003", "Mac Studio");
const deviceD = makeDevice("00000000-0000-4000-8000-000000000004", "MacBook Air");

describe("Commit+ device access", () => {
  test("only active Pro receives three device slots", () => {
    assert.equal(deviceLimitForEntitlement(undefined), 1);
    assert.equal(deviceLimitForEntitlement({ plan: "free", access: "active" }), 1);
    assert.equal(deviceLimitForEntitlement({ plan: "pro", access: "inactive" }), 1);
    assert.equal(deviceLimitForEntitlement({ plan: "pro", access: "active" }), 3);
  });

  test("device metadata is strict and hardware-neutral", () => {
    assert.deepEqual(validateDeviceMetadata(deviceA), deviceA);
    assert.throws(
      () => validateDeviceMetadata({ ...deviceA, deviceID: "serial-number" }),
      DeviceAccessDataError,
    );
    assert.throws(
      () => validateDeviceMetadata({ ...deviceA, serialNumber: "C02SECRET" }),
      DeviceAccessDataError,
    );
    assert.throws(
      () => validateDeviceMetadata({ ...deviceA, platform: "Windows" }),
      DeviceAccessDataError,
    );
  });

  test("Free first claim succeeds and same-device claim is idempotent", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "free", access: "inactive" });

    const first = await claimDeviceSlot("user-a", deviceA, store.dependencies());
    store.advanceTime();
    const repeated = await claimDeviceSlot("user-a", deviceA, store.dependencies());

    assert.equal(first.status, "active");
    assert.equal(repeated.status, "active");
    assert.deepEqual(store.activeDeviceIDs, [deviceA.deviceID]);
    assert.equal(store.createdTokenClaims.length, 2);
    assert.equal(store.devices.get(deviceA.deviceID)?.lastSeenAt.toMillis(), store.nowMillis);
  });

  test("Free second device receives the active device list without a token", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "free", access: "inactive" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());

    const result = await claimDeviceSlot("user-a", deviceB, store.dependencies());

    assert.equal(result.status, "limitReached");
    assert.equal(result.limit, 1);
    assert.deepEqual(result.devices.map((device) => device.deviceID), [deviceA.deviceID]);
    assert.equal(store.createdTokenClaims.length, 1);
    assert.deepEqual(store.activeDeviceIDs, [deviceA.deviceID]);
  });

  test("active Pro allows three devices and denies the fourth", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "pro", access: "active" });
    for (const device of [deviceA, deviceB, deviceC]) {
      const result = await claimDeviceSlot("user-a", device, store.dependencies());
      assert.equal(result.status, "active");
      store.advanceTime();
    }

    const fourth = await claimDeviceSlot("user-a", deviceD, store.dependencies());

    assert.equal(fourth.status, "limitReached");
    assert.equal(fourth.limit, 3);
    assert.equal(fourth.devices.length, 3);
    assert.equal(store.activeDeviceIDs.length, 3);
  });

  test("two concurrent final-slot claims activate exactly one device", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "pro", access: "active" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());
    await claimDeviceSlot("user-a", deviceB, store.dependencies());

    const [left, right] = await Promise.all([
      claimDeviceSlot("user-a", deviceC, store.dependencies()),
      claimDeviceSlot("user-a", deviceD, store.dependencies()),
    ]);

    assert.deepEqual([left.status, right.status].sort(), ["active", "limitReached"]);
    assert.equal(store.activeDeviceIDs.length, 3);
    assert.equal(new Set(store.activeDeviceIDs).size, 3);
  });

  test("replacement atomically revokes the selected device and activates current", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "free", access: "inactive" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());

    const result = await replaceDeviceSlot(
      "user-a",
      deviceA.deviceID,
      deviceB,
      store.dependencies(),
    );

    assert.equal(result.status, "active");
    assert.deepEqual(store.activeDeviceIDs, [deviceB.deviceID]);
    assert.equal(store.devices.get(deviceA.deviceID)?.status, "revoked");
    assert.equal(store.devices.get(deviceA.deviceID)?.revokedReason, "replaced");
    assert.equal(store.devices.get(deviceB.deviceID)?.status, "active");
  });

  test("stale replacement does not activate a new device", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "free", access: "inactive" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());

    const result = await replaceDeviceSlot(
      "user-a",
      deviceC.deviceID,
      deviceB,
      store.dependencies(),
    );

    assert.equal(result.status, "limitReached");
    assert.deepEqual(store.activeDeviceIDs, [deviceA.deviceID]);
    assert.equal(store.devices.has(deviceB.deviceID), false);
  });

  test("replacement after downgrade revokes every excess Pro device", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "pro", access: "active" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());
    store.advanceTime();
    await claimDeviceSlot("user-a", deviceB, store.dependencies());
    store.advanceTime();
    await claimDeviceSlot("user-a", deviceC, store.dependencies());
    store.entitlement = { plan: "free", access: "inactive" };

    const result = await replaceDeviceSlot(
      "user-a",
      deviceA.deviceID,
      deviceD,
      store.dependencies(),
    );

    assert.equal(result.status, "active");
    assert.deepEqual(store.activeDeviceIDs, [deviceD.deviceID]);
    assert.equal(store.devices.get(deviceA.deviceID)?.revokedReason, "replaced");
    assert.equal(store.devices.get(deviceB.deviceID)?.revokedReason, "planDowngrade");
    assert.equal(store.devices.get(deviceC.deviceID)?.revokedReason, "planDowngrade");
  });

  test("Pro downgrade retains the most recently active Mac deterministically", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "pro", access: "active" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());
    store.advanceTime();
    await claimDeviceSlot("user-a", deviceB, store.dependencies());
    store.advanceTime();
    await claimDeviceSlot("user-a", deviceC, store.dependencies());
    store.entitlement = { plan: "free", access: "inactive" };

    await reconcileDeviceLimit("user-a", store.dependencies());

    assert.deepEqual(store.activeDeviceIDs, [deviceC.deviceID]);
    assert.equal(store.devices.get(deviceA.deviceID)?.revokedReason, "planDowngrade");
    assert.equal(store.devices.get(deviceB.deviceID)?.revokedReason, "planDowngrade");
  });

  test("release and heartbeat are idempotent and require an active slot", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "free", access: "inactive" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());
    store.advanceTime();
    await heartbeatDevice("user-a", deviceA, store.dependencies());
    assert.equal(store.devices.get(deviceA.deviceID)?.lastSeenAt.toMillis(), store.nowMillis);

    await releaseDeviceSlot("user-a", deviceA.deviceID, "signedOut", store.dependencies());
    await releaseDeviceSlot("user-a", deviceA.deviceID, "signedOut", store.dependencies());
    assert.deepEqual(store.activeDeviceIDs, []);
    await assert.rejects(
      heartbeatDevice("user-a", deviceA, store.dependencies()),
      /no longer active/,
    );
  });

  test("malformed server summary fails closed", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "pro", access: "active" });
    store.summary = { schemaVersion: 1, activeDeviceIDs: ["not-a-uuid"] };

    await assert.rejects(
      claimDeviceSlot("user-a", deviceA, store.dependencies()),
      /invalid device/,
    );
    assert.equal(store.createdTokenClaims.length, 0);
  });

  test("custom token contains only the server-owned device binding claims", async () => {
    const store = new InMemoryDeviceAccessStore({ plan: "pro", access: "active" });
    await claimDeviceSlot("user-a", deviceA, store.dependencies());

    assert.deepEqual(store.createdTokenClaims, [{
      uid: "user-a",
      claims: {
        commitPlusDeviceID: deviceA.deviceID,
        commitPlusDeviceSessionVersion: 1,
      },
    }]);
  });
});

interface StoredDevice extends CommitPlusDeviceMetadata {
  schemaVersion: 1;
  status: "active" | "revoked";
  createdAt: Timestamp;
  lastSeenAt: Timestamp;
  revokedAt?: Timestamp;
  revokedReason?: DeviceRevocationReason;
}

class InMemoryDeviceAccessStore {
  entitlement: unknown;
  summary: unknown;
  devices = new Map<string, StoredDevice>();
  nowMillis = 1_700_000_000_000;
  createdTokenClaims: Array<{
    uid: string;
    claims: Record<string, string | number>;
  }> = [];
  private transactionQueue: Promise<void> = Promise.resolve();

  init(entitlement: unknown) {
    this.entitlement = entitlement;
  }

  constructor(entitlement: unknown) {
    this.entitlement = entitlement;
    this.summary = undefined;
  }

  get activeDeviceIDs(): string[] {
    const summary = this.summary as { activeDeviceIDs?: unknown } | undefined;
    return Array.isArray(summary?.activeDeviceIDs)
      ? summary.activeDeviceIDs.filter((value): value is string => typeof value === "string")
      : [];
  }

  advanceTime(milliseconds = 1_000): void {
    this.nowMillis += milliseconds;
  }

  dependencies(): DeviceAccessDependencies {
    return {
      runTransaction: (operation) => this.enqueueTransaction(operation),
      createCustomToken: async (uid, claims) => {
        this.createdTokenClaims.push({ uid, claims });
        return `token-${this.createdTokenClaims.length}`;
      },
      now: () => this.nowMillis,
    };
  }

  private enqueueTransaction<T>(
    operation: (transaction: DeviceAccessTransaction) => Promise<T>,
  ): Promise<T> {
    const result = this.transactionQueue.then(async () => {
      const draft = new InMemoryDeviceAccessTransaction(this);
      const value = await operation(draft);
      draft.commit();
      return value;
    });
    this.transactionQueue = result.then(() => undefined, () => undefined);
    return result;
  }
}

class InMemoryDeviceAccessTransaction implements DeviceAccessTransaction {
  private summary: unknown;
  private devices: Map<string, StoredDevice>;

  constructor(private readonly store: InMemoryDeviceAccessStore) {
    this.summary = structuredClone(store.summary);
    this.devices = new Map(
      [...store.devices].map(([deviceID, device]) => [deviceID, { ...device }]),
    );
  }

  async readEntitlement(): Promise<unknown> {
    return structuredClone(this.store.entitlement);
  }

  async readSummary(): Promise<DeviceAccessSummarySnapshot> {
    return {
      exists: this.summary !== undefined,
      data: structuredClone(this.summary),
    };
  }

  async readDevices(deviceIDs: readonly string[]): Promise<Map<string, unknown>> {
    return new Map(deviceIDs.map((deviceID) => [deviceID, this.devices.get(deviceID)]));
  }

  writeSummary(activeDeviceIDs: readonly string[], nowMillis: number): void {
    this.summary = {
      schemaVersion: 1,
      activeDeviceIDs: [...activeDeviceIDs],
      updatedAt: Timestamp.fromMillis(nowMillis),
    };
  }

  activateDevice(
    device: CommitPlusDeviceMetadata,
    createdAtMillis: number,
    nowMillis: number,
  ): void {
    this.devices.set(device.deviceID, {
      ...device,
      schemaVersion: 1,
      status: "active",
      createdAt: Timestamp.fromMillis(createdAtMillis),
      lastSeenAt: Timestamp.fromMillis(nowMillis),
    });
  }

  revokeDevice(
    deviceID: string,
    reason: DeviceRevocationReason,
    nowMillis: number,
  ): void {
    const existing = this.devices.get(deviceID) ?? {
      ...makeDevice(deviceID, "Mac"),
      schemaVersion: 1 as const,
      status: "active" as const,
      createdAt: Timestamp.fromMillis(0),
      lastSeenAt: Timestamp.fromMillis(0),
    };
    this.devices.set(deviceID, {
      ...existing,
      status: "revoked",
      revokedAt: Timestamp.fromMillis(nowMillis),
      revokedReason: reason,
    });
  }

  commit(): void {
    this.store.summary = this.summary;
    this.store.devices = this.devices;
  }
}

function makeDevice(deviceID: string, modelFamily: string): CommitPlusDeviceMetadata {
  return {
    deviceID,
    platform: "macOS",
    modelFamily,
    osVersion: "26.2",
    appVersion: "1.0.4",
  };
}
