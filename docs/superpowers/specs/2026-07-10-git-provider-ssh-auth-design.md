# Git Provider SSH Auth Design

**Date:** 2026-07-10
**Status:** Approved implementation source
**Scope:** Full SSH transport support for connected GitHub and GitLab provider accounts, including Account UI key selection and remote Git command injection.

## Overview

Git provider accounts currently support HTTPS private repository access through OAuth tokens and an askpass helper. The Add Account and Edit Account sheets already expose a Protocol picker, but SSH is disabled and has no key-file workflow.

This design adds SSH as a first-class local transport option for connected provider accounts. Commit+ stores only local SSH key references and uses OpenSSH for passphrase handling through the user's normal macOS ssh-agent or Keychain setup. Commit+ does not store private key contents or SSH passphrases.

## Product Decisions

- HTTPS remains the default provider account protocol.
- SSH is enabled for GitHub and GitLab accounts.
- Selecting SSH shows an SSH key file picker in Add Account and Edit Account.
- Commit+ stores the selected SSH key reference locally on this Mac only.
- Commit+ does not sync SSH key paths, key contents, or passphrases through Firestore.
- Commit+ does not add a passphrase field.
- Passphrase prompts and unlocked-key reuse are delegated to OpenSSH, ssh-agent, and macOS Keychain behavior.
- Git operations for guests and accounts without SSH profiles keep existing behavior.
- HTTPS token credential injection remains unchanged.

## Goals

- Enable the SSH protocol option in the Account connection UI.
- Let users select a private SSH key file when SSH is selected.
- Persist a local SSH key reference for each connected provider account.
- Use the selected key for SSH remotes that match the connected provider account.
- Support both scp-style remotes, such as `git@github.com:owner/repo.git`, and URL-style remotes, such as `ssh://git@gitlab.com/group/project.git`.
- Keep SSH secrets out of Firestore, command-line arguments beyond the selected key path, logs, and app-visible error text.
- Preserve HTTPS behavior and existing provider token flows.

## Non-Goals

- Managing SSH key passphrases inside Commit+.
- Generating SSH keys.
- Uploading public keys to GitHub or GitLab.
- Syncing SSH key references across devices.
- Supporting per-repository SSH key overrides in the first SSH phase.
- Supporting Bitbucket or other providers.
- Replacing the user's existing ssh-agent or `~/.ssh/config`.

## Account Transport Model

Provider accounts gain a selected Git transport:

```swift
enum GitProviderTransportProtocol: String, Codable, Equatable, CaseIterable, Identifiable {
    case https
    case ssh
}
```

`GitProviderAccount` stores the selected transport as non-secret metadata:

```swift
struct GitProviderAccount: Identifiable, Equatable, Codable {
    var transportProtocol: GitProviderTransportProtocol
}
```

Existing decoded accounts default to `.https` so old metadata remains valid.

The selected SSH key is not part of Firestore account metadata. It is local device state keyed by the same stable provider account identity used for token vault entries:

```text
<macgitUID>:<provider>:<normalizedHost>:<providerUserID>
```

## Local SSH Key Storage

Add a local SSH key store:

```swift
protocol GitProviderSSHKeyStore {
    func key(for account: GitProviderAccount) throws -> GitProviderSSHKey?
    func saveKey(_ key: GitProviderSSHKey, for account: GitProviderAccount) throws
    func deleteKey(for account: GitProviderAccount) throws
}

struct GitProviderSSHKey: Equatable, Codable {
    var path: String
}
```

The first implementation stores only the absolute file path in local app preferences or Keychain data. It never stores private key contents or passphrases. If the app sandbox requires file access persistence, the store can add a local security-scoped bookmark while keeping the public interface as a key reference.

Disconnecting a provider account deletes the local SSH key reference along with the local token before removing provider metadata.

## Account UI

The Add Account and Edit Account sheets show:

- Host
- Auth Type
- Username
- Connect or Reconnect
- Protocol
- SSH Key, only when Protocol is SSH

When Protocol is HTTPS:

- The sheet keeps the existing OAuth/token-backed connect flow.
- SSH key fields are hidden.
- Save requires a connected username.

When Protocol is SSH:

- The sheet shows an SSH key row with a path label and a Choose button.
- Choose opens `NSOpenPanel`.
- The panel allows files only, not directories.
- Save requires a connected username and a selected existing key file.
- The selected protocol and key reference are saved without reconnecting OAuth if the account is already connected.

The UI copy should stay native and compact. It should not explain SSH concepts inside the sheet.

## SSH Remote Resolution

The existing remote identity resolver already parses HTTPS and SSH remote shapes. SSH credential resolution uses the same provider/host matching rules as HTTPS:

1. Parse the remote URL.
2. Match provider and normalized host against connected accounts.
3. If a preferred account is available, require that account to match.
4. If exactly one matching account has SSH selected and a local key reference, use it.
5. If multiple matching accounts are possible, return the existing multiple-account error.
6. If no SSH key is configured, return a user-facing missing-key error.

HTTPS remotes continue using token askpass credentials. SSH remotes never use OAuth tokens as Git passwords.

## SSH Command Injection

Add an SSH injection layer parallel to the HTTPS askpass injector:

```swift
struct GitSSHCredential: Equatable {
    var username: String
    var keyPath: String
}

protocol GitSSHCredentialInjecting {
    func injection(for credential: GitSSHCredential) throws -> GitCredentialInjection
}
```

The production injector sets:

```text
GIT_TERMINAL_PROMPT=0
GIT_SSH_COMMAND=ssh -i <keyPath> -o IdentitiesOnly=yes
```

The injector validates that the key file exists before returning an environment. It does not copy or mutate the key file. It quotes the key path safely for shell use.

OpenSSH handles passphrase prompts through the user's configured ssh-agent and macOS Keychain. If the key cannot be unlocked, Git returns its normal authentication failure and Commit+ surfaces the Git error without exposing secrets.

## Security Rules

- Do not store SSH private key contents.
- Do not store SSH passphrases.
- Do not write SSH key paths to Firestore.
- Do not log `GIT_SSH_COMMAND`.
- Do not infer GitLab self-hosted providers from hostnames alone; keep using connected account hosts.
- Preserve token deletion before metadata deletion when disconnecting accounts.
- Delete local SSH key references during provider account disconnect.
- Keep local Git behavior unchanged when a remote does not match a connected account.

## Error Handling

Add typed SSH credential errors:

```swift
enum GitProviderCredentialError {
    case sshKeyUnavailable(username: String)
    case sshKeyMissing(path: String)
}
```

User-facing messages should be concise:

- Missing configured key: "The SSH key for <username> is unavailable. Choose a key and try again."
- Missing file: "The selected SSH key file could not be found."

Existing HTTPS errors remain unchanged.

## Testing

Focused test coverage:

- Model decoding defaults old accounts to HTTPS.
- Protocol presentation enables SSH for GitHub and GitLab.
- SSH UI policy requires a key only when SSH is selected.
- SSH key store saves, reads, and deletes local key references by provider account key.
- SSH resolver ignores HTTPS remotes and resolves SSH remotes for matching accounts.
- SSH resolver errors when the matching account has no key.
- SSH injector sets `GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND`.
- SSH injector safely quotes key paths with spaces.
- Remote fetch, pull, and push paths use SSH injection for SSH remotes and preserve HTTPS injection for HTTPS remotes.

Verification before completion:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

## Roadmap Placement

This is a new Git Provider Accounts follow-up phase after Phase 5. It closes the explicit Phase 2 gap where SSH remotes were preserved until SSH credential support was designed.
