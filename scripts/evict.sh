#!/bin/bash
# evict.sh — Delete GHCR images for an evicted FVS version
#
# Called by the build-runtime workflow after a new version is added to
# releases.json and the oldest entry falls off the retention window.
#
# Deletes the runtime image for the specified version tag from GHCR.
#
# Usage:
#   bash scripts/evict.sh <version>
#   bash scripts/evict.sh FS2025.4c
#
# Environment:
#   GH_TOKEN        GitHub token with packages:delete permission (required)
#   GITHUB_REPOSITORY_OWNER  Set automatically by GitHub Actions

set -euo pipefail

EVICTED_VERSION="${1:-}"

if [ -z "$EVICTED_VERSION" ]; then
  echo "Usage: evict.sh <version>" >&2
  exit 1
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN environment variable is required." >&2
  exit 1
fi

ORG="${GITHUB_REPOSITORY_OWNER:-}"
if [ -z "$ORG" ]; then
  echo "ERROR: GITHUB_REPOSITORY_OWNER environment variable is required." >&2
  exit 1
fi

PACKAGE_NAME="fvs-runtime"

echo "Evicting FVS version ${EVICTED_VERSION} from GHCR (${ORG}/${PACKAGE_NAME})..."

# List all versions of the package and find the one matching the evicted tag
VERSIONS=$(gh api \
  "/orgs/${ORG}/packages/container/${PACKAGE_NAME}/versions" \
  --paginate \
  --jq '.[] | {id: .id, tags: .metadata.container.tags}')

# Find the version ID for the evicted tag
VERSION_ID=$(echo "$VERSIONS" | \
  jq -r --arg tag "$EVICTED_VERSION" \
  'select(.tags[] == $tag) | .id' 2>/dev/null || true)

if [ -z "$VERSION_ID" ]; then
  echo "WARNING: No GHCR image found for tag '${EVICTED_VERSION}'. It may have already been deleted." >&2
  exit 0
fi

# Delete the package version
gh api \
  --method DELETE \
  "/orgs/${ORG}/packages/container/${PACKAGE_NAME}/versions/${VERSION_ID}"

echo "Deleted GHCR image ${ORG}/${PACKAGE_NAME}:${EVICTED_VERSION} (version ID: ${VERSION_ID})"
