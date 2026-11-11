# AetherOS zsh profile: power — the developer profile plus a Starship
# prompt (if installed), a system summary on new terminals (fastfetch, at
# most once per hour so splits stay fast), and extra history settings.

source "${0:A:h}/developer.zsh"

setopt HIST_REDUCE_BLANKS EXTENDED_HISTORY
HISTSIZE=50000
SAVEHIST=50000

command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

if command -v fastfetch >/dev/null 2>&1 && [[ -o interactive ]]; then
    _aether_ff="${XDG_RUNTIME_DIR:-/tmp}/aether-fastfetch-stamp"
    if [ ! -f "$_aether_ff" ] || [ -n "$(find "$_aether_ff" -mmin +60 2>/dev/null)" ]; then
        fastfetch && touch "$_aether_ff"
    fi
    unset _aether_ff
fi
