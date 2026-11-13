# shellcheck shell=bash
# ULTRON RECOVERY — shells: zsh, bash, tmux configs (syntax), links into the
# dotfiles repo, the login shell, aether-terminal's default shell.

mod_shell_paths() {
    printf '%s\n' "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bashrc.d/aether.bash" "$HOME/.config/tmux" "$HOME/.config/aether-shell/terminal/shell"
}
mod_shell_deps() { printf '%s\n' "zsh:zsh" "bash:bash" "tmux:tmux" "fzf:fzf"; }

mod_shell_check() {
    local p0=${#UR_PROBLEMS[@]} out login f
    for f in "$HOME/.zshrc" "$HOME/.bashrc.d/aether.bash"; do
        if [ -L "$f" ] && [ ! -e "$f" ]; then problem shell "broken link ${f/#$HOME/\~} → $(readlink "$f")"; fi
    done
    if [ -f "$HOME/.zshrc" ]; then
        command -v zsh >/dev/null 2>&1 && { out="$(zsh -n "$HOME/.zshrc" 2>&1)" || problem shell "~/.zshrc syntax error: $(head -1 <<< "$out")"; }
    elif [ ! -L "$HOME/.zshrc" ]; then problem shell "~/.zshrc is missing"; fi
    if [ -f "$HOME/.bashrc" ]; then
        out="$(bash -n "$HOME/.bashrc" 2>&1)" || problem shell "~/.bashrc syntax error: $(head -1 <<< "$out")"
    else problem shell "~/.bashrc is missing"; fi
    [ -f "$HOME/.bashrc.d/aether.bash" ] && { out="$(bash -n "$HOME/.bashrc.d/aether.bash" 2>&1)" || problem shell "aether.bash syntax error: $(head -1 <<< "$out")"; }
    if [ -f "$HOME/.config/tmux/tmux.conf" ] && command -v tmux >/dev/null 2>&1; then
        out="$(tmux -L ultron-check -f "$HOME/.config/tmux/tmux.conf" new-session -d -s check 2>&1)"; local rc=$?
        tmux -L ultron-check kill-server >/dev/null 2>&1
        [ "$rc" = 0 ] || problem shell "tmux.conf error: $(head -1 <<< "$out")"
    fi
    if [ -L "$HOME/.config/tmux" ] && [ ! -e "$HOME/.config/tmux" ]; then problem shell "broken link ~/.config/tmux"; fi
    login="$(getent passwd "$(id -un)" | cut -d: -f7)"
    [ -x "$login" ] || problem shell "login shell $login does not exist"
    grep -qx "$login" /etc/shells 2>/dev/null || problem shell "login shell $login is not listed in /etc/shells"
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Shells: zsh, bash, tmux configs valid; login shell $login"
    return 0
}

mod_shell_repair() {
    repair_link "$HOME/.zshrc" config/zsh/.zshrc
    repair_link "$HOME/.config/tmux" config/tmux
    [ -d "$HOME/.bashrc.d" ] || [ ! -e "${UR_REPO:-/nonexistent}/config/bash/aether.bash" ] || change "create ~/.bashrc.d" mkdir -p "$HOME/.bashrc.d"
    repair_link "$HOME/.bashrc.d/aether.bash" config/bash/aether.bash
    repair_deleted_tracked config/zsh
    repair_deleted_tracked config/tmux
    repair_deleted_tracked config/bash
    if [ ! -e "$HOME/.bashrc" ] && [ -f /etc/skel/.bashrc ]; then
        change "restore ~/.bashrc from Fedora's default (/etc/skel)" cp /etc/skel/.bashrc "$HOME/.bashrc"
    fi
    repair_full_restore shell config/zsh config/tmux config/bash
    local login; login="$(getent passwd "$(id -un)" | cut -d: -f7)"
    if [ ! -x "$login" ] || ! grep -qx "$login" /etc/shells 2>/dev/null; then
        ui_info "Fix the login shell yourself (needs your password): chsh -s /usr/bin/zsh"
    fi
}
