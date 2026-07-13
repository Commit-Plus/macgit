# Commit+ DMG Release Design

## Goal

Extend the successful tag-driven release pipeline to publish a notarized DMG for first-time downloads while retaining the existing ZIP as the Sparkle update payload.

## Release Artifacts

Each stable release publishes two application artifacts:

- `Commit+-<version>-arm64.dmg` for the landing page and manual installation.
- `Commit+-<version>-arm64.zip` for the existing Sparkle appcast and automatic updates.

GitHub's automatically generated source archives remain unrelated to application distribution.

## Build and Signing Flow

1. Archive the Release configuration.
2. Export the archive with the Developer ID distribution method so Xcode re-signs Sparkle's nested helpers correctly.
3. Create the ZIP from the exported and signed `Commit+.app`.
4. Submit the ZIP to Apple's notary service, staple the returned ticket to `Commit+.app`, and recreate the ZIP so it contains the stapled app.
5. Create a read-only compressed DMG from the stapled app. The mounted image contains `Commit+.app` and an `Applications` symlink.
6. Submit the DMG to Apple's notary service and staple the returned ticket to the DMG.

The workflow must not re-sign the app after notarization because doing so would invalidate its ticket.

## Publication Flow

The GitHub Release create/update step uploads both artifacts with replacement enabled for retry safety. The public asset verification step checks both versioned download URLs.

Sparkle `generate_appcast` continues to receive only the ZIP in its working directory. This prevents duplicate appcast items for the same version and preserves the already qualified update path.

GitHub Pages deployment remains unchanged and publishes the generated `appcast.xml`.

## Verification and Failure Handling

Before publication, the pipeline verifies:

- The exported app metadata, architecture, Developer ID signature, Gatekeeper assessment, and stapled ticket.
- The DMG exists, mounts successfully, contains `Commit+.app` and the `Applications` symlink, passes Gatekeeper assessment, and has a valid stapled ticket.
- Both GitHub Release assets become publicly reachable.

Notarization failures print Apple's issue log and stop before stapling. Temporary mounted images are detached during cleanup even after a failed verification.

## Scope Boundaries

- No landing-page implementation is included.
- No visual DMG background or custom icon layout is included in this first iteration.
- The Sparkle appcast format and ZIP-based update behavior do not change.
- The existing `v1.0.1` release is not modified; the first intended DMG release is `v1.0.2`.
