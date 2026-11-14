#!/usr/bin/bash
# Builds the RPM from the release tarball with rpmbuild, inspects it, and
# runs rpmlint. On non-RPM hosts the build-dependency check is skipped
# (--nodeps: the host's rpm database is empty); everything else is a real
# build. Fedora-inapplicable rpmlint checks (Group/Packager tags, SPDX
# licence list, signatures, dictionary spelling) are filtered and reported.
set -uo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "SKIPPED: rpmbuild not installed (sudo dnf install rpm-build rpmlint)"
    exit 0
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
SOURCE_DATE_EPOCH=1700000000 bash "$REPO_DIR/packaging/tarball/build-tarball.sh" >/dev/null || fail "tarball"
mkdir -p "$T/SOURCES" "$T/SPECS"
cp "$REPO_DIR"/dist/aetheros-dotfiles-*.tar.gz "$T/SOURCES/"
cp "$REPO_DIR/packaging/rpm/aetheros-dotfiles.spec" "$T/SPECS/"
nodeps=""
rpm -q rpm >/dev/null 2>&1 || nodeps="--nodeps"
rpmbuild --define "_topdir $T" $nodeps -ba "$T/SPECS/aetheros-dotfiles.spec" > "$T/build.log" 2>&1 || { tail -20 "$T/build.log"; fail "rpmbuild"; }
rpm_file="$(ls "$T"/RPMS/noarch/*.rpm)"
echo "PASS: rpmbuild produced $(basename "$rpm_file")${nodeps:+ (build-deps not checked: non-RPM host)}"
# Quickshell is optional (classic is the default interface): Suggests, not Requires.
rpm -qp --suggests "$rpm_file" | grep -q '^quickshell >= 0.2.0$' || fail "missing Suggests: quickshell >= 0.2.0"
rpm -qpR "$rpm_file" | grep -q '^quickshell' && fail "quickshell must not be a hard Requires"
[ "$(rpm -qpl "$rpm_file" | grep -c -E '/tests/|/packaging/')" -eq 0 ] || fail "development files shipped"
rpm -qplv "$rpm_file" | grep -E '/usr/share/aetheros-dotfiles/scripts/setup-symlinks.sh$' | grep -q '^-rwxr-xr-x' || fail "entry point not executable"
echo "PASS: requires, contents and modes as expected"
if command -v rpmlint >/dev/null 2>&1; then
    errors="$(rpmlint "$rpm_file" 2>&1 | grep -E ': E: ' | grep -vE 'no-group-tag|no-packager-tag|no-signature|invalid-license|spelling-error' || true)"
    [ -z "$errors" ] || { echo "$errors"; fail "rpmlint errors"; }
    echo "PASS: rpmlint — no errors after filtering Fedora-inapplicable checks"
else
    echo "NOTE: rpmlint not installed; lint not run"
fi
