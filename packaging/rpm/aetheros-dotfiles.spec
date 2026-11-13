# Upstream versions like 1.0.0-rc.2 map to RPM Version 1.0.0 with a
# pre-release Release (0.N.rcN), so 1.0.0-1 later sorts after every RC.
%global upstream_version 1.0.0-rc.2

Name:           aetheros-dotfiles
Version:        1.0.0
Release:        0.2.rc2%{?dist}
Summary:        AetherOS desktop for Hyprland: Quickshell shell, configuration and tools

License:        GPL-3.0-or-later
URL:            https://github.com/OWNER/aetheros-dotfiles
Source0:        %{url}/releases/download/v%{upstream_version}/%{name}-%{upstream_version}.tar.gz

BuildArch:      noarch
BuildRequires:  python3

Requires:       hyprland
Requires:       python3 >= 3.9
Requires:       kitty
Requires:       zsh
Recommends:     hypridle
# Classic interface (the default)
Recommends:     waybar
Recommends:     (rofi-wayland or rofi)
Recommends:     SwayNotificationCenter
Recommends:     hyprlock
Recommends:     swww
Recommends:     cliphist
Recommends:     grim
Recommends:     slurp
# The aether (Quickshell) interface
Suggests:       quickshell >= 0.2.0
Recommends:     pciutils
Recommends:     hwdata
Recommends:     libsecret
Recommends:     power-profiles-daemon

%description
AetherOS dotfiles: Hyprland configuration with two interfaces — "classic"
(Waybar, Rofi, SwayNC, Wlogout, Hyprlock, swww) and the AetherOS Shell (Quickshell),
terminal and shell configuration, install/backup/restore scripts, and
package lists.

This package installs files read-only under %{_datadir}/%{name}.
It does NOT symlink anything into your home directory automatically —
RPM installs are system-wide and shouldn't reach into a specific
user's $HOME as a side effect of package installation. After
installing, run:

    aetheros-dotfiles-setup

as your regular (non-root) user to symlink the configs into place.

%prep
%setup -q -n %{name}-%{upstream_version}

%build
# Nothing to compile — this package is configuration files and shell
# scripts, installed as-is.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_datadir}/%{name}
cp -a . %{buildroot}%{_datadir}/%{name}/
rm -rf %{buildroot}%{_datadir}/%{name}/.git
rm -rf %{buildroot}%{_datadir}/%{name}/.github
# Development-only content: tests, packaging recipes, editor/lint configs.
rm -rf %{buildroot}%{_datadir}/%{name}/tests %{buildroot}%{_datadir}/%{name}/packaging
rm -f %{buildroot}%{_datadir}/%{name}/.editorconfig %{buildroot}%{_datadir}/%{name}/.gitattributes %{buildroot}%{_datadir}/%{name}/.shellcheckrc
find %{buildroot}%{_datadir}/%{name} -name ".gitignore" -delete
find %{buildroot}%{_datadir}/%{name} -name "__pycache__" -type d -prune -exec rm -rf {} +

mkdir -p %{buildroot}%{_bindir}
ln -s ../share/%{name}/scripts/setup-symlinks.sh \
      %{buildroot}%{_bindir}/aetheros-dotfiles-setup
ln -s ../share/%{name}/scripts/doctor.sh \
      %{buildroot}%{_bindir}/aetheros-dotfiles-doctor
ln -s ../share/%{name}/scripts/bin/aether \
      %{buildroot}%{_bindir}/aether
ln -s ../share/%{name}/scripts/bin/aether-screenshot \
      %{buildroot}%{_bindir}/aether-screenshot
ln -s ../share/%{name}/scripts/bin/aether-wallpaper \
      %{buildroot}%{_bindir}/aether-wallpaper
# Entry points must stay executable through the symlinks.
chmod 0755 %{buildroot}%{_datadir}/%{name}/install.sh %{buildroot}%{_datadir}/%{name}/scripts/*.sh %{buildroot}%{_datadir}/%{name}/scripts/bin/*

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_datadir}/%{name}/
%{_bindir}/aetheros-dotfiles-setup
%{_bindir}/aetheros-dotfiles-doctor
%{_bindir}/aether
%{_bindir}/aether-screenshot
%{_bindir}/aether-wallpaper

%changelog
* Wed Nov 11 2026 AetherOS Maintainer <maintainer@REPLACE.ME> - 1.0.0-0.2.rc2
- Release hardening: verified Quickshell API use (0.2.0-0.3.2), PAM start failure
  handling, widget trust model, GPU telemetry fixes, symlinked entry points,
  reproducible source tarball. See CHANGELOG.md.

* Wed Nov 11 2026 AetherOS Maintainer <maintainer@REPLACE.ME> - 1.0.0-0.1.rc1
- 1.0 release candidate: NVML telemetry, GPU-pressure policy, assistant, widgets, Island 2.0,
  28 settings sections, custom themes, displays with auto-revert. See CHANGELOG.md.

* Wed Nov 11 2026 AetherOS Maintainer <maintainer@REPLACE.ME> - 0.3.0-1
- Installer lifecycle (check/dry-run/install/update/uninstall/rollback), snapshots, recovery,
  safe-mode unit, animation/graphics engine, dock, island, overview, system centre, layouts,
  automation, profiles, palettes, wallpaper engine, lock screen hardening. See CHANGELOG.md.

* Mon Nov 09 2026 AetherOS Maintainer <maintainer@REPLACE.ME> - 0.2.0-1
- aether CLI backend (lib/aether): hardware detection, graphics/NVIDIA
  management, telemetry, performance profiles, diagnostics, repair.
- Shell: control centre, system dashboard, launcher favourites/recents,
  notification grouping, OSD, design system with light theme.

* Sat Aug 22 2026 AetherOS Maintainer <maintainer@REPLACE.ME> - 0.1.0-1
- Initial packaging: Hyprland config, Aether Shell, terminal/shell config,
  install/backup/restore/uninstall scripts.
