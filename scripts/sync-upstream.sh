#!/usr/bin/env bash
set -euo pipefail

# Sync application code from e2b-dev/infra upstream while preserving local infrastructure.
#
# Usage:
#   ./scripts/sync-upstream.sh              # preview changes (dry run)
#   ./scripts/sync-upstream.sh --apply      # apply changes to working tree
#
# Strategy: uses git checkout + git rm to align tracked paths with upstream,
# which handles renames, deletions, and new files reliably (unlike git apply).

# Tracked paths (application code):
SYNC_PATHS=(
  "packages/"
  "spec/"
  "tests/"
  "go.work"
)

# Local-only files to preserve (exist in our fork but not upstream):
PRESERVE_PATHS=(
  "scripts/sync-upstream.sh"
  "scripts/verify-go-build.sh"
)

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

# --- Compare ---
LOCAL_HEAD=$(git rev-parse HEAD)
UPSTREAM_HEAD=$(git rev-parse "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}")

echo ""
echo "Local HEAD:  ${LOCAL_HEAD:0:12}"
echo "Upstream:    ${UPSTREAM_HEAD:0:12}"
echo ""

# Check for actual file differences in sync paths (not commit count, since histories diverge)
DIFF_STAT=$(git diff HEAD "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" --stat -- "${SYNC_PATHS[@]}" || true)

if [[ -z "$DIFF_STAT" ]]; then
  echo "Already up to date with upstream."
  exit 0
fi

# Count upstream commits since our last common ancestor for the commit message
MERGE_BASE=$(git merge-base HEAD "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || echo "")
if [[ -n "$MERGE_BASE" ]]; then
  COMMIT_COUNT=$(git rev-list --count "${MERGE_BASE}..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" -- "${SYNC_PATHS[@]}")
else
  COMMIT_COUNT="unknown"
fi

echo "File differences in tracked paths:"
echo "-----------------------------------"
echo "$DIFF_STAT"
echo ""
echo "Upstream commits since merge base: ${COMMIT_COUNT}"
echo ""

if $DRY_RUN; then
  echo "This is a dry run. To apply these changes:"
  echo "  ./scripts/sync-upstream.sh --apply"
  echo ""
  echo "After applying, verify builds with: ./scripts/verify-go-build.sh"
  exit 0
fi

# --- Apply ---
echo "Applying upstream changes..."

# Step 1: Find and delete files that upstream removed
echo "  Checking for deleted files..."
DELETED=0
for path in "${SYNC_PATHS[@]}"; do
  # Files in our tree but not in upstream (within sync paths)
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    # Skip files we want to preserve locally
    skip=false
    for preserve in "${PRESERVE_PATHS[@]}"; do
      if [[ "$file" == "$preserve" ]]; then
        skip=true
        break
      fi
    done
    if $skip; then
      continue
    fi
    echo "    rm $file"
    git rm -q "$file"
    DELETED=$((DELETED + 1))
  done < <(git diff HEAD "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" --name-only --diff-filter=D -- "$path" 2>/dev/null)
done
echo "  Deleted: ${DELETED} files"

# Step 2: Checkout all files from upstream for sync paths
echo "  Checking out upstream files..."
for path in "${SYNC_PATHS[@]}"; do
  # Only checkout if the path exists in upstream
  if git ls-tree -d "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" "$path" &>/dev/null || \
     git ls-tree "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" "$path" &>/dev/null; then
    git checkout "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" -- "$path" 2>/dev/null || true
  fi
done

# Step 3: Restore local-only preserved files that upstream checkout may have removed
for preserve in "${PRESERVE_PATHS[@]}"; do
  if ! [[ -f "$preserve" ]] && git show "HEAD:${preserve}" &>/dev/null 2>&1; then
    echo "  Restoring local file: $preserve"
    git checkout HEAD -- "$preserve"
  fi
done

echo ""
echo "Changes applied. Summary:"
git diff --cached --stat | tail -3
echo ""
echo "Next steps:"
echo "  1. Verify builds:  ./scripts/verify-go-build.sh"
echo "  2. Review changes: git diff --cached"
echo "  3. Commit:         git commit -m 'sync: pull upstream app code changes (${COMMIT_COUNT} commits, up to ${UPSTREAM_HEAD:0:9})'"
