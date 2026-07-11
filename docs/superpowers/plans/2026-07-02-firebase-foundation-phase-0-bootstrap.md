# Firebase Foundation Phase 0 Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reproducible Firebase/Google dependencies, configuration detection, and app-owned account models while keeping unconfigured builds usable as guest.

**Architecture:** A small bootstrapper reports configured or missing Firebase resources instead of crashing. App-owned account and entitlement types remain independent of Firebase so later phases are unit-testable.

**Tech Stack:** Swift 5, SwiftUI, FirebaseCore/Auth/Firestore 12.15.0, GoogleSignIn 9.2.0, XCTest, Xcode Swift Package Manager.

---

## Scope

This phase adds dependencies, Firebase project setup documentation, bootstrap status, and pure models. It does not render Account UI or perform authentication.

## File Structure

- Modify `macgit.xcodeproj/project.pbxproj`: add Firebase and Google package references/products plus `-ObjC`.
- Create `macgit/App/FirebaseBootstrap.swift`: configure Firebase only when bundled config exists.
- Create `macgit/Models/AccountModels.swift`: app-owned identity, plan, entitlement, and bootstrap states.
- Modify `macgit/App/macgitApp.swift`: invoke bootstrap without blocking guest startup.
- Create `macgitTests/AccountModelsTests.swift`: model normalization tests.
- Create `docs/firebase-setup.md`: exact console and local configuration steps.

### Task 1: Add Pure Account and Entitlement Models

**Files:**
- Create: `macgit/Models/AccountModels.swift`
- Create: `macgitTests/AccountModelsTests.swift`

- [x] **Step 1: Write failing model tests**

```swift
import XCTest
@testable import macgit

final class AccountModelsTests: XCTestCase {
    func testMissingEntitlementNormalizesToFree() {
        XCTAssertEqual(AccountEntitlement.free.plan, .free)
        XCTAssertFalse(AccountEntitlement.free.hasProAccess)
    }

    func testOnlyActiveProGrantsAccess() {
        XCTAssertTrue(AccountEntitlement(plan: .pro, access: .active, billingStatus: .active).hasProAccess)
        XCTAssertFalse(AccountEntitlement(plan: .pro, access: .inactive, billingStatus: .pastDue).hasProAccess)
    }

    func testAccountSnapshotUsesEmailFallback() {
        let snapshot = AccountSnapshot(uid: "uid-1", email: nil, displayName: nil, providerIDs: ["password"])
        XCTAssertEqual(snapshot.displayLabel, "Commit+ Account")
    }
}
```

- [x] **Step 2: Run the focused test and confirm compile failure**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/AccountModelsTests
```

Expected: FAIL because `AccountEntitlement` and `AccountSnapshot` do not exist.

- [x] **Step 3: Create the app-owned models**

```swift
import Foundation

enum AccountPlan: String, Codable, Equatable { case free, pro }
enum EntitlementAccess: String, Codable, Equatable { case active, inactive }
enum BillingStatus: String, Codable, Equatable { case none, trialing, active, pastDue = "past_due", canceled }
enum EntitlementSource: String, Codable, Equatable { case adminTest = "admin_test", polar }

struct AccountEntitlement: Codable, Equatable {
    var plan: AccountPlan
    var access: EntitlementAccess
    var billingStatus: BillingStatus
    var source: EntitlementSource?
    var currentPeriodEnd: Date?
    var cancelAtPeriodEnd: Bool

    static let free = AccountEntitlement(
        plan: .free,
        access: .inactive,
        billingStatus: .none,
        source: nil,
        currentPeriodEnd: nil,
        cancelAtPeriodEnd: false
    )

    init(
        plan: AccountPlan,
        access: EntitlementAccess,
        billingStatus: BillingStatus,
        source: EntitlementSource? = nil,
        currentPeriodEnd: Date? = nil,
        cancelAtPeriodEnd: Bool = false
    ) {
        self.plan = plan
        self.access = access
        self.billingStatus = billingStatus
        self.source = source
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    var hasProAccess: Bool { plan == .pro && access == .active }
}

struct AccountSnapshot: Equatable {
    let uid: String
    let email: String?
    let displayName: String?
    let providerIDs: [String]
    var displayLabel: String { displayName ?? email ?? "Commit+ Account" }
}

enum FirebaseBootstrapStatus: Equatable { case configured, missingConfiguration, failed(String) }
```

- [x] **Step 4: Run the focused tests**

Expected: `AccountModelsTests` passes with 3 tests.

- [x] **Step 5: Commit**

```bash
git add macgit/Models/AccountModels.swift macgitTests/AccountModelsTests.swift
git commit -m "feat: add account and entitlement models"
```

### Task 2: Add Firebase and Google Packages

**Files:**
- Modify: `macgit.xcodeproj/project.pbxproj`
- Modify: `macgit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

- [x] **Step 1: Add Swift package references**

Add package URLs and minimum versions:

```text
https://github.com/firebase/firebase-ios-sdk.git — upToNextMajor 12.15.0
https://github.com/google/GoogleSignIn-iOS.git — upToNextMajor 9.2.0
```

Add `FirebaseAuth`, `FirebaseFirestore`, and `GoogleSignIn` to the `macgit` target. Add `$(inherited) -ObjC` to `OTHER_LDFLAGS` for Debug and Release.

- [x] **Step 2: Resolve dependencies**

```bash
xcodebuild -resolvePackageDependencies -project macgit.xcodeproj -scheme macgit
```

Expected: package resolution succeeds and `Package.resolved` records Firebase 12.15.x and GoogleSignIn 9.2.x within the allowed major versions.

- [x] **Step 3: Build to prove package linkage**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED.

- [x] **Step 4: Commit**

```bash
git add macgit.xcodeproj/project.pbxproj macgit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "build: add Firebase and Google sign-in packages"
```

### Task 3: Add Safe Firebase Bootstrap

**Files:**
- Create: `macgit/App/FirebaseBootstrap.swift`
- Modify: `macgit/App/macgitApp.swift`

- [x] **Step 1: Create bootstrap implementation**

```swift
import FirebaseCore
import Foundation

enum FirebaseBootstrap {
    static func configure(bundle: Bundle = .main) -> FirebaseBootstrapStatus {
        if FirebaseApp.app() != nil { return .configured }
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path)
        else { return .missingConfiguration }
        FirebaseApp.configure(options: options)
        return .configured
    }
}
```

- [x] **Step 2: Initialize before creating scene state**

Add to `macgitApp`:

```swift
private let firebaseStatus: FirebaseBootstrapStatus

init() {
    firebaseStatus = FirebaseBootstrap.configure()
}
```

Do not fatal-error on `.missingConfiguration`; Account UI in Phase 1 will explain the unavailable cloud configuration while local Git remains usable.

- [x] **Step 3: Build without a plist**

Run the normal build command. Expected: BUILD SUCCEEDED and no runtime configuration is required for compilation.

- [x] **Step 4: Commit**

```bash
git add macgit/App/FirebaseBootstrap.swift macgit/App/macgitApp.swift
git commit -m "feat: bootstrap Firebase without blocking guest mode"
```

### Task 4: Document External Firebase Configuration

**Files:**
- Create: `docs/firebase-setup.md`
- Modify: `.gitignore`

- [x] **Step 1: Write setup instructions with these exact operations**

Document creating the Firebase project, registering macOS bundle ID `dev.thanhtran.commitplus`, enabling Email/Password and Google providers, downloading `GoogleService-Info.plist` to `macgit/GoogleService-Info.plist`, adding the `REVERSED_CLIENT_ID` URL scheme, creating a Firestore database, and installing Firebase CLI for emulator work.

- [x] **Step 2: Keep local production config out of Git**

Add:

```gitignore
macgit/GoogleService-Info.plist
.firebase/
firebase-debug.log
```

- [x] **Step 3: Add a checked-in configuration contract**

Create `docs/examples/GoogleService-Info.plist.example` containing only documented key names with nonfunctional example values, including `BUNDLE_ID`, `GOOGLE_APP_ID`, `PROJECT_ID`, `CLIENT_ID`, and `REVERSED_CLIENT_ID`.

- [x] **Step 4: Commit**

```bash
git add docs/firebase-setup.md .gitignore docs/examples/GoogleService-Info.plist.example
git commit -m "docs: add Firebase project setup guide"
```

### Task 5: Verify Phase 0

- [x] Run all tests:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: TEST SUCCEEDED.

- [x] Update the roadmap Phase 0 entry to `[completed]` with the verified branch or merge commit and commit that documentation update.
