#!/usr/bin/env bash
set -euo pipefail

# Verify all Go packages compile inside a Linux Docker container.
# Catches CGO issues, Linux-only syscall usage, and missing dependencies
# that won't surface on macOS.
#
# Usage:
#   ./scripts/verify-go-build.sh              # build all packages
#   ./scripts/verify-go-build.sh packages/api # build specific package(s)

GO_VERSION="1.25.4"
IMAGE="golang:${GO_VERSION}-bookworm"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Packages that require CGO (C dependencies, Linux kernel interfaces)
CGO_PACKAGES=(
  "packages/orchestrator"
)

# All workspace packages from go.work
ALL_PACKAGES=(
  "packages/api"
  "packages/auth"
  "packages/clickhouse"
  "packages/client-proxy"
  "packages/dashboard-api"
  "packages/db"
  "packages/docker-reverse-proxy"
  "packages/envd"
  "packages/local-dev"
  "packages/nomad-nodepool-apm"
  "packages/orchestrator"
  "packages/shared"
  "tests/integration"
)

# If specific packages are given as args, use those; otherwise build all
if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=("${ALL_PACKAGES[@]}")
fi

is_cgo_package() {
  local pkg="$1"
  for cgo_pkg in "${CGO_PACKAGES[@]}"; do
    if [[ "$pkg" == "$cgo_pkg" ]]; then
      return 0
    fi
  done
  return 1
}

PASS=()
FAIL=()

echo "=== Go Build Verification (Linux/${GOARCH:-$(go env GOARCH)}) ==="
echo "Image: ${IMAGE}"
echo "Packages: ${#TARGETS[@]}"
echo ""

for pkg in "${TARGETS[@]}"; do
  # Strip trailing slash
  pkg="${pkg%/}"

  if ! [[ -d "${REPO_ROOT}/${pkg}" ]]; then
    echo "SKIP  ${pkg} (directory not found)"
    continue
  fi

  if is_cgo_package "$pkg"; then
    CGO_FLAG="1"
    CGO_LABEL="CGO=1"
  else
    CGO_FLAG="0"
    CGO_LABEL="CGO=0"
  fi

  printf "BUILD %-45s [%s] ... " "$pkg" "$CGO_LABEL"

  # Run go build inside Docker, mounting the repo read-only.
  # Uses 'go build ./...' to compile-check all sub-packages.
  # The -o /dev/null discards binaries — we only care about compilation.
  if OUTPUT=$(docker run --rm \
    --platform linux/$(go env GOARCH) \
    -v "${REPO_ROOT}:/src:ro" \
    -w "/src/${pkg}" \
    -e CGO_ENABLED="${CGO_FLAG}" \
    -e GOWORK="/src/go.work" \
    "${IMAGE}" \
    sh -c '
      # Try building with output to tmpdir (handles main packages on read-only mount).
      # Fall back to plain go build for library-only packages.
      mkdir -p /tmp/out
      if ! go build -o /tmp/out/ ./... 2>&1; then
        go build ./... 2>&1 || exit 1
      fi
      go vet ./... 2>&1
    ' 2>&1); then
    echo "OK"
    PASS+=("$pkg")
  else
    echo "FAIL"
    echo "$OUTPUT" | grep -v '^go: downloading' | head -30
    FAIL+=("$pkg")
  fi
done

echo ""
echo "=== Results ==="
echo "Passed: ${#PASS[@]}/${#TARGETS[@]}"

if [[ ${#FAIL[@]} -gt 0 ]]; then
  echo "Failed: ${#FAIL[@]}"
  for f in "${FAIL[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo "All packages compiled successfully."
