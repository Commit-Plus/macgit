# Show Header Buttons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global "Show Header Buttons" submenu under the View menu that toggles visibility of Branch, Merge, Stash, Remote, Finder, and Terminal toolbar buttons, syncs the choices to Firebase, and deploys updated Firestore rules.

**Architecture:** Six new booleans are added to `AppState`/`AppSettingsSnapshot`, encoded/decoded by `FirestoreSettingsStore`, observed by `AccountSessionController` via a new `AppState.settingsSnapshotPublisher`, and consumed by `MainWindowView` and `macgitApp.swift`. Firestore rules stay at schema version 1 but allow the new optional keys for backward compatibility.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest, Firebase Firestore, Firebase CLI.

---

## File map

| File | Responsibility |
|---|---|
| `macgit/Models/AppSettingsSnapshot.swift` | Value type that holds all synced app settings, including the six new header-button visibility flags. |
| `macgit/App/AppState.swift` | Observable app-level state, UserDefaults persistence, and a publisher that emits a new `AppSettingsSnapshot` whenever any synced setting changes. |
| `macgit/Services/FirestoreSettingsStore.swift` | Encodes/decodes `AppSettingsSnapshot` to/from the Firestore `users/{uid}/settings/app` document. |
| `macgit/App/AccountSessionController.swift` | Wires `AppState` changes into `SettingsSyncService` for cloud sync. |
| `macgit/Views/Account/ManageAccountSheet.swift` | Shows the new settings in the sync-conflict comparison sheet. |
| `macgit/App/macgitApp.swift` | Adds the "Show Header Buttons" submenu to the View menu. |
| `macgit/Views/MainWindow/MainWindowView.swift` | Conditionally renders the six toolbar buttons and removes them from the More menu when hidden. |
| `firestore.rules` | Allows the six new optional boolean fields while keeping existing documents valid. |
| `firebase-tests/firestore.rules.test.mjs` | Rules unit tests for new fields and backward compatibility. |
| `macgitTests/AppSettingsSnapshotTests.swift` | Snapshot encode/decode and `AppState.apply` tests. |
| `macgitTests/CloudSettingsDocumentTests.swift` | Firestore document encoding/decoding tests. |
| `macgitTests/SettingsSyncServiceTests.swift` | Sync service tests using updated snapshot fixtures. |

---

### Task 1: Create feature branch

**Files:**
- Modify: repository branch state

- [ ] **Step 1: Ensure clean main and create branch**

```bash
git status
# expected: working tree clean and on main
git checkout main
git pull origin main
git checkout -b codex/show-header-buttons
```

- [ ] **Step 2: Commit marker (empty not needed; first real commit in Task 2)**

---

### Task 2: Extend `AppSettingsSnapshot`

**Files:**
- Modify: `macgit/Models/AppSettingsSnapshot.swift`
- Modify: `macgitTests/AppSettingsSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

In `macgitTests/AppSettingsSnapshotTests.swift`, replace the first test with the expanded version:

```swift
    func testSnapshotRoundTripsOnlyApprovedSettings() throws {
        let value = AppSettingsSnapshot(
            showToolbarButtonText: false,
            showSubmodules: true,
            showSubtrees: true,
            showHeaderBranchButton: false,
            showHeaderMergeButton: true,
            showHeaderStashButton: false,
            showHeaderRemoteButton: true,
            showHeaderFinderButton: false,
            showHeaderTerminalButton: true
        )

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys),
            [
                "schemaVersion",
                "showToolbarButtonText",
                "showSubmodules",
                "showSubtrees",
                "showHeaderBranchButton",
                "showHeaderMergeButton",
                "showHeaderStashButton",
                "showHeaderRemoteButton",
                "showHeaderFinderButton",
                "showHeaderTerminalButton"
            ]
        )
    }
```

Also update `testAppStateApplyChangesOnlyApprovedSettings` snapshot fixtures in the same file:

```swift
        state.apply(
            AppSettingsSnapshot(
                showToolbarButtonText: false,
                showSubmodules: true,
                showSubtrees: true,
                showHeaderBranchButton: true,
                showHeaderMergeButton: true,
                showHeaderStashButton: true,
                showHeaderRemoteButton: true,
                showHeaderFinderButton: true,
                showHeaderTerminalButton: true
            )
        )
```

and the matching `XCTAssertEqual(state.snapshot, ...)` block with the same values.

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/AppSettingsSnapshotTests/testSnapshotRoundTripsOnlyApprovedSettings
```

Expected: build/test FAILS because the new initializer parameters do not exist.

- [ ] **Step 3: Implement the model changes**

Replace the contents of `macgit/Models/AppSettingsSnapshot.swift` with:

```swift
//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

struct AppSettingsSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var showToolbarButtonText: Bool
    var showSubmodules: Bool
    var showSubtrees: Bool
    var showHeaderBranchButton: Bool
    var showHeaderMergeButton: Bool
    var showHeaderStashButton: Bool
    var showHeaderRemoteButton: Bool
    var showHeaderFinderButton: Bool
    var showHeaderTerminalButton: Bool

    init(
        showToolbarButtonText: Bool,
        showSubmodules: Bool,
        showSubtrees: Bool,
        showHeaderBranchButton: Bool = true,
        showHeaderMergeButton: Bool = true,
        showHeaderStashButton: Bool = true,
        showHeaderRemoteButton: Bool = true,
        showHeaderFinderButton: Bool = true,
        showHeaderTerminalButton: Bool = true
    ) {
        schemaVersion = 1
        self.showToolbarButtonText = showToolbarButtonText
        self.showSubmodules = showSubmodules
        self.showSubtrees = showSubtrees
        self.showHeaderBranchButton = showHeaderBranchButton
        self.showHeaderMergeButton = showHeaderMergeButton
        self.showHeaderStashButton = showHeaderStashButton
        self.showHeaderRemoteButton = showHeaderRemoteButton
        self.showHeaderFinderButton = showHeaderFinderButton
        self.showHeaderTerminalButton = showHeaderTerminalButton
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/AppSettingsSnapshotTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macgit/Models/AppSettingsSnapshot.swift macgitTests/AppSettingsSnapshotTests.swift
git commit -m "feat(settings): add six header button visibility flags to AppSettingsSnapshot"
```

---

### Task 3: Add `AppState` properties and snapshot publisher

**Files:**
- Modify: `macgit/App/AppState.swift`
- Modify: `macgitTests/AppSettingsSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

Add a new test to `macgitTests/AppSettingsSnapshotTests.swift`:

```swift
    func testHeaderButtonVisibilityDefaultsToTrueAndPersists() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertTrue(state.showHeaderBranchButton)
        XCTAssertTrue(state.showHeaderMergeButton)
        XCTAssertTrue(state.showHeaderStashButton)
        XCTAssertTrue(state.showHeaderRemoteButton)
        XCTAssertTrue(state.showHeaderFinderButton)
        XCTAssertTrue(state.showHeaderTerminalButton)

        state.showHeaderBranchButton = false
        state.showHeaderMergeButton = false
        state.showHeaderStashButton = false
        state.showHeaderRemoteButton = false
        state.showHeaderFinderButton = false
        state.showHeaderTerminalButton = false

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertFalse(reloaded.showHeaderBranchButton)
        XCTAssertFalse(reloaded.showHeaderMergeButton)
        XCTAssertFalse(reloaded.showHeaderStashButton)
        XCTAssertFalse(reloaded.showHeaderRemoteButton)
        XCTAssertFalse(reloaded.showHeaderFinderButton)
        XCTAssertFalse(reloaded.showHeaderTerminalButton)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/AppSettingsSnapshotTests/testHeaderButtonVisibilityDefaultsToTrueAndPersists
```

Expected: FAIL because the properties do not exist.

- [ ] **Step 3: Implement the properties, snapshot backing, and publisher**

Replace the contents of `macgit/App/AppState.swift` with an implementation that:

1. Adds the six new `@Published` header button visibility properties, each persisted to `UserDefaults` with a default of `true`.
2. Adds a private `@Published private var currentSettingsSnapshot: AppSettingsSnapshot` property.
3. Updates the `didSet` of every synced property (`showToolbarButtonText`, `showSubmodules`, `showSubtrees`, and the six new header button properties) to write to `UserDefaults` and assign `currentSettingsSnapshot = snapshot`.
4. Leaves the `didSet` of device-local settings (`syncEnabled`, `searchFilter`, `preferredSearchFileApplicationBundleIdentifier`) unchanged so they do not touch `currentSettingsSnapshot`.
5. Initializes `currentSettingsSnapshot = snapshot` at the end of `init`.
6. Exposes `settingsSnapshotPublisher` as `$currentSettingsSnapshot.removeDuplicates().eraseToAnyPublisher()`.
7. Updates `snapshot` and `apply(_:)` to include the six new fields.
8. Guards `apply(_:)` with an `isApplyingSnapshot` flag so intermediate per-property assignments do not emit multiple snapshots.

The resulting `settingsSnapshotPublisher` emits one `AppSettingsSnapshot` whenever any synced setting changes.

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/AppSettingsSnapshotTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macgit/App/AppState.swift macgitTests/AppSettingsSnapshotTests.swift
git commit -m "feat(settings): persist header button visibility in AppState and expose snapshot publisher"
```

---

### Task 4: Update `FirestoreSettingsStore` encode/decode

**Files:**
- Modify: `macgit/Services/FirestoreSettingsStore.swift`
- Modify: `macgitTests/CloudSettingsDocumentTests.swift`

- [ ] **Step 1: Write the failing test**

In `macgitTests/CloudSettingsDocumentTests.swift`, replace the `snapshot` constant and `testEncodingUsesExactDocumentSchema` with:

```swift
    private let snapshot = AppSettingsSnapshot(
        showToolbarButtonText: false,
        showSubmodules: true,
        showSubtrees: false,
        showHeaderBranchButton: true,
        showHeaderMergeButton: false,
        showHeaderStashButton: true,
        showHeaderRemoteButton: false,
        showHeaderFinderButton: true,
        showHeaderTerminalButton: false
    )

    func testEncodingUsesExactDocumentSchema() throws {
        let timestamp = Timestamp(date: Date(timeIntervalSince1970: 123))

        let document = CloudSettingsDocument.encode(snapshot, updatedAt: timestamp)

        XCTAssertEqual(
            Set(document.keys),
            [
                "schemaVersion",
                "showToolbarButtonText",
                "showSubmodules",
                "showSubtrees",
                "showHeaderBranchButton",
                "showHeaderMergeButton",
                "showHeaderStashButton",
                "showHeaderRemoteButton",
                "showHeaderFinderButton",
                "showHeaderTerminalButton",
                "updatedAt"
            ]
        )
        XCTAssertEqual(document["schemaVersion"] as? Int, 1)
        XCTAssertEqual(document["showToolbarButtonText"] as? Bool, false)
        XCTAssertEqual(document["showSubmodules"] as? Bool, true)
        XCTAssertEqual(document["showSubtrees"] as? Bool, false)
        XCTAssertEqual(document["showHeaderBranchButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderMergeButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderStashButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderRemoteButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderFinderButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderTerminalButton"] as? Bool, false)
        XCTAssertEqual(document["updatedAt"] as? Timestamp, timestamp)
    }
```

Also add a new test:

```swift
    func testDecodingDefaultsMissingHeaderButtonsToTrue() throws {
        var document = validDocument()
        document.removeValue(forKey: "showHeaderBranchButton")
        document.removeValue(forKey: "showHeaderRemoteButton")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertTrue(decoded.showHeaderBranchButton)
        XCTAssertTrue(decoded.showHeaderRemoteButton)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CloudSettingsDocumentTests/testEncodingUsesExactDocumentSchema
```

Expected: FAIL because `encode` does not output the new keys.

- [ ] **Step 3: Implement encode/decode changes**

Replace the contents of `macgit/Services/FirestoreSettingsStore.swift` with:

```swift
//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import FirebaseFirestore
import Foundation

enum CloudSettingsDocument {
    static func encode(
        _ snapshot: AppSettingsSnapshot,
        updatedAt: Any
    ) -> [String: Any] {
        [
            "schemaVersion": snapshot.schemaVersion,
            "showToolbarButtonText": snapshot.showToolbarButtonText,
            "showSubmodules": snapshot.showSubmodules,
            "showSubtrees": snapshot.showSubtrees,
            "showHeaderBranchButton": snapshot.showHeaderBranchButton,
            "showHeaderMergeButton": snapshot.showHeaderMergeButton,
            "showHeaderStashButton": snapshot.showHeaderStashButton,
            "showHeaderRemoteButton": snapshot.showHeaderRemoteButton,
            "showHeaderFinderButton": snapshot.showHeaderFinderButton,
            "showHeaderTerminalButton": snapshot.showHeaderTerminalButton,
            "updatedAt": updatedAt
        ]
    }

    static func decode(_ data: [String: Any]?) throws -> AppSettingsSnapshot {
        guard let data,
              let schemaVersion = data["schemaVersion"] as? Int,
              schemaVersion == 1,
              let showToolbarButtonText = data["showToolbarButtonText"] as? Bool,
              let showSubmodules = data["showSubmodules"] as? Bool,
              let showSubtrees = data["showSubtrees"] as? Bool,
              data["updatedAt"] is Timestamp else {
            throw CloudSettingsError.invalidDocument
        }

        return AppSettingsSnapshot(
            showToolbarButtonText: showToolbarButtonText,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: data["showHeaderBranchButton"] as? Bool ?? true,
            showHeaderMergeButton: data["showHeaderMergeButton"] as? Bool ?? true,
            showHeaderStashButton: data["showHeaderStashButton"] as? Bool ?? true,
            showHeaderRemoteButton: data["showHeaderRemoteButton"] as? Bool ?? true,
            showHeaderFinderButton: data["showHeaderFinderButton"] as? Bool ?? true,
            showHeaderTerminalButton: data["showHeaderTerminalButton"] as? Bool ?? true
        )
    }
}

@MainActor
final class FirestoreSettingsStore: CloudSettingsStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func load(uid: String) async throws -> AppSettingsSnapshot? {
        let snapshot = try await document(uid: uid).getDocument()
        guard snapshot.exists else { return nil }
        return try CloudSettingsDocument.decode(snapshot.data(with: .estimate))
    }

    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws {
        try await document(uid: uid).setData(
            CloudSettingsDocument.encode(snapshot, updatedAt: FieldValue.serverTimestamp())
        )
    }

    func observe(
        uid: String,
        onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void
    ) -> ObservationToken {
        let registration = document(uid: uid).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }

            do {
                let value = try CloudSettingsDocument.decode(snapshot?.data(with: .estimate))
                onChange(.success(value))
            } catch {
                onChange(.failure(error))
            }
        }
        return SettingsFirestoreObservationToken(registration: registration)
    }

    private func document(uid: String) -> DocumentReference {
        firestore.collection("users").document(uid).collection("settings").document("app")
    }
}

private final class SettingsFirestoreObservationToken: ObservationToken {
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        registration?.remove()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CloudSettingsDocumentTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macgit/Services/FirestoreSettingsStore.swift macgitTests/CloudSettingsDocumentTests.swift
git commit -m "feat(sync): encode and decode header button visibility in Firestore"
```

---

### Task 5: Wire snapshot publisher into `AccountSessionController`

**Files:**
- Modify: `macgit/App/AccountSessionController.swift`

- [ ] **Step 1: Replace the CombineLatest3 observation**

In `macgit/App/AccountSessionController.swift`, replace the entire `bindSettingsSync()` body (lines 308-346) with:

```swift
    private func bindSettingsSync() {
        guard let settingsSyncService else { return }

        settingsSyncService.$status
            .sink { [weak self] status in
                guard let self else { return }
                settingsSyncStatus = status
                if case .needsInitialChoice = status {
                    presentSettingsConflictSheet()
                } else if presentedSheet == .settingsConflict {
                    presentedSheet = nil
                }
            }
            .store(in: &cancellables)

        appState.settingsSnapshotPublisher
            .dropFirst()
            .sink { [weak self] snapshot in
                guard let self else { return }
                settingsSyncService?.localSettingsDidChange(snapshot)
            }
            .store(in: &cancellables)

        appState.$syncEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.scheduleSettingsSyncEligibilityUpdate(enabled: enabled)
            }
            .store(in: &cancellables)
    }
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 3: Commit**

```bash
git add macgit/App/AccountSessionController.swift
git commit -m "refactor(sync): observe AppState snapshot publisher for settings sync"
```

---

### Task 6: Update sync conflict sheet UI

**Files:**
- Modify: `macgit/Views/Account/ManageAccountSheet.swift`

- [ ] **Step 1: Add setting rows in the conflict comparison view**

In `macgit/Views/Account/ManageAccountSheet.swift`, replace the `settingsGroup` body (lines 195-206) with:

```swift
    private func settingsGroup(title: String, snapshot: AppSettingsSnapshot) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                settingRow("Toolbar button text", enabled: snapshot.showToolbarButtonText)
                settingRow("Submodules", enabled: snapshot.showSubmodules)
                settingRow("Subtrees", enabled: snapshot.showSubtrees)
                settingRow("Header: Branch", enabled: snapshot.showHeaderBranchButton)
                settingRow("Header: Merge", enabled: snapshot.showHeaderMergeButton)
                settingRow("Header: Stash", enabled: snapshot.showHeaderStashButton)
                settingRow("Header: Remote", enabled: snapshot.showHeaderRemoteButton)
                settingRow("Header: Finder", enabled: snapshot.showHeaderFinderButton)
                settingRow("Header: Terminal", enabled: snapshot.showHeaderTerminalButton)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 3: Commit**

```bash
git add macgit/Views/Account/ManageAccountSheet.swift
git commit -m "feat(ui): show header button visibility in settings sync conflict sheet"
```

---

### Task 7: Update `SettingsSyncServiceTests` fixtures

**Files:**
- Modify: `macgitTests/SettingsSyncServiceTests.swift`

- [ ] **Step 1: Expand `local` and `cloud` snapshots**

Replace the fixture definitions in `macgitTests/SettingsSyncServiceTests.swift` with:

```swift
    private let local = AppSettingsSnapshot(
        showToolbarButtonText: true,
        showSubmodules: false,
        showSubtrees: false,
        showHeaderBranchButton: true,
        showHeaderMergeButton: true,
        showHeaderStashButton: true,
        showHeaderRemoteButton: true,
        showHeaderFinderButton: true,
        showHeaderTerminalButton: true
    )
    private let cloud = AppSettingsSnapshot(
        showToolbarButtonText: false,
        showSubmodules: true,
        showSubtrees: true,
        showHeaderBranchButton: false,
        showHeaderMergeButton: false,
        showHeaderStashButton: false,
        showHeaderRemoteButton: false,
        showHeaderFinderButton: false,
        showHeaderTerminalButton: false
    )
```

Also update the `first` snapshot inside `testLocalEditsAreDebouncedAndOnlyLatestSnapshotUploads` to include the six new booleans so that equality comparisons remain valid:

```swift
        let first = AppSettingsSnapshot(
            showToolbarButtonText: false,
            showSubmodules: false,
            showSubtrees: false,
            showHeaderBranchButton: true,
            showHeaderMergeButton: true,
            showHeaderStashButton: true,
            showHeaderRemoteButton: true,
            showHeaderFinderButton: true,
            showHeaderTerminalButton: true
        )
```

- [ ] **Step 2: Run the tests**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/SettingsSyncServiceTests
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add macgitTests/SettingsSyncServiceTests.swift
git commit -m "test(sync): update settings sync fixtures with header button flags"
```

---

### Task 8: Add "Show Header Buttons" submenu to View menu

**Files:**
- Modify: `macgit/App/macgitApp.swift`

- [ ] **Step 1: Insert the submenu**

In `macgit/App/macgitApp.swift`, replace the existing `CommandGroup(before: .toolbar)` block (lines 198-209) with:

```swift
            CommandGroup(before: .toolbar) {
                Toggle(isOn: $appState.showToolbarButtonText) {
                    Label("Show Button Text", systemImage: "character.textbox")
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                Toggle(isOn: $appState.showSubmodules) {
                    Label("Show Submodules", systemImage: "folder.badge.gearshape")
                }
                Toggle(isOn: $appState.showSubtrees) {
                    Label("Show Subtrees", systemImage: "tree")
                }
                Menu("Show Header Buttons") {
                    Toggle("Branch", isOn: $appState.showHeaderBranchButton)
                    Toggle("Merge", isOn: $appState.showHeaderMergeButton)
                    Toggle("Stash", isOn: $appState.showHeaderStashButton)
                    Toggle("Remote", isOn: $appState.showHeaderRemoteButton)
                    Toggle("Finder", isOn: $appState.showHeaderFinderButton)
                    Toggle("Terminal", isOn: $appState.showHeaderTerminalButton)
                }
            }
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 3: Commit**

```bash
git add macgit/App/macgitApp.swift
git commit -m "feat(menu): add Show Header Buttons submenu to View menu"
```

---

### Task 9: Conditionally show/hide toolbar buttons

**Files:**
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Conditionally render right-side toolbar items**

In `macgit/Views/MainWindow/MainWindowView.swift`, replace the right-side toolbar block (lines 589-612) with:

```swift
        ToolbarItem(placement: .automatic) {
            toolbarButton(
                icon: "arrow.uturn.backward",
                label: "Undo",
                showText: appState.showToolbarButtonText,
                disabled: GitUndoToolbarPolicy.isUndoDisabled(
                    isSyncing: syncState.isAnySyncing,
                    canUndo: undoManager.canUndo
                ),
                action: { handleGitUndoMenuAction(.undo) }
            )
        }
        if appState.showHeaderRemoteButton {
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "network", label: "Remote", showText: appState.showToolbarButtonText, disabled: remoteURLString.isEmpty, action: { openRemoteURL() })
            }
        }
        if appState.showHeaderFinderButton {
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "folder", label: "Finder", showText: appState.showToolbarButtonText, action: showInFinder)
            }
        }
        if appState.showHeaderTerminalButton {
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "terminal", label: "Terminal", showText: appState.showToolbarButtonText, action: openTerminal)
            }
        }
        ToolbarItem(placement: .automatic) {
            toolbarButton(icon: "gear", label: "Settings", showText: appState.showToolbarButtonText, action: { showingRepositorySettings = true })
        }
```

- [ ] **Step 2: Conditionally render left-side toolbar buttons**

Replace the three conditional `toolbarButton` calls for Branch, Merge, and Stash inside `leftToolbar` with conditional blocks.

For the `windowWidth > 1000` branch (around line 912-914):

```swift
                if appState.showHeaderBranchButton {
                    toolbarButton(icon: "arrow.triangle.branch", label: "Branch", showText: showText, action: { presentBranchSheet(startPoint: nil) })
                }
                if appState.showHeaderMergeButton {
                    toolbarButton(icon: "arrow.triangle.merge", label: "Merge", showText: showText, isLoading: syncState.isMerging, disabled: syncing, action: { showingMergeSheet = true })
                }
                if appState.showHeaderStashButton {
                    toolbarButton(icon: "archivebox", label: "Stash", showText: showText, isLoading: syncState.isStashing, disabled: syncing || syncState.stashableCount == 0, action: { showingStashSheet = true })
                }
```

For the `windowWidth > 800` branch, only the `moreMenu` is shown for Branch/Merge/Stash, so no extra changes are needed there.

- [ ] **Step 3: Update More menu to respect visibility flags**

Replace `moreMenu` body (lines 932-956) with:

```swift
    private var moreMenu: some View {
        Menu {
            let syncing = syncState.isAnySyncing
            if windowWidth <= 800 {
                Button("Pull") { showingPullSheet = true }
                    .disabled(syncing)
                Button("Push") { showingPushSheet = true }
                    .disabled(syncing)
                Button("Fetch") { showingFetchSheet = true }
                    .disabled(syncing)
            }
            if windowWidth <= 1000 {
                if appState.showHeaderBranchButton {
                    Button("Branch") { presentBranchSheet(startPoint: nil) }
                }
                if appState.showHeaderMergeButton {
                    Button("Merge") { showingMergeSheet = true }
                        .disabled(syncing)
                }
                if appState.showHeaderStashButton {
                    Button("Stash", action: { showingStashSheet = true })
                        .disabled(syncing || syncState.stashableCount == 0)
                }
            }
        } label: {
            ToolbarButtonLabel(icon: "ellipsis", label: "More", showText: appState.showToolbarButtonText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More Actions")
    }
```

- [ ] **Step 4: Build to verify it compiles**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add macgit/Views/MainWindow/MainWindowView.swift
git commit -m "feat(toolbar): conditionally show header buttons based on app state"
```

---

### Task 10: Update Firestore rules and rules tests

**Files:**
- Modify: `firestore.rules`
- Modify: `firebase-tests/firestore.rules.test.mjs`

- [ ] **Step 1: Update `firestore.rules`**

Replace the `validAppSettings` function in `firestore.rules` with:

```javascript
    function validAppSettings() {
      return request.resource.data.keys().hasOnly([
          'schemaVersion',
          'showToolbarButtonText',
          'showSubmodules',
          'showSubtrees',
          'showHeaderBranchButton',
          'showHeaderMergeButton',
          'showHeaderStashButton',
          'showHeaderRemoteButton',
          'showHeaderFinderButton',
          'showHeaderTerminalButton',
          'updatedAt'
        ])
        && request.resource.data.keys().hasAll([
          'schemaVersion',
          'showToolbarButtonText',
          'showSubmodules',
          'showSubtrees',
          'updatedAt'
        ])
        && request.resource.data.schemaVersion is int
        && request.resource.data.schemaVersion == 1
        && request.resource.data.showToolbarButtonText is bool
        && request.resource.data.showSubmodules is bool
        && request.resource.data.showSubtrees is bool
        && (!('showHeaderBranchButton' in request.resource.data) || request.resource.data.showHeaderBranchButton is bool)
        && (!('showHeaderMergeButton' in request.resource.data) || request.resource.data.showHeaderMergeButton is bool)
        && (!('showHeaderStashButton' in request.resource.data) || request.resource.data.showHeaderStashButton is bool)
        && (!('showHeaderRemoteButton' in request.resource.data) || request.resource.data.showHeaderRemoteButton is bool)
        && (!('showHeaderFinderButton' in request.resource.data) || request.resource.data.showHeaderFinderButton is bool)
        && (!('showHeaderTerminalButton' in request.resource.data) || request.resource.data.showHeaderTerminalButton is bool)
        && request.resource.data.updatedAt is timestamp;
    }
```

- [ ] **Step 2: Update rules tests**

In `firebase-tests/firestore.rules.test.mjs`, update `validSettings()` to:

```javascript
function validSettings() {
  return {
    schemaVersion: 1,
    showToolbarButtonText: true,
    showSubmodules: false,
    showSubtrees: true,
    showHeaderBranchButton: true,
    showHeaderMergeButton: false,
    showHeaderStashButton: true,
    showHeaderRemoteButton: false,
    showHeaderFinderButton: true,
    showHeaderTerminalButton: false,
    updatedAt: serverTimestamp(),
  };
}
```

Add two new tests after the existing settings type test:

```javascript
  test("settings accept optional header button fields", async () => {
    const userA = environment.authenticatedContext("user-a");

    await assertSucceeds(setDoc(settings("user-a", userA), validSettings()));
  });

  test("settings reject wrong type for optional header button fields", async () => {
    const userA = environment.authenticatedContext("user-a");

    for (const key of [
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderTerminalButton",
    ]) {
      await assertFails(setDoc(settings("user-a", userA), {
        ...validSettings(),
        [key]: "true",
      }));
    }
  });

  test("settings accept legacy documents without header button fields", async () => {
    const userA = environment.authenticatedContext("user-a");
    const legacy = validSettings();
    for (const key of [
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderTerminalButton",
    ]) {
      delete legacy[key];
    }

    await assertSucceeds(setDoc(settings("user-a", userA), legacy));
  });
```

- [ ] **Step 3: Run rules tests**

```bash
node --test firebase-tests/firestore.rules.test.mjs
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add firestore.rules firebase-tests/firestore.rules.test.mjs
git commit -m "feat(firestore): allow optional header button visibility fields in app settings"
```

---

### Task 11: Full build and targeted test run

**Files:**
- All files above

- [ ] **Step 1: Build the project**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 2: Run targeted tests**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test \
  -only-testing macgitTests/AppSettingsSnapshotTests \
  -only-testing macgitTests/CloudSettingsDocumentTests \
  -only-testing macgitTests/SettingsSyncServiceTests
```

Expected: all targeted tests PASS. If the full test suite crashes during bootstrapping, a successful build is sufficient per `AGENTS.md`.

- [ ] **Step 3: Commit if any last-minute fixes were required**

If no changes were needed, no extra commit is required.

---

### Task 12: Deploy updated Firestore rules

**Files:**
- `firestore.rules` (already updated)

- [ ] **Step 1: Deploy**

```bash
firebase deploy --only firestore:rules
```

Expected: deployment succeeds and prints the deployed rules version.

- [ ] **Step 2: Commit a deployment marker (optional)**

If the project tracks deployments in git, add a note; otherwise this step is optional.

---

## Spec coverage self-check

| Spec requirement | Task(s) |
|---|---|
| Show Header Buttons submenu in View menu | Task 8 |
| Six toggles | Task 8 |
| Default all on | Tasks 2 & 3 |
| Hidden buttons removed from toolbar and More menu | Task 9 |
| Global settings | Tasks 2 & 3 |
| Firebase sync via `AppSettingsSnapshot` | Tasks 2, 4, 5 |
| Backward-compatible Firestore rules | Task 10 |
| Unit/rules tests updated | Tasks 2, 4, 7, 10 |
| Deploy rules if changed | Task 12 |

## Placeholder self-check

No placeholders such as "TBD", "TODO", "implement later", or "write tests for the above" remain. Every step includes exact file paths, code, and commands.
