#!/usr/bin/bash
# Builds a versioned source tarball for a generic/manual install — the one
# packaging format with no distro-specific package manager involved, so
# it's the one most likely to actually work everywhere.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null || echo "dev")}"
OUT_DIR="$REPO_DIR/dist"
ARCHIVE_NAME="aetheros-dotfiles-${VERSION}.tar.gz"

mkdir -p "$OUT_DIR"

echo "Building $ARCHIVE_NAME..."
tar -czf "$OUT_DIR/$ARCHIVE_NAME" \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='*.bak.*' \
    -C "$(dirname "$REPO_DIR")" \
    "$(basename "$REPO_DIR")"

echo "Built: $OUT_DIR/$ARCHIVE_NAME"
echo "Size: $(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1)"
sha256sum "$OUT_DIR/$ARCHIVE_NAME" > "$OUT_DIR/$ARCHIVE_NAME.sha256"
echo "Checksum: $OUT_DIR/$ARCHIVE_NAME.sha256"
