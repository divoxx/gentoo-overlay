#!/usr/bin/env bash
# verify-ebuild.sh — Deterministic ebuild QA and build verifier.
#
# Usage:
#   verify-ebuild.sh <category/name> [version]
#   verify-ebuild.sh dev-python/foo
#   verify-ebuild.sh dev-python/foo 1.3.0
#
# Exits 0 on success, 1 on any failure.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 <category/name> [version]" >&2; exit 1; }

ATOM="$1"
VERSION="${2:-}"
CATEGORY="${ATOM%%/*}"
NAME="${ATOM##*/}"

[[ "$CATEGORY" != "$ATOM" && -n "$CATEGORY" && -n "$NAME" ]] || \
    die "Invalid atom '$ATOM'. Expected category/name (e.g. dev-python/foo)"

# ---------------------------------------------------------------------------
# Locate overlay root
# ---------------------------------------------------------------------------

step "Locating overlay root"

find_overlay_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/profiles/repo_name" ]] && { echo "$dir"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

OVERLAY_ROOT=""
[[ -n "${GITHUB_WORKSPACE:-}" && -f "$GITHUB_WORKSPACE/profiles/repo_name" ]] && \
    OVERLAY_ROOT="$GITHUB_WORKSPACE"
if [[ -z "$OVERLAY_ROOT" ]]; then
    OVERLAY_ROOT=$(find_overlay_root "$PWD") || die "Could not locate overlay root"
fi
[[ -n "$OVERLAY_ROOT" ]] || die "Could not locate overlay root"

REPO_NAME=$(cat "$OVERLAY_ROOT/profiles/repo_name")
echo "Overlay: $OVERLAY_ROOT ($REPO_NAME)"

# ---------------------------------------------------------------------------
# Register overlay with portage
# ---------------------------------------------------------------------------
#
# `ebuild` operates on a file path and `pkgcheck` auto-detects the repo from
# profiles/repo_name, but `emerge` (used in step 4/5) requires the overlay to
# be declared in /etc/portage/repos.conf. The CI container ships only the
# default `gentoo` repo, so write a repos.conf entry for this overlay before
# any emerge invocation. Skipped silently on hosts without /etc/portage
# (e.g. non-Gentoo dev machines running pkgcheck-only checks).

if [[ -d /etc/portage ]]; then
    step "Registering overlay $REPO_NAME with portage"
    REPOS_CONF_DIR=/etc/portage/repos.conf
    mkdir -p "$REPOS_CONF_DIR"
    REPOS_CONF_FILE="$REPOS_CONF_DIR/${REPO_NAME}.conf"
    cat > "$REPOS_CONF_FILE" <<EOF
[${REPO_NAME}]
location = ${OVERLAY_ROOT}
auto-sync = no
EOF
    echo "Wrote $REPOS_CONF_FILE"
fi

# ---------------------------------------------------------------------------
# Locate ebuild
# ---------------------------------------------------------------------------

step "Locating ebuild for $ATOM"

PKG_DIR="$OVERLAY_ROOT/$CATEGORY/$NAME"
[[ -d "$PKG_DIR" ]] || die "Package directory not found: $PKG_DIR"

if [[ -n "$VERSION" ]]; then
    EBUILD_FILE="$PKG_DIR/$NAME-$VERSION.ebuild"
    [[ -f "$EBUILD_FILE" ]] || die "Ebuild not found: $EBUILD_FILE"
else
    EBUILD_FILE="$(ls "$PKG_DIR"/*.ebuild 2>/dev/null | sort -V | tail -n 1)"
    [[ -n "$EBUILD_FILE" ]] || die "No ebuilds found in $PKG_DIR"
fi

echo "Ebuild: $EBUILD_FILE"

# ---------------------------------------------------------------------------
# 1/5: Manifest
# ---------------------------------------------------------------------------

step "1/5: Regenerating Manifest (pkgdev manifest)"

(cd "$PKG_DIR" && pkgdev manifest)
echo "Manifest: OK"

# ---------------------------------------------------------------------------
# 2/5: pkgcheck QA scan
# ---------------------------------------------------------------------------

step "2/5: pkgcheck QA scan"

# Run from overlay root so pkgcheck resolves the repo correctly.
# Any finding (warning or error) is treated as a failure.
PKGCHECK_EXIT=0
(cd "$OVERLAY_ROOT" && pkgcheck scan "$CATEGORY/$NAME") || PKGCHECK_EXIT=$?
[[ $PKGCHECK_EXIT -eq 0 ]] || die "pkgcheck found issues in $ATOM"

echo "pkgcheck: OK (no issues)"

# ---------------------------------------------------------------------------
# 3/5: Fetch
# ---------------------------------------------------------------------------

step "3/5: Fetching distfiles (ebuild clean fetch)"

FETCH_LOG=$(mktemp /tmp/verify-fetch-XXXXXX.log)
FETCH_EXIT=0
ebuild "$EBUILD_FILE" clean fetch >"$FETCH_LOG" 2>&1 || FETCH_EXIT=$?

if [[ $FETCH_EXIT -ne 0 ]]; then
    echo "fetch: FAILED — last 50 lines of log:"
    tail -50 "$FETCH_LOG"
    rm -f "$FETCH_LOG"
    die "ebuild fetch failed"
fi

rm -f "$FETCH_LOG"
echo "fetch: OK"

# ---------------------------------------------------------------------------
# 4/5: Install declared build dependencies
# ---------------------------------------------------------------------------

step "4/5: Installing build dependencies (emerge --onlydeps)"
echo "Note: installs DEPEND/BDEPEND packages so pkg-config and headers are available."

EBUILD_BASENAME=$(basename "$EBUILD_FILE" .ebuild)
PV="${EBUILD_BASENAME#${NAME}-}"

emerge --onlydeps --quiet-build "=${CATEGORY}/${NAME}-${PV}::${REPO_NAME}" || \
    die "emerge --onlydeps failed — check DEPEND/BDEPEND declarations"

echo "deps: OK"

# ---------------------------------------------------------------------------
# 5/5: Build through install phase
# ---------------------------------------------------------------------------

step "5/5: Building through install phase (unpack prepare configure compile install)"
echo "Note: 'install' writes to staging \${D} only — live filesystem is never touched."

ebuild "$EBUILD_FILE" unpack prepare configure compile install || \
    die "ebuild build failed"

echo "build: OK"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "========================================"
echo " Overall: PASS  ($ATOM)"
echo "========================================"
