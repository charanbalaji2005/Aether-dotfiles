# Publishing checklist (maintainers)

1. **Repository links** — `tools/set-repo-url.sh <user>/<repo>`, review `git diff`, commit.
2. **Identity** — check `LICENSE`, `THIRD_PARTY.md` and the copyright line in README.
3. **Generated files** — `python3 tools/gen_schema.py && python3 tools/gen_cli_reference.py`.
4. **Tests** — `bash tests/run-all.sh` as a normal user, with PySide6 + Xvfb installed, all green.
5. **Hardware** — work through [docs/HARDWARE.md](docs/HARDWARE.md#validation-checklist-needed-before-calling-a-release-100);
   record results in TEST_REPORT.md. Until every row passes, publish as a pre-release
   (`v1.0.0-rc.N`).
6. **Version** — `lib/aether/__init__.py` `__version__`, `packaging/rpm/*.spec` (Version/Release),
   `packaging/arch/PKGBUILD` (pkgver), CHANGELOG heading.
7. **Screenshots** — take real ones on your desktop (`SUPER+SHIFT+S`) for the README; don't use
   mockups.
8. **Tag** — `git tag -s v1.0.0-rc.1 && git push --tags`. The release workflow re-runs the tests,
   checks the tag matches `__version__`, and publishes a tarball + SHA-256 with the CHANGELOG
   section (tags containing `-` are marked pre-release).
9. **Security contact** — enable private vulnerability reporting in the repository settings
   (SECURITY.md and the issue template point there).
