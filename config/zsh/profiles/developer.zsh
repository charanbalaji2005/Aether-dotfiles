# AetherOS zsh profile: developer — fuzzy history/file search, smarter cd,
# and a few git helpers. Each tool is used only if it is installed
# (fzf, zoxide are in the "complete" install mode).

if command -v fzf >/dev/null 2>&1; then
    # Fedora's fzf ships its zsh integration here.
    for f in /usr/share/fzf/shell/key-bindings.zsh /usr/share/doc/fzf/examples/key-bindings.zsh; do
        [ -f "$f" ] && source "$f" && break
    done
fi
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

alias gd='git diff'
alias gds='git diff --staged'
alias gsw='git switch'
alias gb='git branch --sort=-committerdate | head -20'
# Jump to the root of the current git repository.
groot() { cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; }
