Name:           aetheros-dotfiles
Version:        1.0.0
Release:        0.1.rc1%{?dist}
Summary:        AetherOS Hyprland dotfiles and Quickshell desktop shell

License:        GPL-3.0-or-later
URL:            https://github.com/OWNER/aetheros-dotfiles
Source0:        %{name}.tar.gz
# Source0 intentionally has no real upstream URL yet — this repo hasn't
# been published to a specific location. Update both URL and Source0 once
# it has a real home; rpmlint will flag this until then, correctly.
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Group:          Applications/System
Packager:       Charan Balaji <noreply@example.invalid>

BuildArch:      noarch

Requires:       hyprland
Requires:       kitty
Requires:       zsh
Requires:       python3
Recommends:     pciutils
Recommends:     hwdata
Recommends:     mokutil

%description
AetherOS dotfiles: Hyprland configuration, the AetherOS Shell (Quickshell),
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
%setup -q -n aetheros-dotfiles

%build
# Nothing to compile — this package is configuration files and shell
# scripts, installed as-is.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_datadir}/%{name}
cp -a . %{buildroot}%{_datadir}/%{name}/
rm -rf %{buildroot}%{_datadir}/%{name}/.git
rm -rf %{buildroot}%{_datadir}/%{name}/.github
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
* Wed Nov 11 2026 AetherOS Project <noreply@example.invalid> - 1.0.0-0.1.rc1
- 1.0 release candidate: NVML telemetry, GPU-pressure policy, assistant, widgets, Island 2.0,
  28 settings sections, custom themes, displays with auto-revert. See CHANGELOG.md.

* Wed Nov 11 2026 AetherOS Project <noreply@example.invalid> - 0.3.0-1
- Installer lifecycle (check/dry-run/install/update/uninstall/rollback), snapshots, recovery,
  safe-mode unit, animation/graphics engine, dock, island, overview, system centre, layouts,
  automation, profiles, palettes, wallpaper engine, lock screen hardening. See CHANGELOG.md.

* Mon Nov 09 2026 AetherOS Project <noreply@example.invalid> - 0.2.0-1
- aether CLI backend (lib/aether): hardware detection, graphics/NVIDIA
  management, telemetry, performance profiles, diagnostics, repair.
- Shell: control centre, system dashboard, launcher favourites/recents,
  notification grouping, OSD, design system with light theme.

* Sat Aug 22 2026 AetherOS Project <noreply@example.invalid> - 0.1.0-1
- Initial packaging: Hyprland config, Aether Shell, terminal/shell config,
  install/backup/restore/uninstall scripts.
