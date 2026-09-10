# Terminal repository opening implementation

1. Build a signed native helper in Contents/Helpers, sharing runtime selection and repository validation with the app.
2. Add a strict macgit://open-repository URL route, preserving authentication callbacks.
3. Resolve repository roots with Git, including subfolders, empty repositories and worktrees; preserve literal paths and reject invalid folders.
4. Install a symlink at ~/.local/bin/commit from General Settings, without overwriting existing commands. Show PATH guidance.
5. Test parser, resolver and installation in isolation, build the macOS app and inspect packaged helper. Do not launch the app.

The helper returns success when macOS accepts the open request. Errors after handoff appear in the app. Bare repositories are unsupported. Embedded Git remains the existing optional downloaded runtime; the CLI honors the app's runtime preference.

## Build integration

The app build phase compiles each requested architecture, combines them with lipo,
and signs the nested helper before the app is signed. Script sandboxing is disabled
for this app target because the Swift compiler creates its own module-cache files.
This does not change the app's runtime sandbox or hardened-runtime settings.

## Verification

- 26 isolated parser, URL round-trip, real Git repository/worktree, inherited Git
  environment, and installation checks passed via `bash scripts/test-command-line.sh`.
- The packaged helper passed strict signature verification, help output, PATH-style
  argv[0] lookup, and nonzero stderr checks for non-repos, missing folders and invalid
  arguments. These checks do not launch the app.
- `xcodebuild build` passed after integration.
- Window activation, cold-launch routing and Settings interaction still require a
  manual check; the app was not launched, following repository instructions.

## Launch setup tip and automatic PATH configuration

- Offer one setup tip per process launch, after other startup sheets are dismissed.
- Close only dismisses this launch; Don't remind stores a local suppression flag.
- Skip the tip when the CLI symlink and shell configuration are both installed.
- One button installs the helper and appends the PATH command, backing up existing
  zsh/bash/fish configuration and preserving symlinks. Settings shares the same setup model.
- Display installation errors in the tip, retain a retry button for partial setup,
  and explain that existing terminal sessions need the displayed command or a new tab.
- Validate reminder policy, shell configuration, repeated installation and preservation
  with the standalone CLI harness; build without launching the app.

Validation after setup-tip integration: 45 standalone checks passed; final macOS build succeeded. The app was not launched, so modal appearance and interaction remain manually unverified.
