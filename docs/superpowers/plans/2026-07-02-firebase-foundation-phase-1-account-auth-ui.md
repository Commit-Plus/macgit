# Firebase Foundation Phase 1 Account Auth and UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement optional email/password and Google authentication plus the always-visible Account toolbar menu and account sheets.

**Architecture:** `AccountSessionController` owns app state and consumes an `AccountAuthenticating` protocol. Firebase and Google SDK details stay in `FirebaseAuthService`; views render app-owned state and actions.

**Tech Stack:** SwiftUI, FirebaseAuth, GoogleSignIn, XCTest, macOS URL handling.

---

## File Structure

- Create `macgit/Services/AccountAuthenticating.swift`: auth protocol and app errors.
- Create `macgit/Services/FirebaseAuthService.swift`: Firebase/Google adapter.
- Create `macgit/App/AccountSessionController.swift`: observable session state.
- Create `macgit/Views/Account/AccountToolbarMenu.swift`: guest/Free/Pro menu rendering.
- Create `macgit/Views/Account/AuthenticationSheet.swift`: sign-in/create UI.
- Create `macgit/Views/Account/ManageAccountSheet.swift`: identity and account controls.
- Modify `macgit/Views/MainWindow/ContentView.swift`: always-visible toolbar menu and sheets.
- Modify `macgit/App/macgitApp.swift`: inject the shared account controller and route Google callback URLs.
- Test with `AccountSessionControllerTests.swift` and `AccountMenuPolicyTests.swift`.

### Task 1: Define Auth Boundary and Controller

**Files:**
- Create: `macgit/Services/AccountAuthenticating.swift`
- Create: `macgit/App/AccountSessionController.swift`
- Create: `macgitTests/AccountSessionControllerTests.swift`

- [x] **Step 1: Write failing controller tests**

```swift
import XCTest
@testable import macgit

@MainActor
final class AccountSessionControllerTests: XCTestCase {
    func testGuestRemainsAvailableWhenFirebaseIsMissing() {
        let controller = AccountSessionController(auth: FakeAccountAuth(current: nil), bootstrapStatus: .missingConfiguration)
        XCTAssertEqual(controller.state, .guest)
        XCTAssertFalse(controller.cloudFeaturesAvailable)
    }

    func testEmailSignInPublishesAccount() async {
        let account = AccountSnapshot(uid: "u1", email: "a@example.com", displayName: nil, providerIDs: ["password"])
        let controller = AccountSessionController(auth: FakeAccountAuth(signInResult: account), bootstrapStatus: .configured)
        await controller.signIn(email: "a@example.com", password: "secret12")
        XCTAssertEqual(controller.state, .authenticated(account))
    }
}
```

- [x] **Step 2: Run and confirm missing-type failure**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/AccountSessionControllerTests
```

- [x] **Step 3: Add protocol, errors, and state**

```swift
import Foundation

enum AccountAuthError: LocalizedError, Equatable {
    case invalidCredentials, emailAlreadyInUse, weakPassword, networkUnavailable
    case needsExistingMethod(email: String, providerIDs: [String])
    case googlePresentationUnavailable, cloudNotConfigured, message(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "The email or password is incorrect."
        case .emailAlreadyInUse: return "An account already exists for this email."
        case .weakPassword: return "Use a password with at least 6 characters."
        case .networkUnavailable: return "Connect to the internet and try again."
        case .needsExistingMethod: return "Sign in using the existing method to link this account."
        case .googlePresentationUnavailable: return "Commit+ could not present Google Sign-In."
        case .cloudNotConfigured: return "Cloud accounts are not configured in this build."
        case .message(let text): return text
        }
    }
}

protocol AccountAuthenticating {
    var currentAccount: AccountSnapshot? { get }
    func signIn(email: String, password: String) async throws -> AccountSnapshot
    func createAccount(email: String, password: String) async throws -> AccountSnapshot
    func signInWithGoogle() async throws -> AccountSnapshot
    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot
    func sendPasswordReset(email: String) async throws
    func signOut() throws
}

enum AccountSessionState: Equatable { case guest, loading, authenticated(AccountSnapshot), failed(String) }
```

Implement `@MainActor final class AccountSessionController: ObservableObject` with `@Published private(set) var state`, `@Published var presentedSheet`, `@Published var errorMessage`, async sign-in/create/Google/reset methods, and synchronous sign-out. Initialize from `auth.currentAccount`; missing Firebase config remains `.guest` and sets `cloudFeaturesAvailable = false`.

- [x] **Step 4: Add the fake shown in the test file and make tests pass**

Expected: `AccountSessionControllerTests` passes.

- [x] **Step 5: Commit**

```bash
git add macgit/Services/AccountAuthenticating.swift macgit/App/AccountSessionController.swift macgitTests/AccountSessionControllerTests.swift
git commit -m "feat: add account session controller"
```

### Task 2: Implement Firebase Email and Google Auth

**Files:**
- Create: `macgit/Services/FirebaseAuthService.swift`
- Modify: `macgit/App/macgitApp.swift`

- [x] **Step 1: Add the Firebase adapter**

```swift
import AppKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

final class FirebaseAuthService: AccountAuthenticating {
    var currentAccount: AccountSnapshot? { Auth.auth().currentUser.map(Self.snapshot) }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        do { return Self.snapshot(try await Auth.auth().signIn(withEmail: email, password: password).user) }
        catch { throw map(error) }
    }

    func createAccount(email: String, password: String) async throws -> AccountSnapshot {
        do { return Self.snapshot(try await Auth.auth().createUser(withEmail: email, password: password).user) }
        catch { throw map(error) }
    }

    func signInWithGoogle() async throws -> AccountSnapshot {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let window = NSApp.keyWindow ?? NSApp.windows.first
        else { throw AccountAuthError.googlePresentationUnavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AccountAuthError.message("Google did not return an identity token.")
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        do { return Self.snapshot(try await Auth.auth().signIn(with: credential).user) }
        catch { throw map(error) }
    }

    func sendPasswordReset(email: String) async throws { try await Auth.auth().sendPasswordReset(withEmail: email) }
    func signOut() throws { try Auth.auth().signOut(); GIDSignIn.sharedInstance.signOut() }

    private static func snapshot(_ user: User) -> AccountSnapshot {
        AccountSnapshot(uid: user.uid, email: user.email, displayName: user.displayName,
                        providerIDs: user.providerData.map(\.providerID).sorted())
    }
}
```

Add a private `map(_:)` that maps `AuthErrorCode.wrongPassword`, `invalidCredential`, `emailAlreadyInUse`, `weakPassword`, `networkError`, and `accountExistsWithDifferentCredential` to the app errors defined in Task 1; all other errors become `.message(error.localizedDescription)`.

For `accountExistsWithDifferentCredential`, retain the pending Google `AuthCredential` in memory. Implement `completePendingLink(email:password:)` by signing in with email/password, calling `user.link(with: pendingCredential)`, clearing the pending credential on success, and returning the linked `AccountSnapshot`. The authentication sheet asks for the existing password; it never creates a second Firebase UID.

- [x] **Step 2: Route Google callback URLs**

Attach to the root `ContentView` scene:

```swift
.onOpenURL { url in
    _ = GIDSignIn.sharedInstance.handle(url)
}
```

- [x] **Step 3: Build and run controller tests**

Expected: BUILD SUCCEEDED and controller tests pass without contacting Firebase.

- [x] **Step 4: Commit**

```bash
git add macgit/Services/FirebaseAuthService.swift macgit/App/macgitApp.swift
git commit -m "feat: implement Firebase account authentication"
```

### Task 3: Add Account Menu Policy

**Files:**
- Create: `macgit/Views/Account/AccountMenuPolicy.swift`
- Create: `macgitTests/AccountMenuPolicyTests.swift`

- [x] **Step 1: Test guest, Free, and Pro action ordering**

Define expected arrays exactly as approved: guest `[signIn, createAccount, upgrade]`; Free `[manageAccount, syncLocked, upgrade, signOut]`; Pro `[manageAccount, syncStatus, manageSubscriptionComingLater, signOut]`.

- [x] **Step 2: Implement pure policy**

```swift
enum AccountMenuAction: Equatable {
    case signIn, createAccount, manageAccount, syncLocked, syncStatus
    case upgrade, manageSubscriptionComingLater, signOut
}

enum AccountMenuPolicy {
    static func actions(account: AccountSnapshot?, entitlement: AccountEntitlement) -> [AccountMenuAction] {
        guard account != nil else { return [.signIn, .createAccount, .upgrade] }
        return entitlement.hasProAccess
            ? [.manageAccount, .syncStatus, .manageSubscriptionComingLater, .signOut]
            : [.manageAccount, .syncLocked, .upgrade, .signOut]
    }
}
```

- [x] **Step 3: Run focused tests and commit**

Expected: all `AccountMenuPolicyTests` pass.

### Task 4: Build Account Views and Wire the Root Toolbar

**Files:**
- Create: `macgit/Views/Account/AccountToolbarMenu.swift`
- Create: `macgit/Views/Account/AuthenticationSheet.swift`
- Create: `macgit/Views/Account/ManageAccountSheet.swift`
- Modify: `macgit/Views/MainWindow/ContentView.swift`
- Modify: `macgit/App/macgitApp.swift`

- [ ] **Step 1: Create `AuthenticationSheet`**

Implement a native sheet with segmented `Sign In`/`Create Account`, email/password fields, inline error, primary action, password reset, Google action, disabled `Sign in with Apple · Coming later`, Cancel, loading disablement, and the guest-use reminder. Bind actions only to `AccountSessionController`.

- [ ] **Step 2: Create `ManageAccountSheet`**

Render identity/provider summary, plan badge, a Phase-2-ready sync row, disabled billing action labelled `Upgrade to Pro · Coming later` or `Manage Subscription · Coming later`, Sign Out, and `Delete Account...` disabled with an explanatory accessibility hint until Phase 2.

- [ ] **Step 3: Create `AccountToolbarMenu`**

Use `Menu` with label `Label("Account", systemImage: "person.crop.circle")`. Render actions from `AccountMenuPolicy` in the approved order and keep the menu available with or without an open repository.

- [ ] **Step 4: Mount at the root**

Add to `ContentView`:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        AccountToolbarMenu(controller: accountController)
    }
}
.sheet(item: $accountController.presentedSheet) { sheet in
    accountSheet(for: sheet)
}
```

Inject one `@StateObject AccountSessionController` from `macgitApp`; do not instantiate controllers per repository window content subtree.

- [ ] **Step 5: Run targeted tests and full suite**

Expected: account policy/controller tests pass, then TEST SUCCEEDED for the full suite.

- [ ] **Step 6: Commit and mark Phase 1 complete in the roadmap**

```bash
git add macgit/Views/Account macgit/Views/MainWindow/ContentView.swift macgit/App/macgitApp.swift docs/superpowers/plans/2026-07-02-firebase-foundation-roadmap.md
git commit -m "feat: add optional Commit+ account UI"
```
