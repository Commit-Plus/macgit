# Firebase Foundation Phase 2 Entitlement and Account Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Free/Pro entitlement server-controlled, provide safe admin test assignment, and complete authenticated account deletion.

**Architecture:** `EntitlementStore` converts Firestore documents into app-owned models and defaults missing/malformed records to Free. Firestore rules prevent client escalation; Admin SDK scripts and callable Functions own privileged writes.

**Tech Stack:** Swift, FirebaseFirestore, Firebase Functions 2nd gen, TypeScript, Firebase Admin SDK, Firestore Emulator, XCTest.

---

## File Structure

- Create `macgit/Services/EntitlementProviding.swift` and `FirestoreEntitlementStore.swift`.
- Modify `AccountSessionController`, Account menu, and Manage Account sheet.
- Create `firebase.json`, `firestore.rules`, `functions/`, and `scripts/firebase/` support.
- Create Swift policy tests and Node emulator/rules tests.

### Task 1: Add Entitlement Boundary and Decoder

**Files:**
- Create: `macgit/Services/EntitlementProviding.swift`
- Create: `macgit/Services/FirestoreEntitlementStore.swift`
- Create: `macgitTests/EntitlementDocumentDecoderTests.swift`

- [x] **Step 1: Write decoder tests**

Test a valid active Pro document, a missing document returning `.free`, and unknown/wrong-type fields returning `.free` with a nonfatal diagnostic.

- [x] **Step 2: Add protocol and decoder**

```swift
protocol ObservationToken { func cancel() }

protocol EntitlementProviding {
    func observe(uid: String, onChange: @escaping (AccountEntitlement) -> Void) -> ObservationToken
}

enum EntitlementDocumentDecoder {
    static func decode(_ data: [String: Any]?) -> AccountEntitlement {
        guard let data,
              let planRaw = data["plan"] as? String,
              let plan = AccountPlan(rawValue: planRaw),
              let accessRaw = data["access"] as? String,
              let access = EntitlementAccess(rawValue: accessRaw),
              let statusRaw = data["billingStatus"] as? String,
              let status = BillingStatus(rawValue: statusRaw)
        else { return .free }
        return AccountEntitlement(
            plan: plan,
            access: access,
            billingStatus: status,
            source: (data["source"] as? String).flatMap(EntitlementSource.init(rawValue:)),
            currentPeriodEnd: (data["currentPeriodEnd"] as? Timestamp)?.dateValue(),
            cancelAtPeriodEnd: data["cancelAtPeriodEnd"] as? Bool ?? false
        )
    }
}
```

- [x] **Step 3: Implement Firestore listener**

Observe `entitlements/{uid}` on the main queue; map document/error to entitlement state without granting Pro on error. Return an app-owned cancellation token rather than exposing Firebase's concrete listener type from views.

- [x] **Step 4: Run focused tests and commit**

Expected: decoder tests pass.

### Task 2: Gate Account UI from Live Entitlement

**Files:**
- Modify: `macgit/App/AccountSessionController.swift`
- Modify: `macgit/Views/Account/AccountToolbarMenu.swift`
- Modify: `macgit/Views/Account/ManageAccountSheet.swift`
- Create: `macgitTests/EntitlementGateTests.swift`

- [x] **Step 1: Test listener lifecycle**

Assert sign-in starts exactly one entitlement observation, a Pro update changes menu policy, sign-out cancels observation and resets `.free`, and listener failure never grants access.

- [x] **Step 2: Add published entitlement state**

```swift
@Published private(set) var entitlement: AccountEntitlement = .free
@Published private(set) var entitlementError: String?
```

Start/stop observation on auth transitions. Update menu and Manage Account labels from the normalized state. Keep upgrade and subscription actions disabled with `Coming later` until Polar work.

- [x] **Step 3: Run focused tests and commit**

Expected: entitlement gate and menu tests pass.

### Task 3: Add Firestore Rules and Emulator Tests

**Files:**
- Create: `firebase.json`
- Create: `firestore.rules`
- Create: `firebase-tests/package.json`
- Create: `firebase-tests/firestore.rules.test.mjs`

- [x] **Step 1: Add deny-by-default rules**

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/settings/app {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow write: if request.auth != null && request.auth.uid == uid
        && request.resource.data.keys().hasOnly([
          'schemaVersion', 'showToolbarButtonText', 'showSubmodules', 'showSubtrees', 'updatedAt'
        ]);
    }
    match /entitlements/{uid} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow write: if false;
    }
    match /{document=**} { allow read, write: if false; }
  }
}
```

- [x] **Step 2: Test isolation and escalation denial**

Use `@firebase/rules-unit-testing` to prove user A reads only its own settings/entitlement, cannot read user B, and cannot create/update/delete an entitlement. Use rules-disabled context to seed documents.

- [x] **Step 3: Run emulator tests**

```bash
firebase emulators:exec --only firestore "npm --prefix firebase-tests test"
```

Expected: all rules tests pass.

- [x] **Step 4: Commit**

```bash
git add firebase.json firestore.rules firebase-tests
git commit -m "test: secure Firebase account documents"
```

### Task 4: Add Admin Test Entitlement Script

**Files:**
- Create: `scripts/firebase/package.json`
- Create: `scripts/firebase/set-entitlement.mjs`
- Modify: `docs/firebase-setup.md`

- [x] **Step 1: Implement explicit grant/revoke commands**

```javascript
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const [uid, mode] = process.argv.slice(2);
if (!uid || !["grant", "revoke"].includes(mode)) {
  throw new Error("Usage: node set-entitlement.mjs <firebase-uid> <grant|revoke>");
}
initializeApp({ credential: applicationDefault() });
const active = mode === "grant";
await getFirestore().doc(`entitlements/${uid}`).set({
  plan: active ? "pro" : "free",
  access: active ? "active" : "inactive",
  billingStatus: active ? "active" : "none",
  source: "admin_test",
  cancelAtPeriodEnd: false,
  updatedAt: FieldValue.serverTimestamp()
});
```

- [x] **Step 2: Document Application Default Credentials and emulator usage**

Include exact grant/revoke commands and warn that the script is an operator tool, never bundled into the app.

- [x] **Step 3: Verify against emulator and commit**

Expected: granting changes the seeded user's entitlement to active Pro; revoking returns Free.

### Task 5: Add Secure Account Deletion Function

**Files:**
- Create: `functions/package.json`
- Create: `functions/tsconfig.json`
- Create: `functions/src/index.ts`
- Modify: `macgit.xcodeproj/project.pbxproj`
- Modify: `macgit/Services/AccountAuthenticating.swift`
- Modify: `macgit/Services/FirebaseAuthService.swift`
- Modify: `macgit/Views/Account/ManageAccountSheet.swift`

- [x] **Step 1: Implement callable deletion**

Add the `FirebaseFunctions` product from the existing Firebase package to the `macgit` target, then implement:

```typescript
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

initializeApp();
export const deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in again before deleting the account.");
  const authTime = Number(request.auth.token.auth_time ?? 0);
  if (Math.floor(Date.now() / 1000) - authTime > 300) {
    throw new HttpsError("failed-precondition", "Recent authentication is required.");
  }
  const db = getFirestore();
  await Promise.all([
    db.doc(`users/${uid}/settings/app`).delete(),
    db.doc(`entitlements/${uid}`).delete()
  ]);
  await getAuth().deleteUser(uid);
  return { deleted: true };
});
```

- [x] **Step 2: Add client confirmation and recent-auth recovery**

Expose `deleteAccount()` on the auth boundary. Manage Account shows a destructive confirmation, requests reauthentication when Firebase returns `requires-recent-login`, calls the function, then resets local session state. Never touch local repositories or recent paths.

- [x] **Step 3: Test idempotent backend behavior and controller failure restoration**

Expected: deletion clears both documents and auth user; a failed call leaves the controller authenticated with an actionable error.

- [x] **Step 4: Run all Firebase tests and full Xcode suite**

Expected: Firebase tests pass and TEST SUCCEEDED.

- [x] **Step 5: Commit and mark Phase 2 complete**

```bash
git add functions macgit/Services macgit/Views/Account macgitTests docs/superpowers/plans/2026-07-02-firebase-foundation-roadmap.md
git commit -m "feat: add secure Pro entitlement lifecycle"
```
