import { promisify } from "node:util";
import { execFile } from "node:child_process";
import { test } from "node:test";
import assert from "node:assert/strict";

const run = promisify(execFile);
const projectId = "macgit-admin-script-test";

async function runEntitlementScript(mode) {
  await run(
    process.execPath,
    [new URL("../scripts/firebase/set-entitlement.mjs", import.meta.url).pathname, "user-a", mode],
    {
      env: {
        ...process.env,
        FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
        GCLOUD_PROJECT: projectId,
      },
    },
  );
}

async function entitlementData() {
  const response = await fetch(
    `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents/entitlements/user-a`,
    { headers: { Authorization: "Bearer owner" } },
  );
  assert.equal(response.ok, true);
  const document = await response.json();
  return Object.fromEntries(
    Object.entries(document.fields).map(([key, value]) => [
      key,
      value.stringValue ?? value.booleanValue ?? value.timestampValue,
    ]),
  );
}

test("admin script grants and revokes test Pro access", async () => {
  await runEntitlementScript("grant");
  const granted = await entitlementData();
  assert.equal(granted.plan, "pro");
  assert.equal(granted.access, "active");
  assert.equal(granted.billingStatus, "active");
  assert.equal(granted.source, "admin_test");

  await runEntitlementScript("revoke");
  const revoked = await entitlementData();
  assert.equal(revoked.plan, "free");
  assert.equal(revoked.access, "inactive");
  assert.equal(revoked.billingStatus, "none");
});
