#!/usr/bin/bash
# Release source tarball and Arch PKGBUILD:
#  * the tarball is reproducible (same tree + SOURCE_DATE_EPOCH → same bytes)
#    and named/rooted exactly as the RPM spec and PKGBUILD expect;
#  * tools/update-pkgbuild.sh fills a checksum that matches the tarball;
#  * the PKGBUILD's package() function, run with bash against the real
#    tarball, produces the expected tree.
# Not covered: makepkg/namcap on Arch (see TEST_REPORT.md).
set -uo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ver="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import aether; print(aether.__version__)' "$REPO_DIR/lib")"
name="aetheros-dotfiles-$ver"

SOURCE_DATE_EPOCH=1700000000 bash "$REPO_DIR/packaging/tarball/build-tarball.sh" >/dev/null || fail "tarball build"
cp "$REPO_DIR/dist/$name.tar.gz" "$T/a.tgz"
SOURCE_DATE_EPOCH=1700000000 bash "$REPO_DIR/packaging/tarball/build-tarball.sh" >/dev/null
cmp -s "$T/a.tgz" "$REPO_DIR/dist/$name.tar.gz" || fail "tarball is not reproducible"
echo "PASS: tarball $name.tar.gz is reproducible"
top="$(tar -tzf "$T/a.tgz" | cut -d/ -f1 | sort -u)"
[ "$top" = "$name" ] || fail "tarball top directory is '$top', expected $name"
tar -tzf "$T/a.tgz" | grep -q 'packaging/arch/PKGBUILD' && fail "PKGBUILD must not be inside the tarball (it carries its checksum)"
echo "PASS: one top directory ($name), PKGBUILD excluded"

spec="$REPO_DIR/packaging/rpm/aetheros-dotfiles.spec"
uv="$(sed -n 's/^%global upstream_version //p' "$spec")"
[ "$uv" = "$ver" ] || fail "spec upstream_version $uv != $ver"
grep -q '^Source0:.*/%{name}-%{upstream_version}.tar.gz$' "$spec" || fail "spec Source0 doesn't name the tarball builder's output"
grep -q '^%setup -q -n %{name}-%{upstream_version}$' "$spec" || fail "spec %setup directory doesn't match the tarball"
echo "PASS: RPM spec Source0 and %setup match the tarball ($uv)"

pv="$(sed -n 's/^_upstreamver=//p' "$REPO_DIR/packaging/arch/PKGBUILD")"
[ "$pv" = "$ver" ] || fail "PKGBUILD _upstreamver $pv != $ver"
grep -q "^sha256sums=('SKIP')" "$REPO_DIR/packaging/arch/PKGBUILD" && fail "PKGBUILD skips checksum verification"
bash "$REPO_DIR/tools/update-pkgbuild.sh" "$REPO_DIR/dist/$name.tar.gz" "$T/PKGBUILD" >/dev/null || fail "update-pkgbuild.sh"
(
    cd "$T" || exit 1
    # shellcheck disable=SC1091
    source ./PKGBUILD
    # shellcheck disable=SC2154  # sha256sums comes from the PKGBUILD
    [ "${sha256sums[0]}" = "$(sha256sum "$REPO_DIR/dist/$name.tar.gz" | cut -d' ' -f1)" ] || { echo "FAIL: PKGBUILD checksum doesn't match"; exit 1; }
    srcdir="$T/src"; pkgdir="$T/pkg"; mkdir -p "$srcdir" "$pkgdir"
    tar -xzf "$REPO_DIR/dist/$name.tar.gz" -C "$srcdir"
    package || { echo "FAIL: package() failed"; exit 1; }
    for b in aether aetheros-dotfiles-setup aetheros-dotfiles-doctor; do
        [ "$(readlink "$pkgdir/usr/bin/$b")" != "" ] || { echo "FAIL: /usr/bin/$b missing"; exit 1; }
    done
    [ -x "$pkgdir/usr/share/aetheros-dotfiles/scripts/setup-symlinks.sh" ] || { echo "FAIL: entry point not executable"; exit 1; }
    [ ! -e "$pkgdir/usr/share/aetheros-dotfiles/tests" ] || { echo "FAIL: tests shipped"; exit 1; }
    [ -f "$pkgdir/usr/share/licenses/aetheros-dotfiles/LICENSE" ] || { echo "FAIL: license missing"; exit 1; }
    HOME="$T/home" "$pkgdir/usr/share/aetheros-dotfiles/scripts/bin/aether" --version | grep -q "aether $ver" || { echo "FAIL: packaged aether doesn't run"; exit 1; }
) || exit 1
echo "PASS: PKGBUILD checksum matches; package() builds the expected tree; packaged aether runs"
