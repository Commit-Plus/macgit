# Firebase Foundation Phase 3 Pro Settings Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync three global `AppState` preferences across devices for active Pro users with explicit first-merge choice and safe pause/resume.

**Architecture:** A pure coordinator consumes local snapshots, an app-owned cloud store protocol, identity, and entitlement. `AppState` remains immediate local truth; Firestore is observed only while authenticated, Pro, and enabled on that device.

**Tech Stack:** Swift, Combine, FirebaseFirestore, XCTest, Firestore Emulator.

---

## File Structure

- Create `macgit/Models/AppSettingsSnapshot.swift`.
- Create `macgit/Services/CloudSettingsStore.swift` and `FirestoreSettingsStore.swift`.
- Create `macgit/Services/SettingsSyncService.swift`.
- Modify `AppState`, `AccountSessionController`, Account views, and root injection.
- Add focused sync tests and extend Firestore rules tests.

### Task 1: Add Snapshot and Local Sync Preference

**Files:**
- Create: `macgit/Models/AppSettingsSnapshot.swift`
- Modify: `macgit/App/AppState.swift`
- Create: `macgitTests/AppSettingsSnapshotTests.swift`

- [x] **Step 1: Write snapshot round-trip tests**

```swift
import XCTest
@testable import macgit

final class AppSettingsSnapshotTests: XCTestCase {
    func testSnapshotContainsOnlyApprovedSettings() {
        let value = AppSettingsSnapshot(showToolbarButtonText: false, showSubmodules: true, showSubtrees: true)
        XCTAssertEqual(value.schemaVersion, 1)
    }
}
```

- [x] **Step 2: Add snapshot type**

```swift
struct AppSettingsSnapshot: Codable, Equatable {
    let schemaVersion: Int
    var showToolbarButtonText: Bool
    var showSubmodules: Bool
    var showSubtrees: Bool

    init(showToolbarButtonText: Bool, showSubmodules: Bool, showSubtrees: Bool) {
        schemaVersion = 1
        self.showToolbarButtonText = showToolbarButtonText
        self.showSubmodules = showSubmodules
        self.showSubtrees = showSubtrees
    }
}
```

- [x] **Step 3: Add AppState seam**

Add `snapshot`, `apply(_:)`, and device-local `syncEnabled` persisted under `settingsSyncEnabled`. `apply(_:)` updates only the three approved properties; it never changes transient window/repository state.

- [x] **Step 4: Run tests and commit**

### Task 2: Add Cloud Store Protocol and Firestore Adapter

**Files:**
- Create: `macgit/Services/CloudSettingsStore.swift`
- Create: `macgit/Services/FirestoreSettingsStore.swift`
- Create: `macgitTests/CloudSettingsDocumentTests.swift`

- [x] **Step 1: Define cloud contract**

```swift
protocol CloudSettingsStore {
    func load(uid: String) async throws -> AppSettingsSnapshot?
    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws
    func observe(uid: String, onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void) -> ObservationToken
}
```

- [x] **Step 2: Test exact document schema and malformed fallback**

Assert only `schemaVersion`, three booleans, and `updatedAt` are encoded; missing/wrong-type fields throw `CloudSettingsError.invalidDocument` and do not create a partial snapshot.

- [x] **Step 3: Implement Firestore adapter**

Use `users/{uid}/settings/app`, `FieldValue.serverTimestamp()`, and `addSnapshotListener`. Keep Firebase `Timestamp` conversion inside this adapter.

- [x] **Step 4: Run tests and commit**

### Task 3: Implement Pure Sync Coordinator

**Files:**
- Create: `macgit/Services/SettingsSyncService.swift`
- Create: `macgitTests/SettingsSyncServiceTests.swift`

- [x] **Step 1: Write state-machine tests**

Cover: ineligible guest; locked Free; Pro disabled; first enable with no cloud uploads local; equal cloud starts observing; conflicting cloud emits `.needsInitialChoice`; cloud/local choice saves or applies correctly; remote apply does not echo-upload; local edits debounce; sign-out/disable/past-due cancels observation; Pro restoration resumes when device preference remains enabled.

- [x] **Step 2: Define states and choice**

```swift
enum InitialSettingsChoice { case useCloud, keepThisMac, cancel }
enum SettingsSyncStatus: Equatable {
    case off, locked, starting, needsInitialChoice(AppSettingsSnapshot), syncing
    case paused, failed(String)
}
```

- [x] **Step 3: Implement coordinator**

Use a `Task`-based 500 ms debounce. Maintain `isApplyingRemote` only around `AppState.apply`; local change observation must ignore that interval. Cancel listener and pending debounce task whenever eligibility becomes false.

- [x] **Step 4: Run focused tests and commit**

Expected: all state-machine tests pass deterministically using a fake clock/store.

### Task 4: Wire Pro Sync UI and First-Merge Confirmation

**Files:**
- Modify: `macgit/Views/Account/AccountToolbarMenu.swift`
- Modify: `macgit/Views/Account/ManageAccountSheet.swift`
- Modify: `macgit/App/AccountSessionController.swift`
- Modify: `macgit/App/macgitApp.swift`

- [x] **Step 1: Render entitlement-aware control**

Guest/Free shows locked sync with Upgrade action. Active Pro shows a toggle and status (`Syncing`, `Paused`, or error). `past_due` and inactive Pro preserve the enabled preference but disable changes and show `Paused`.

- [x] **Step 2: Present initial conflict confirmation**

When status becomes `.needsInitialChoice`, show one sheet with current Mac and cloud values plus buttons in this order: `Cancel`, `Use Cloud Settings`, `Keep This Mac's Settings`. Cancel turns device sync back off.

- [x] **Step 3: Inject one sync service per app session**

The shared controller owns the service and updates eligibility from account UID, entitlement, and `AppState.syncEnabled`. Repository windows consume the same global preference state.

- [x] **Step 4: Run policy/controller tests and commit**

### Task 5: Tighten Rules and Verify End-to-End

**Files:**
- Modify: `firestore.rules`
- Modify: `firebase-tests/firestore.rules.test.mjs`
- Modify: `docs/firebase-setup.md`

- [x] **Step 1: Validate exact settings types**

Require schema version integer, three boolean fields, and timestamp `updatedAt`; reject missing keys, unknown keys, and wrong types.

- [x] **Step 2: Run emulator suite**

```bash
firebase emulators:exec --only auth,firestore,functions "npm --prefix firebase-tests test"
```

Expected: all auth/rules/function tests pass.

- [x] **Step 3: Run targeted Swift tests**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SettingsSyncServiceTests
```

Expected: PASS.

- [x] **Step 4: Run complete macOS suite**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: TEST SUCCEEDED. Do not launch the app.

- [x] **Step 5: Mark Phase 3 and roadmap complete**

Update Phase 3 to `[completed]`, include the verified landing commit, and state that Polar, Git provider auth, and repository-history sync remain separate roadmaps.

- [x] **Step 6: Commit**

```bash
git add macgit macgitTests firestore.rules firebase-tests docs/firebase-setup.md docs/superpowers/plans/2026-07-02-firebase-foundation-roadmap.md
git commit -m "feat: sync Pro app settings with Firebase"
```
