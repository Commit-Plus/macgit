#!/bin/zsh
set -euo pipefail

# Prepare and publish a Commit+ release tag.
# Usage: ./scripts/release/prepare-release.sh <version>
# Example: ./scripts/release/prepare-release.sh 1.2.3

VERSION="${1:?usage: prepare-release.sh <version>}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION. Expected X.Y.Z (e.g. 1.2.3)" >&2
  exit 1
fi

TAG="v$VERSION"
PBXPROJ="macgit.xcodeproj/project.pbxproj"

# Ensure we are on main with a clean working tree.
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Must be on the main branch. Current branch: $CURRENT_BRANCH" >&2
  exit 1
fi

if [[ -n $(git status --short) ]]; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

# Update MARKETING_VERSION in all build configurations.
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"

if ! grep -q "MARKETING_VERSION = $VERSION;" "$PBXPROJ"; then
  echo "Failed to update MARKETING_VERSION in $PBXPROJ" >&2
  exit 1
fi

git add "$PBXPROJ"
git commit -m "chore: bump MARKETING_VERSION to $VERSION"
git push origin main

git tag "$TAG"
git push origin "$TAG"

echo "Prepared release $TAG."
echo "Monitor the workflow at: https://github.com/$(git remote get-url origin | sed -E 's/.*github.com[\/:]([^\/]+\/[^\/]+)\.git/\1/')/actions"
