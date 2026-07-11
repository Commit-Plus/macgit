# Repository Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a repo-specific settings modal that opens from the main window toolbar, persists Git behavior preferences per repository, and provides quick actions for opening `.gitignore` and `.git/config`.

**Architecture:** Add a dedicated `RepoSettings` model and `RepoSettingsStore` for per-repo persistence, a small draft/view-model layer to keep the sheet logic testable, and a `RepositorySettingsSheetView` for the top-tab modal UI. Integrate the saved settings into `MainWindowView`, `PullSheetView`, and `SyncState` so the settings influence real app behavior instead of acting as dead form data.

**Tech Stack:** SwiftUI, Foundation, Swift Concurrency, UserDefaults, XCTest, NSWorkspace

---

## File Structure

| File | Responsibility |
|------|----------------|
| `macgit/Models/RepoSettings.swift` | `PullStrategy`, `RepoSettings`, default values, and small runtime helper methods for resolving saved settings into live behavior |
| `macgit/Services/RepoSettingsStore.swift` | Persist and load `RepoSettings` keyed by repository path using `UserDefaults` |
| `macgit/ViewModels/RepositorySettingsDraft.swift` | Testable sheet state for top tabs, hybrid branch input, and conversion between UI state and `RepoSettings` |
| `macgit/Services/RepositorySettingsFileService.swift` | Prepare `.gitignore` and `.git/config` paths and create `.gitignore` on demand |
| `macgit/Views/Common/RepositorySettingsSheetView.swift` | Repo settings modal UI with top tabs and save/cancel behavior |
| `macgit/Views/Common/PullSheetView.swift` | Accept saved defaults for remote, branch, and pull strategy |
| `macgit/Services/SyncState.swift` | Respect `autoFetchEnabled`, `refreshOnAppActive`, and pull strategy defaults during runtime behavior |
| `macgit/Views/MainWindow/MainWindowView.swift` | Present settings sheet, load repo settings, and apply settings to toolbar actions and confirmation flows |
| `macgitTests/RepoSettingsStoreTests.swift` | Persistence and default-value coverage |
| `macgitTests/RepositorySettingsDraftTests.swift` | Hybrid branch-entry and normalization coverage |
| `macgitTests/RepositorySettingsFileServiceTests.swift` | `.gitignore` creation and `.git/config` path behavior |

---

### Task 1: Add Repo Settings Model And Persistence

**Files:**
- Create: `macgit/Models/RepoSettings.swift`
- Create: `macgit/Services/RepoSettingsStore.swift`
- Create: `macgitTests/RepoSettingsStoreTests.swift`

- [ ] **Step 1: Write the failing persistence tests**

```swift
import XCTest
@testable import macgit

final class RepoSettingsStoreTests: XCTestCase {
    func testRepoSettingsDecodesMissingFieldsWithDefaults() throws {
        let data = #"{"defaultRemoteName":"origin","defaultPullBranch":"main"}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RepoSettings.self, from: data)

        XCTAssertEqual(decoded.defaultRemoteName, "origin")
        XCTAssertEqual(decoded.defaultPullBranch, "main")
        XCTAssertEqual(decoded.pullStrategy, .merge)
        XCTAssertFalse(decoded.autoFetchEnabled)
        XCTAssertTrue(decoded.refreshOnAppActive)
        XCTAssertTrue(decoded.confirmDetachedHeadCheckout)
        XCTAssertTrue(decoded.confirmDestructiveStashActions)
    }

    func testRepoSettingsStorePersistsSettingsPerRepositoryPath() {
        let defaultsKey = "test.repo-settings.\(UUID().uuidString)"
        let store = RepoSettingsStore(userDefaults: UserDefaults.standard, key: defaultsKey)
        let repoA = "/tmp/repo-a-\(UUID().uuidString)"
        let repoB = "/tmp/repo-b-\(UUID().uuidString)"

        var repoASettings = RepoSettings.defaults(currentBranch: "main", remotes: ["origin"])
        repoASettings.pullStrategy = .rebase
        repoASettings.autoFetchEnabled = true
        store.update(for: repoA, settings: repoASettings)

        let loadedA = store.settings(for: repoA, currentBranch: "main", remotes: ["origin"])
        let loadedB = store.settings(for: repoB, currentBranch: "develop", remotes: ["upstream"])

        XCTAssertEqual(loadedA.pullStrategy, .rebase)
        XCTAssertTrue(loadedA.autoFetchEnabled)
        XCTAssertEqual(loadedB.defaultRemoteName, "upstream")
        XCTAssertEqual(loadedB.defaultPullBranch, "develop")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepoSettingsStoreTests`
Expected: FAIL with missing `RepoSettings` and `RepoSettingsStore` symbols.

- [ ] **Step 3: Implement the model and store**

`macgit/Models/RepoSettings.swift`

```swift
import Foundation

enum PullStrategy: String, Codable, CaseIterable {
    case merge
    case rebase
}

struct RepoSettings: Codable, Equatable {
    var defaultRemoteName: String?
    var defaultPullBranch: String
    var pullStrategy: PullStrategy
    var autoFetchEnabled: Bool
    var refreshOnAppActive: Bool
    var confirmDetachedHeadCheckout: Bool
    var confirmDestructiveStashActions: Bool

    static func defaults(currentBranch: String?, remotes: [String]) -> RepoSettings {
        RepoSettings(
            defaultRemoteName: remotes.first,
            defaultPullBranch: currentBranch ?? "",
            pullStrategy: .merge,
            autoFetchEnabled: false,
            refreshOnAppActive: true,
            confirmDetachedHeadCheckout: true,
            confirmDestructiveStashActions: true
        )
    }

    init(
        defaultRemoteName: String?,
        defaultPullBranch: String,
        pullStrategy: PullStrategy,
        autoFetchEnabled: Bool,
        refreshOnAppActive: Bool,
        confirmDetachedHeadCheckout: Bool,
        confirmDestructiveStashActions: Bool
    ) {
        self.defaultRemoteName = defaultRemoteName
        self.defaultPullBranch = defaultPullBranch
        self.pullStrategy = pullStrategy
        self.autoFetchEnabled = autoFetchEnabled
        self.refreshOnAppActive = refreshOnAppActive
        self.confirmDetachedHeadCheckout = confirmDetachedHeadCheckout
        self.confirmDestructiveStashActions = confirmDestructiveStashActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultRemoteName = try container.decodeIfPresent(String.self, forKey: .defaultRemoteName)
        defaultPullBranch = try container.decodeIfPresent(String.self, forKey: .defaultPullBranch) ?? ""
        pullStrategy = try container.decodeIfPresent(PullStrategy.self, forKey: .pullStrategy) ?? .merge
        autoFetchEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFetchEnabled) ?? false
        refreshOnAppActive = try container.decodeIfPresent(Bool.self, forKey: .refreshOnAppActive) ?? true
        confirmDetachedHeadCheckout = try container.decodeIfPresent(Bool.self, forKey: .confirmDetachedHeadCheckout) ?? true
        confirmDestructiveStashActions = try container.decodeIfPresent(Bool.self, forKey: .confirmDestructiveStashActions) ?? true
    }
}
```

`macgit/Services/RepoSettingsStore.swift`

```swift
import Foundation

final class RepoSettingsStore {
    static let shared = RepoSettingsStore()

    private let userDefaults: UserDefaults
    private let key: String
    private var cached: [String: RepoSettings] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "dev.thanhtran.commitplus.repoSettings"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        load()
    }

    func settings(for repositoryPath: String, currentBranch: String?, remotes: [String]) -> RepoSettings {
        cached[repositoryPath] ?? .defaults(currentBranch: currentBranch, remotes: remotes)
    }

    func update(for repositoryPath: String, settings: RepoSettings) {
        cached[repositoryPath] = settings
        save()
    }

    private func load() {
        guard
            let data = userDefaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: RepoSettings].self, from: data)
        else {
            return
        }
        cached = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        userDefaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Run the persistence tests again**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepoSettingsStoreTests`
Expected: PASS with 2 passing tests in `RepoSettingsStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add macgit/Models/RepoSettings.swift macgit/Services/RepoSettingsStore.swift macgitTests/RepoSettingsStoreTests.swift
git commit -m "feat: add repo settings persistence"
```

---

### Task 2: Add Testable Draft State For The Settings Sheet

**Files:**
- Create: `macgit/ViewModels/RepositorySettingsDraft.swift`
- Create: `macgitTests/RepositorySettingsDraftTests.swift`

- [ ] **Step 1: Write the failing draft-state tests**

```swift
import XCTest
@testable import macgit

final class RepositorySettingsDraftTests: XCTestCase {
    func testDraftPrefersSavedBranchWhenItExistsInDetectedBranches() {
        let settings = RepoSettings(
            defaultRemoteName: "origin",
            defaultPullBranch: "release",
            pullStrategy: .merge,
            autoFetchEnabled: false,
            refreshOnAppActive: true,
            confirmDetachedHeadCheckout: true,
            confirmDestructiveStashActions: true
        )

        let draft = RepositorySettingsDraft(
            settings: settings,
            remotes: ["origin", "upstream"],
            branches: ["main", "release"],
            currentBranch: "main"
        )

        XCTAssertEqual(draft.selectedRemoteName, "origin")
        XCTAssertEqual(draft.selectedBranchMode, .detected)
        XCTAssertEqual(draft.selectedDetectedBranch, "release")
        XCTAssertEqual(draft.manualBranchName, "")
    }

    func testDraftFallsBackToManualBranchEntryWhenSavedBranchIsCustom() {
        let draft = RepositorySettingsDraft(
            settings: RepoSettings(
                defaultRemoteName: "origin",
                defaultPullBranch: "release/hotfix",
                pullStrategy: .rebase,
                autoFetchEnabled: true,
                refreshOnAppActive: false,
                confirmDetachedHeadCheckout: false,
                confirmDestructiveStashActions: false
            ),
            remotes: ["origin"],
            branches: ["main", "develop"],
            currentBranch: "main"
        )

        XCTAssertEqual(draft.selectedBranchMode, .manual)
        XCTAssertEqual(draft.manualBranchName, "release/hotfix")
        XCTAssertEqual(draft.resolvedSettings.defaultPullBranch, "release/hotfix")
        XCTAssertEqual(draft.resolvedSettings.pullStrategy, .rebase)
    }

    func testDraftTrimsManualBranchNameOnSave() {
        var draft = RepositorySettingsDraft(
            settings: RepoSettings.defaults(currentBranch: "main", remotes: ["origin"]),
            remotes: ["origin"],
            branches: ["main"],
            currentBranch: "main"
        )
        draft.selectedBranchMode = .manual
        draft.manualBranchName = "  release/v2  "

        XCTAssertEqual(draft.resolvedSettings.defaultPullBranch, "release/v2")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepositorySettingsDraftTests`
Expected: FAIL with missing `RepositorySettingsDraft` and `SelectedBranchMode` symbols.

- [ ] **Step 3: Implement the draft state**

```swift
import Foundation

enum SelectedBranchMode: String, Equatable {
    case detected
    case manual
}

struct RepositorySettingsDraft: Equatable {
    var selectedRemoteName: String
    var selectedBranchMode: SelectedBranchMode
    var selectedDetectedBranch: String
    var manualBranchName: String
    var pullStrategy: PullStrategy
    var autoFetchEnabled: Bool
    var refreshOnAppActive: Bool
    var confirmDetachedHeadCheckout: Bool
    var confirmDestructiveStashActions: Bool

    let remotes: [String]
    let branches: [String]

    init(settings: RepoSettings, remotes: [String], branches: [String], currentBranch: String?) {
        self.remotes = remotes
        self.branches = branches
        if let savedRemote = settings.defaultRemoteName, remotes.contains(savedRemote) {
            selectedRemoteName = savedRemote
        } else {
            selectedRemoteName = remotes.first ?? settings.defaultRemoteName ?? ""
        }
        pullStrategy = settings.pullStrategy
        autoFetchEnabled = settings.autoFetchEnabled
        refreshOnAppActive = settings.refreshOnAppActive
        confirmDetachedHeadCheckout = settings.confirmDetachedHeadCheckout
        confirmDestructiveStashActions = settings.confirmDestructiveStashActions

        if branches.contains(settings.defaultPullBranch) {
            selectedBranchMode = .detected
            selectedDetectedBranch = settings.defaultPullBranch
            manualBranchName = ""
        } else {
            selectedBranchMode = .manual
            selectedDetectedBranch = currentBranch ?? branches.first ?? ""
            manualBranchName = settings.defaultPullBranch
        }
    }

    var resolvedSettings: RepoSettings {
        let branch = selectedBranchMode == .detected
            ? selectedDetectedBranch
            : manualBranchName.trimmingCharacters(in: .whitespacesAndNewlines)

        return RepoSettings(
            defaultRemoteName: selectedRemoteName.isEmpty ? nil : selectedRemoteName,
            defaultPullBranch: branch,
            pullStrategy: pullStrategy,
            autoFetchEnabled: autoFetchEnabled,
            refreshOnAppActive: refreshOnAppActive,
            confirmDetachedHeadCheckout: confirmDetachedHeadCheckout,
            confirmDestructiveStashActions: confirmDestructiveStashActions
        )
    }
}
```

- [ ] **Step 4: Run the draft tests again**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepositorySettingsDraftTests`
Expected: PASS with 3 passing tests in `RepositorySettingsDraftTests`.

- [ ] **Step 5: Commit**

```bash
git add macgit/ViewModels/RepositorySettingsDraft.swift macgitTests/RepositorySettingsDraftTests.swift
git commit -m "feat: add repo settings draft state"
```

---

### Task 3: Add File-Action Support For `.gitignore` And `.git/config`

**Files:**
- Create: `macgit/Services/RepositorySettingsFileService.swift`
- Create: `macgitTests/RepositorySettingsFileServiceTests.swift`

- [ ] **Step 1: Write the failing file-service tests**

```swift
import XCTest
@testable import macgit

final class RepositorySettingsFileServiceTests: XCTestCase {
    func testPrepareGitIgnoreCreatesFileWhenMissing() throws {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-settings-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        let service = RepositorySettingsFileService(fileManager: .default)
        let gitIgnoreURL = try service.prepareGitIgnore(in: repoURL)

        XCTAssertEqual(gitIgnoreURL.lastPathComponent, ".gitignore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitIgnoreURL.path))
    }

    func testGitConfigReturnsNilWhenConfigDoesNotExist() throws {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-settings-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let service = RepositorySettingsFileService(fileManager: .default)

        XCTAssertNil(service.gitConfigURL(in: repoURL))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepositorySettingsFileServiceTests`
Expected: FAIL with missing `RepositorySettingsFileService`.

- [ ] **Step 3: Implement the file service**

```swift
import Foundation

struct RepositorySettingsFileService {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareGitIgnore(in repositoryURL: URL) throws -> URL {
        let gitIgnoreURL = repositoryURL.appendingPathComponent(".gitignore")
        if !fileManager.fileExists(atPath: gitIgnoreURL.path) {
            fileManager.createFile(atPath: gitIgnoreURL.path, contents: Data())
        }
        return gitIgnoreURL
    }

    func gitConfigURL(in repositoryURL: URL) -> URL? {
        let configURL = repositoryURL
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("config")
        return fileManager.fileExists(atPath: configURL.path) ? configURL : nil
    }
}
```

- [ ] **Step 4: Run the file-service tests again**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepositorySettingsFileServiceTests`
Expected: PASS with 2 passing tests in `RepositorySettingsFileServiceTests`.

- [ ] **Step 5: Commit**

```bash
git add macgit/Services/RepositorySettingsFileService.swift macgitTests/RepositorySettingsFileServiceTests.swift
git commit -m "feat: add repo settings file actions"
```

---

### Task 4: Build The Repository Settings Sheet UI

**Files:**
- Create: `macgit/Views/Common/RepositorySettingsSheetView.swift`
- Modify: `macgit/ViewModels/RepositorySettingsDraft.swift`

- [ ] **Step 1: Build the sheet UI**

`macgit/Views/Common/RepositorySettingsSheetView.swift`

```swift
import SwiftUI

private enum RepositorySettingsTab: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case pullFetch = "Pull & Fetch"
    case safetyFiles = "Safety & Files"

    var id: String { rawValue }
}

struct RepositorySettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let initialSettings: RepoSettings
    let onSave: (RepoSettings) -> Void
    let onOpenGitIgnore: () -> Void
    let onOpenGitConfig: () -> Void
    let onOpenRemoteURL: (String) -> Void

    @State private var selectedTab: RepositorySettingsTab = .remote
    @State private var remotes: [String] = []
    @State private var branches: [String] = []
    @State private var currentBranch: String?
    @State private var draft: RepositorySettingsDraft?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(RepositorySettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(24)

            Group {
                if let draft {
                    switch selectedTab {
                    case .remote:
                        remoteTab(draft: draft)
                    case .pullFetch:
                        pullFetchTab(draft: draft)
                    case .safetyFiles:
                        safetyFilesTab(draft: draft)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    guard let draft else { return }
                    onSave(draft.resolvedSettings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
            }
            .padding(24)
        }
        .frame(minWidth: 560, idealWidth: 560, maxWidth: 560)
        .frame(minHeight: 420, idealHeight: 440)
        .task { await loadOptions() }
    }
}
```

- [ ] **Step 2: Fill in the per-tab sections and hybrid branch controls**

Add these view helpers inside `RepositorySettingsSheetView`:

```swift
@ViewBuilder
private func remoteTab(draft: RepositorySettingsDraft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        Picker("Default Remote", selection: binding(\.selectedRemoteName)) {
            ForEach(remotes, id: \.self) { remote in
                Text(remote).tag(remote)
            }
        }

        Picker("Default Pull Branch Mode", selection: binding(\.selectedBranchMode)) {
            Text("Detected Branch").tag(SelectedBranchMode.detected)
            Text("Manual Entry").tag(SelectedBranchMode.manual)
        }

        if draft.selectedBranchMode == .detected {
            Picker("Default Pull Branch", selection: binding(\.selectedDetectedBranch)) {
                ForEach(branches, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
        } else {
            TextField("release/hotfix", text: binding(\.manualBranchName))
        }

        Button("Open Remote URL") {
            onOpenRemoteURL(draft.selectedRemoteName)
        }
        .disabled(draft.selectedRemoteName.isEmpty)
    }
}

@ViewBuilder
private func pullFetchTab(draft: RepositorySettingsDraft) -> some View {
    Form {
        Picker("Pull Strategy", selection: binding(\.pullStrategy)) {
            Text("Merge").tag(PullStrategy.merge)
            Text("Rebase").tag(PullStrategy.rebase)
        }
        Toggle("Auto Fetch", isOn: binding(\.autoFetchEnabled))
        Toggle("Refresh On App Active", isOn: binding(\.refreshOnAppActive))
    }
}

@ViewBuilder
private func safetyFilesTab(draft: RepositorySettingsDraft) -> some View {
    Form {
        Toggle("Confirm Detached HEAD Checkout", isOn: binding(\.confirmDetachedHeadCheckout))
        Toggle("Confirm Destructive Stash Actions", isOn: binding(\.confirmDestructiveStashActions))

        HStack {
            Button("Open .gitignore", action: onOpenGitIgnore)
            Button("Open .git/config", action: onOpenGitConfig)
        }
    }
}
```

- [ ] **Step 3: Add option loading and mutable draft bindings**

Add these helpers to `RepositorySettingsSheetView`:

```swift
private func loadOptions() async {
    async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
    async let loadedBranches = GitStatusService.shared.localBranches(in: repositoryURL)
    async let loadedCurrentBranch = GitStatusService.shared.currentBranch(in: repositoryURL)

    let (remotes, branches, currentBranch) = await (loadedRemotes, loadedBranches, loadedCurrentBranch)

    await MainActor.run {
        self.remotes = remotes
        self.branches = branches
        self.currentBranch = currentBranch
        draft = RepositorySettingsDraft(
            settings: initialSettings,
            remotes: remotes,
            branches: branches,
            currentBranch: currentBranch
        )
    }
}

private func binding<Value>(_ keyPath: WritableKeyPath<RepositorySettingsDraft, Value>) -> Binding<Value> {
    Binding(
        get: { draft![keyPath: keyPath] },
        set: { draft![keyPath: keyPath] = $0 }
    )
}
```

- [ ] **Step 4: Build the app and verify the new sheet compiles**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED with the new sheet compiling cleanly.

- [ ] **Step 5: Commit**

```bash
git add macgit/Views/Common/RepositorySettingsSheetView.swift macgit/ViewModels/RepositorySettingsDraft.swift
git commit -m "feat: add repository settings sheet"
```

---

### Task 5: Wire Settings Into Main Window, Pull Defaults, And Runtime Behavior

**Files:**
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Modify: `macgit/Views/Common/PullSheetView.swift`
- Modify: `macgit/Services/SyncState.swift`
- Modify: `macgit/Models/RepoSettings.swift`

- [ ] **Step 1: Add saved-settings plumbing to `MainWindowView`**

Add state to `MainWindowView` near the other sheet flags:

```swift
@State private var showingRepositorySettings = false
@State private var repoSettings = RepoSettings.defaults(currentBranch: nil, remotes: [])

private let repoSettingsStore = RepoSettingsStore.shared
private let fileService = RepositorySettingsFileService()
```

Update the toolbar button:

```swift
ToolbarItem(placement: .automatic) {
    toolbarButton(icon: "gear", label: "Settings", action: {
        showingRepositorySettings = true
    })
}
```

Add the sheet presentation:

```swift
.sheet(isPresented: $showingRepositorySettings) {
    RepositorySettingsSheetView(
        repositoryURL: repositoryURL,
        initialSettings: repoSettings,
        onSave: { newSettings in
            repoSettings = newSettings
            repoSettingsStore.update(for: repositoryURL.path, settings: newSettings)
            syncState.startBackgroundSync(repositoryURL: repositoryURL, settings: newSettings)
        },
        onOpenGitIgnore: { openGitIgnoreFile() },
        onOpenGitConfig: { openGitConfigFile() },
        onOpenRemoteURL: { remote in openRemoteURL(remote: remote) }
    )
}
```

- [ ] **Step 2: Load repo settings during initial refresh**

Update `performInitialLoad()`:

```swift
private func performInitialLoad() async {
    let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
    let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
    let settings = repoSettingsStore.settings(
        for: repositoryURL.path,
        currentBranch: currentBranch,
        remotes: remotes
    )

    await MainActor.run {
        repoSettings = settings
    }

    await syncState.refresh(repositoryURL: repositoryURL)
    syncState.startBackgroundSync(repositoryURL: repositoryURL, settings: settings)

    let remoteName = settings.defaultRemoteName ?? remotes.first ?? "origin"
    let remoteURLString = await GitStatusService.shared.remoteURL(remote: remoteName, in: repositoryURL)
    if !remoteURLString.isEmpty {
        await MainActor.run {
            self.remoteURLString = remoteURLString
            repoIconName = determineRepoIconName(from: remoteURLString)
        }
    }
}
```

- [ ] **Step 3: Make pull defaults and confirmation flows honor settings**

Update `pullSheet`:

```swift
private var pullSheet: some View {
    PullSheetView(
        repositoryURL: repositoryURL,
        preselectedRemote: repoSettings.defaultRemoteName,
        preselectedBranch: repoSettings.defaultPullBranch.isEmpty ? pullPreselectedBranch : repoSettings.defaultPullBranch,
        defaultPullStrategy: repoSettings.pullStrategy
    ) { remote, branch, options in
        Task {
            await syncState.performPull(remote: remote, branch: branch, options: options, repositoryURL: repositoryURL)
        }
    }
}
```

Update tag checkout handling:

```swift
onRequestCheckout: { ref, isTag in
    if isTag {
        tagToCheckout = ref
        if repoSettings.confirmDetachedHeadCheckout {
            showingDetachedHeadConfirmation = true
        } else {
            Task { await performTagCheckout(tag: ref) }
        }
    } else {
        branchToCheckout = ref
        showingCheckoutConfirmation = true
    }
}
```

Update stash deletion flow:

```swift
private func requestStashAction(ref: String, action: StashAction) {
    if action == .delete && !repoSettings.confirmDestructiveStashActions {
        Task { await performStashAction(ref: ref, action: action, deleteAfterApplying: false) }
        return
    }
    pendingStashRef = ref
    pendingStashAction = action
}
```

- [ ] **Step 4: Teach `PullSheetView` and `SyncState` about saved defaults**

Update `PullSheetView`’s signature and option mapping:

```swift
let preselectedRemote: String?
let defaultPullStrategy: PullStrategy

private var pullOptions: GitStatusService.PullOptions {
    GitStatusService.PullOptions(
        commitMerged: commitMerged,
        includeMessages: includeMessages,
        noFastForward: noFastForward,
        rebaseInstead: rebaseInstead
    )
}
```

Set the initial remote during `loadData()`:

```swift
await MainActor.run {
    remotes = currentRemotes
    selectedRemote = preselectedRemote.flatMap { currentRemotes.contains($0) ? $0 : nil } ?? currentRemotes.first ?? ""
    localBranch = currentLocal
    rebaseInstead = defaultPullStrategy == .rebase
}
```

Extend `SyncState`:

```swift
func startBackgroundSync(repositoryURL: URL, settings: RepoSettings) {
    stopBackgroundSync()
    backgroundTask = Task {
        while !Task.isCancelled {
            if settings.autoFetchEnabled {
                try? await GitStatusService.shared.fetch(options: GitStatusService.FetchOptions(), in: repositoryURL)
            }
            await refresh(repositoryURL: repositoryURL)
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}
```

And gate the active-app refresh:

```swift
.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
    guard repoSettings.refreshOnAppActive else { return }
    Task {
        await syncState.refresh(repositoryURL: repositoryURL)
    }
}
```

- [ ] **Step 5: Add file-opening helpers in `MainWindowView`**

```swift
private func openRemoteURL(remote: String? = nil) {
    let targetRemote = remote ?? repoSettings.defaultRemoteName ?? "origin"
    Task {
        let remoteURL = await GitStatusService.shared.remoteURL(remote: targetRemote, in: repositoryURL)
        guard let url = browserURL(from: remoteURL) else { return }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}

private func openGitIgnoreFile() {
    do {
        let fileURL = try fileService.prepareGitIgnore(in: repositoryURL)
        NSWorkspace.shared.open(fileURL)
    } catch {
        syncState.showError(error.localizedDescription)
    }
}

private func openGitConfigFile() {
    guard let fileURL = fileService.gitConfigURL(in: repositoryURL) else {
        syncState.showInfo("Could not find .git/config for this repository.")
        return
    }
    NSWorkspace.shared.open(fileURL)
}
```

- [ ] **Step 6: Build and run focused tests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/RepoSettingsStoreTests -only-testing:macgitTests/RepositorySettingsDraftTests -only-testing:macgitTests/RepositorySettingsFileServiceTests`
Expected: PASS with all new repo settings tests green.

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED with `MainWindowView`, `PullSheetView`, and `SyncState` compiling together.

- [ ] **Step 7: Commit**

```bash
git add macgit/Views/MainWindow/MainWindowView.swift macgit/Views/Common/PullSheetView.swift macgit/Services/SyncState.swift macgit/Views/Common/RepositorySettingsSheetView.swift
git commit -m "feat: wire repo settings into main window"
```

---

### Task 6: Run Full Verification And Manual Smoke Checks

**Files:**
- Modify: none
- Test: `macgitTests/RepoSettingsStoreTests.swift`
- Test: `macgitTests/RepositorySettingsDraftTests.swift`
- Test: `macgitTests/RepositorySettingsFileServiceTests.swift`

- [ ] **Step 1: Run the full macgit test suite**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`
Expected: PASS with the existing suite and the new repo settings tests all green.

- [ ] **Step 2: Perform a manual smoke pass in the running app**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
open $(ls -dt ~/Library/Developer/Xcode/DerivedData/macgit-*/Build/Products/Debug/Commit+.app | head -n 1)
```

Verify manually:

- `Settings` toolbar button opens the repo settings sheet
- top tabs switch between `Remote`, `Pull & Fetch`, and `Safety & Files`
- changing `Default Remote` affects `Open Remote URL`
- changing `Pull Strategy` preselects merge vs rebase in `PullSheetView`
- disabling `Refresh On App Active` prevents refresh on app activation
- enabling `Auto Fetch` performs background fetches without crashing
- `Open .gitignore` creates the file if needed and opens it
- `Open .git/config` opens when present and shows an info alert when absent
- disabling `Confirm Detached HEAD Checkout` bypasses the detached-HEAD alert for tag checkout
- disabling `Confirm Destructive Stash Actions` allows direct stash deletion

- [ ] **Step 3: Commit the verified implementation**

```bash
git status --short
git add macgit/Models/RepoSettings.swift macgit/Services/RepoSettingsStore.swift macgit/ViewModels/RepositorySettingsDraft.swift macgit/Services/RepositorySettingsFileService.swift macgit/Views/Common/RepositorySettingsSheetView.swift macgit/Views/Common/PullSheetView.swift macgit/Views/MainWindow/MainWindowView.swift macgit/Services/SyncState.swift macgitTests/RepoSettingsStoreTests.swift macgitTests/RepositorySettingsDraftTests.swift macgitTests/RepositorySettingsFileServiceTests.swift
git commit -m "feat: add repo settings modal"
```

---

## Self-Review Checklist

Spec coverage check:

- `Settings` toolbar button opening a repo-specific sheet is covered in Task 5
- top-tab modal with `Remote`, `Pull & Fetch`, and `Safety & Files` is covered in Task 4
- per-repository persistence via `UserDefaults` is covered in Task 1
- hybrid branch picker/manual entry is covered in Task 2 and Task 4
- `.gitignore` and `.git/config` external-open behavior is covered in Task 3 and Task 5
- runtime behavior for refresh, auto-fetch, pull defaults, and confirmations is covered in Task 5

Placeholder scan:

- No `TODO`, `TBD`, or “implement later” markers remain
- All tasks list exact file paths and verification commands

Type consistency:

- `RepoSettings`, `PullStrategy`, `RepositorySettingsDraft`, `RepoSettingsStore`, and `RepositorySettingsFileService` names are used consistently throughout
