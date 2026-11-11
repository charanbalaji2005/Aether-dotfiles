#!/usr/bin/bash
# Builds the release source tarball, reproducibly:
#   dist/aetheros-dotfiles-<version>.tar.gz   (top directory aetheros-dotfiles-<version>/)
#   dist/aetheros-dotfiles-<version>.tar.gz.sha256
#
# <version> defaults to lib/aether's __version__ (e.g. 1.0.0-rc.2). The same
# tree and SOURCE_DATE_EPOCH always produce the same bytes (sorted entries,
# fixed mtimes, numeric root ownership, gzip without a timestamp), so the
# checksum in the Arch PKGBUILD can be verified independently.
# Excluded: .git, dist/, caches, and packaging/arch/PKGBUILD itself (it
# carries this tarball's checksum, so it can't be inside it).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
VERSION="${1:-$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import aether; print(aether.__version__)' "$REPO_DIR/lib")}"
NAME="aetheros-dotfiles-$VERSION"
OUT_DIR="$REPO_DIR/dist"
EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$REPO_DIR" log -1 --format=%ct 2>/dev/null || echo 0)}"

mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(cd "$REPO_DIR" && find . \( -path ./.git -o -path ./dist -o -name __pycache__ -o -name '*.pyc' \) -prune -o \
    \( -type f -o -type l \) ! -path ./packaging/arch/PKGBUILD -print | sed 's|^\./||' | LC_ALL=C sort) > "$tmp/files"
tar -C "$REPO_DIR" --no-recursion -T "$tmp/files" \
    --transform "s,^,$NAME/," --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
    --format=gnu -cf - | gzip -9n > "$OUT_DIR/$NAME.tar.gz"
(cd "$OUT_DIR" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
echo "Built: $OUT_DIR/$NAME.tar.gz ($(du -h "$OUT_DIR/$NAME.tar.gz" | cut -f1))"
cat "$OUT_DIR/$NAME.tar.gz.sha256"
