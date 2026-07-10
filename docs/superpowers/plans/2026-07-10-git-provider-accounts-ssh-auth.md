# Git Provider Accounts SSH Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable SSH as a full local transport for connected GitHub and GitLab accounts, including key-file selection, local key reference storage, SSH remote credential resolution, and Git command injection.

**Architecture:** HTTPS provider auth remains token based through the existing askpass injector. SSH provider auth adds a local key-reference store and an SSH command injector that supplies `GIT_SSH_COMMAND` for matching SSH remotes while leaving passphrase handling to OpenSSH, ssh-agent, and macOS Keychain.

**Tech Stack:** Swift 5, SwiftUI, AppKit `NSOpenPanel`, XCTest, `Process()` Git runner environment injection, local file-system validation, `xcodebuild`.

## Global Constraints

- Work in `/Users/thanhtran/Project/Commit+/macgit/.worktrees/git-provider-accounts-ssh-auth` on branch `codex/git-provider-accounts-ssh-auth`.
- Prefix verification commands with `rtk`.
- Do not launch the app.
- Every new `.swift` file must start with the AGPL v3 header.
- Do not store SSH private key contents or passphrases.
- Do not write SSH key paths, private key contents, or passphrases to Firestore.
- Keep HTTPS token askpass behavior unchanged.
- Existing decoded provider accounts must default to HTTPS.
- A provider account disconnect must delete local token data and local SSH key references before metadata deletion.

---

## File Structure

- Modify `macgit/Models/GitProviderAccountModels.swift`: add `GitProviderTransportProtocol`, `transportProtocol`, and backward-compatible Codable defaults.
- Modify `macgit/Services/FirestoreGitProviderAccountStore.swift`: encode/decode transport metadata while tolerating older documents.
- Create `macgit/Services/GitProviderSSHKeyStore.swift`: local key reference model, store protocol, key helper, and UserDefaults-backed implementation.
- Modify `macgit/App/GitProviderAccountController.swift`: own SSH key store, save transport/key selections, include SSH key store in resolver, and delete key references on disconnect.
- Modify `macgit/Views/Account/GitProviderAccountsPresentationPolicy.swift`: enable SSH and add save/SSH-key policy helpers.
- Modify `macgit/Views/Account/GitProviderAddAccountSheet.swift`: show key picker row for SSH and save protocol/key selections.
- Modify `macgit/Services/GitProviderCredentialResolver.swift`: resolve HTTPS token credentials and SSH key credentials.
- Modify `macgit/Services/GitCredentialInjector.swift`: add SSH credential injector parallel to askpass.
- Modify `macgit/Services/GitStatusService+Remote.swift`: choose HTTPS or SSH injection before remote commands.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: pass SSH injector where remote actions already pass provider credential resolver if needed.
- Test with existing `GitProviderAccountModelsTests.swift`, `GitProviderAccountsSectionTests.swift`, `GitProviderCredentialResolverTests.swift`, `GitCredentialInjectorTests.swift`, and `GitProviderAccountControllerTests.swift`. Remote Git wiring is verified through the focused credential tests plus the final app build unless a narrow existing fake-runner seam is found during implementation.

### Task 1: Transport Model and Metadata

**Files:**
- Modify: `macgit/Models/GitProviderAccountModels.swift`
- Modify: `macgit/Services/FirestoreGitProviderAccountStore.swift`
- Test: `macgitTests/GitProviderAccountModelsTests.swift`

**Interfaces:**
- Produces: `GitProviderTransportProtocol.https`, `.ssh`
- Produces: `GitProviderAccount.transportProtocol`
- Consumes: existing provider account Codable and Firestore document helpers

- [x] **Step 1: Write failing model tests**

Add tests:

```swift
func testProviderAccountDefaultsTransportProtocolToHTTPSWhenDecodingOldPayload() throws
func testProviderAccountRoundTripsSSHTransportProtocol() throws
```

The old-payload test should encode JSON without `transportProtocol`, decode `GitProviderAccount`, and assert `.https`.

- [x] **Step 2: Run model tests and verify RED**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderAccountModelsTests test
```

Expected: fail because `transportProtocol` does not exist.

- [x] **Step 3: Implement transport model**

Add `GitProviderTransportProtocol` and custom `Codable` for `GitProviderAccount` so missing `transportProtocol` decodes as `.https`.

- [x] **Step 4: Encode/decode Firestore transport**

In `GitProviderAccountDocument.encode`, write `transportProtocol`. In decode, default missing or unknown values to `.https`.

- [x] **Step 5: Run model tests and verify GREEN**

Run the same focused model test command.

Expected: pass.

### Task 2: Local SSH Key Store

**Files:**
- Create: `macgit/Services/GitProviderSSHKeyStore.swift`
- Test: `macgitTests/GitProviderSSHKeyStoreTests.swift`

**Interfaces:**
- Consumes: `GitProviderAccount`
- Produces: `GitProviderSSHKey`
- Produces: `GitProviderSSHKeyStore`
- Produces: `UserDefaultsGitProviderSSHKeyStore`
- Produces: `GitProviderSSHKeyStoreKey.key(for:)`

- [x] **Step 1: Write failing key-store tests**

Create tests:

```swift
func testKeyStoreKeyUsesProviderAccountIdentity()
func testUserDefaultsStoreSavesReadsAndDeletesKey()
func testDeletingMissingKeyIsIdempotent()
```

- [x] **Step 2: Run key-store tests and verify RED**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderSSHKeyStoreTests test
```

Expected: fail because the test file or production types do not exist.

- [x] **Step 3: Implement local key store**

Create the AGPL-headed Swift file with:

```swift
struct GitProviderSSHKey: Equatable, Codable {
    var path: String
}

protocol GitProviderSSHKeyStore {
    func key(for account: GitProviderAccount) throws -> GitProviderSSHKey?
    func saveKey(_ key: GitProviderSSHKey, for account: GitProviderAccount) throws
    func deleteKey(for account: GitProviderAccount) throws
}
```

Store encoded values under a namespaced UserDefaults key derived from `GitProviderTokenVaultKey.key(for:)`.

- [x] **Step 4: Run key-store tests and verify GREEN**

Run the same focused key-store test command.

Expected: pass.

### Task 3: SSH Credential Resolution and Injection

**Files:**
- Modify: `macgit/Services/GitProviderCredentialResolver.swift`
- Modify: `macgit/Services/GitCredentialInjector.swift`
- Test: `macgitTests/GitProviderCredentialResolverTests.swift`
- Test: `macgitTests/GitCredentialInjectorTests.swift`

**Interfaces:**
- Consumes: `GitProviderSSHKeyStore`
- Produces: `GitSSHCredential`
- Produces: `GitSSHCredentialInjecting`
- Produces: `TemporaryGitSSHCredentialInjector`
- Produces: `GitProviderCredentialResolver.sshCredential(for:preferredAccountID:)`

- [x] **Step 1: Write failing resolver and injector tests**

Replace `testSSHRemoteKeepsExistingBehavior` with SSH support tests:

```swift
func testReturnsSSHCredentialForMatchingSSHRemote()
func testSSHRemoteWithoutConfiguredKeyThrows()
func testHTTPSRemoteStillReturnsTokenCredential()
```

Add injector tests:

```swift
func testSSHInjectionSetsGitSSHCommand()
func testSSHInjectionQuotesKeyPathWithSpaces()
func testSSHInjectionThrowsWhenKeyFileDoesNotExist()
```

- [x] **Step 2: Run resolver/injector tests and verify RED**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderCredentialResolverTests -only-testing:macgitTests/GitCredentialInjectorTests test
```

Expected: fail because SSH credential APIs do not exist and SSH still returns nil.

- [x] **Step 3: Implement SSH resolver**

Add SSH-specific resolver method. Keep `credential(for:)` HTTPS-only so existing HTTPS call sites remain readable. Add typed errors for missing configured key and missing key file.

- [x] **Step 4: Implement SSH injector**

Create `GIT_SSH_COMMAND` using `/usr/bin/ssh`, `-i`, quoted key path, and `-o IdentitiesOnly=yes`. Set `GIT_TERMINAL_PROMPT=0`.

- [x] **Step 5: Run resolver/injector tests and verify GREEN**

Run the same focused resolver/injector test command.

Expected: pass.

### Task 4: Account UI and Controller Persistence

**Files:**
- Modify: `macgit/App/GitProviderAccountController.swift`
- Modify: `macgit/Views/Account/GitProviderAccountsPresentationPolicy.swift`
- Modify: `macgit/Views/Account/GitProviderAddAccountSheet.swift`
- Test: `macgitTests/GitProviderAccountControllerTests.swift`
- Test: `macgitTests/GitProviderAccountsSectionTests.swift`

**Interfaces:**
- Consumes: `GitProviderSSHKeyStore`
- Produces: `GitProviderAccountController.saveConnectionSettings(account:transportProtocol:sshKey:)`
- Produces: UI policy helpers for save enablement and SSH key visibility

- [x] **Step 1: Write failing policy/controller tests**

Update/add tests:

```swift
func testAddAccountProtocolOptionsEnableSSH()
func testCanConnectAllowsOAuthSSHForSupportedHosts()
func testSaveRequiresSSHKeyWhenProtocolIsSSH()
func testControllerSavesSSHTransportAndKeyReference()
func testDisconnectDeletesSSHKeyReferenceBeforeMetadata()
```

- [x] **Step 2: Run policy/controller tests and verify RED**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderAccountsSectionTests -only-testing:macgitTests/GitProviderAccountControllerTests test
```

Expected: fail because SSH is disabled and controller has no SSH key store.

- [x] **Step 3: Implement policy and controller settings save**

Enable SSH in protocol options. Add save validation helpers. Inject `GitProviderSSHKeyStore` into the controller, defaulting to a UserDefaults-backed store. Add controller method to save the selected transport and key reference for an already connected account.

- [x] **Step 4: Implement sheet key picker**

Add SSH key state, show `LabeledContent("SSH Key")` only for SSH, open `NSOpenPanel` from a Choose button, and call controller settings save from Save.

- [x] **Step 5: Run policy/controller tests and verify GREEN**

Run the same focused policy/controller test command.

Expected: pass.

### Task 5: Remote Git SSH Injection

**Files:**
- Modify: `macgit/Services/GitStatusService+Remote.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift` if the remote call sites need an explicit SSH injector parameter
- Test: `macgitTests/GitProviderCredentialResolverTests.swift`
- Test: `macgitTests/GitCredentialInjectorTests.swift`

**Interfaces:**
- Consumes: `GitProviderCredentialResolver.sshCredential(for:)`
- Consumes: `GitSSHCredentialInjecting`
- Produces: remote fetch/pull/push SSH environment injection for SSH remotes

- [x] **Step 1: Re-run focused credential tests before wiring**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderCredentialResolverTests -only-testing:macgitTests/GitCredentialInjectorTests test
```

Expected: pass before remote wiring starts.

- [x] **Step 2: Wire remote SSH injection**

Update the private credential-injection helper to check the remote URL. HTTPS remotes use `TemporaryGitCredentialInjector`; SSH remotes use `TemporaryGitSSHCredentialInjector`; unsupported remotes return nil and keep existing behavior.

- [x] **Step 3: Run focused credential tests**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderCredentialResolverTests -only-testing:macgitTests/GitCredentialInjectorTests test
```

Expected: pass.

### Task 6: Final Verification and Roadmap

**Files:**
- Modify: `docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md`
- Modify: `docs/superpowers/plans/2026-07-10-git-provider-accounts-ssh-auth.md`

- [x] **Step 1: Mark plan tasks complete as they pass**

Check off completed steps in this plan.

- [x] **Step 2: Run full test suite**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: pass. If the known test-host `Early unexpected exit` issue appears, do not loop blindly; run the macOS build and report the test-host failure.

- [x] **Step 3: Run build**

Run:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: pass.

- [x] **Step 4: Update roadmap**

Mark SSH Auth `[completed]` with the branch or commit after verification succeeds.
