#!/usr/bin/env bash
set -euo pipefail

# Sync application code from e2b-dev/infra upstream while preserving local infrastructure.
#
# Usage:
#   ./scripts/sync-upstream.sh              # preview changes (dry run)
#   ./scripts/sync-upstream.sh --apply      # apply changes to working tree
#
# Tracked paths (application code):
SYNC_PATHS=(
  "packages/"
  "spec/"
  "tests/"
  "scripts/"
  "go.work"
  "go.work.sum"
)
#
# Excluded paths (even within tracked paths):
EXCLUDE_PATHS=()

UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"

# --- Parse args ---
DRY_RUN=true
if [[ "${1:-}" == "--apply" ]]; then
  DRY_RUN=false
fi

# --- Fetch upstream ---
echo "Fetching ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}..."
git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" --quiet

# --- Build diff ---
LOCAL_HEAD=$(git rev-parse HEAD)
UPSTREAM_HEAD=$(git rev-parse "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}")

if [[ "$LOCAL_HEAD" == "$UPSTREAM_HEAD" ]]; then
  echo "Already up to date with upstream."
  exit 0
fi

# Find merge base for a clean diff
MERGE_BASE=$(git merge-base HEAD "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}")

echo ""
echo "Merge base:  ${MERGE_BASE:0:12}"
echo "Local HEAD:  ${LOCAL_HEAD:0:12}"
echo "Upstream:    ${UPSTREAM_HEAD:0:12}"
echo ""

# Build path arguments
PATH_ARGS=()
for p in "${SYNC_PATHS[@]}"; do
  PATH_ARGS+=("$p")
done

# Generate the patch (upstream changes since merge base, scoped to SYNC_PATHS)
PATCH=$(git diff "${MERGE_BASE}..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" -- "${PATH_ARGS[@]}" || true)

if [[ -z "$PATCH" ]]; then
  echo "No upstream changes in tracked paths since last sync."
  exit 0
fi

# Stats
STAT=$(git diff --stat "${MERGE_BASE}..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" -- "${PATH_ARGS[@]}")
FILE_COUNT=$(echo "$STAT" | tail -1)

echo "Upstream changes in tracked paths:"
echo "-----------------------------------"
echo "$STAT"
echo ""

if $DRY_RUN; then
  echo "This is a dry run. To apply these changes:"
  echo "  ./scripts/sync-upstream.sh --apply"
  echo ""
  echo "After applying, review with 'git diff', then commit."
  exit 0
fi

# --- Apply ---
echo "Applying upstream changes..."

# Use git apply with 3-way merge for conflict handling
echo "$PATCH" | git apply --3way - 2>&1 || {
  echo ""
  echo "Some hunks had conflicts. Resolve them manually, then commit."
  echo "Conflicted files:"
  git diff --name-only --diff-filter=U
  exit 1
}

echo ""
echo "Changes applied cleanly. Review with:"
echo "  git diff --stat"
echo "  git diff"
echo ""
echo "Then commit with something like:"
echo "  git add -A && git commit -m 'sync: pull upstream app code changes'"
