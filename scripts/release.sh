#!/usr/bin/env bash
# Usage: ./scripts/release.sh <version> <path/to/Swell.dmg>
#
# 1. Verifies the working tree is clean
# 2. Tags the commit as v<version>
# 3. Pushes the tag
# 4. Creates a GitHub release with notes extracted from CHANGELOG.md
# 5. Attaches the .dmg as a release asset
#
# Before running:
#   - Bump CFBundleShortVersionString in Sources/Info.plist to match <version>
#   - Archive and export the app in Xcode (Product → Archive)
#   - Commit everything, then run this script

set -euo pipefail

VERSION="${1:-}"
ARTIFACT="${2:-}"

if [[ -z "$VERSION" || -z "$ARTIFACT" ]]; then
    echo "Usage: $0 <version> <path/to/Swell.dmg>"
    echo "  e.g. $0 1.0.0 ~/Desktop/Swell.dmg"
    exit 1
fi

if [[ ! -f "$ARTIFACT" ]]; then
    echo "Error: artifact not found: $ARTIFACT"
    exit 1
fi

TAG="v${VERSION}"
REPO=$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git$//')

# --- Guard: clean working tree ---
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is not clean. Commit or stash changes first."
    exit 1
fi

# --- Guard: tag doesn't already exist ---
if git rev-parse "$TAG" &>/dev/null; then
    echo "Error: tag $TAG already exists."
    exit 1
fi

# --- Extract release notes from CHANGELOG.md ---
# Grabs lines between the first "## [x.y.z]" header and the next "## " header.
NOTES=$(awk "/^## \[${VERSION}\]/{found=1; next} found && /^## /{exit} found{print}" CHANGELOG.md)

if [[ -z "$NOTES" ]]; then
    echo "Warning: no changelog entry found for ${VERSION}. Release notes will be empty."
fi

echo "Tagging $TAG on $(git rev-parse --short HEAD)..."
git tag "$TAG"
git push origin "$TAG"

echo "Creating GitHub release $TAG on $REPO..."
gh release create "$TAG" "$ARTIFACT" \
    --repo "$REPO" \
    --title "Swell $TAG" \
    --notes "$NOTES"

echo "Done — https://github.com/$REPO/releases/tag/$TAG"
