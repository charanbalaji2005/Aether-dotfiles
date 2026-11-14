# AetherOS bash — the zsh setup's prompt, history and aliases for bash.
# Linked to ~/.bashrc.d/aether.bash by setup-symlinks.sh; Fedora's default
# ~/.bashrc sources every file in ~/.bashrc.d, so your ~/.bashrc is untouched.
# Only for interactive shells.
[[ $- == *i* ]] || return 0

# ── history ─────────────────────────────────────────────────────────────
HISTFILE="$HOME/.bash_history"
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize globstar autocd cdspell 2>/dev/null
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# ── environment (as in .zshrc) ──────────────────────────────────────────
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"
export TERMINAL="aether-terminal"
export BROWSER="${BROWSER:-firefox}"

# ── aliases (as in .zshrc) ──────────────────────────────────────────────
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza --icons --group-directories-first -l'
    alias la='eza --icons --group-directories-first -la'
    alias lt='eza --icons --group-directories-first --tree'
else
    alias ll='ls -lh'
    alias la='ls -lAh'
fi
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -p'
alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -20'
alias gco='git checkout'
alias hyprreload='hyprctl reload'

# ── completion and fzf ──────────────────────────────────────────────────
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
[ -f /usr/share/fzf/shell/key-bindings.bash ] && . /usr/share/fzf/shell/key-bindings.bash
bind 'set completion-ignore-case on' 2>/dev/null
bind 'set show-all-if-ambiguous on' 2>/dev/null

# ── prompt: the zsh one — path (git branch), then ❯ (red after an error) ─
__aether_prompt() {
    local code=$? branch=""
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)"
    PS1="\[\e[34m\]\w\[\e[0m\]${branch:+ \[\e[35m\](${branch})\[\e[0m\]}\n"
    if [ "$code" -eq 0 ]; then PS1+="\[\e[36m\]❯\[\e[0m\] "; else PS1+="\[\e[31m\]❯\[\e[0m\] "; fi
}
PROMPT_COMMAND="__aether_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
