#!/usr/bin/bash
# Fill packaging/arch/PKGBUILD's sha256sums from the exact release tarball.
#   tools/update-pkgbuild.sh dist/aetheros-dotfiles-<version>.tar.gz [output-PKGBUILD]
# Verifies the tarball's name matches the PKGBUILD's version first.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
tarball="${1:?usage: $0 <tarball> [output]}"
out="${2:-$REPO_DIR/packaging/arch/PKGBUILD}"
ver="$(sed -n "s/^_upstreamver=//p" "$REPO_DIR/packaging/arch/PKGBUILD")"
[ "$(basename "$tarball")" = "aetheros-dotfiles-$ver.tar.gz" ] || { echo "tarball $(basename "$tarball") doesn't match _upstreamver=$ver" >&2; exit 1; }
sum="$(sha256sum "$tarball" | cut -d' ' -f1)"
sed "s/^sha256sums=.*/sha256sums=('$sum')/" "$REPO_DIR/packaging/arch/PKGBUILD" > "$out.tmp"
mv "$out.tmp" "$out"
echo "sha256sums=('$sum') -> $out"
