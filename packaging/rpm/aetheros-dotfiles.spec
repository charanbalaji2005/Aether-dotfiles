Name:           aetheros-dotfiles
Version:        0.1.0
Release:        1%{?dist}
Summary:        AetherOS Hyprland dotfiles and Quickshell desktop shell

License:        GPL-3.0-or-later
URL:            https://github.com/example/aetheros-dotfiles
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
* Sat Aug 22 2026 AetherOS Project <noreply@example.invalid> - 0.1.0-1
- Initial packaging: Hyprland config, Aether Shell, terminal/shell config,
  install/backup/restore/uninstall scripts.
