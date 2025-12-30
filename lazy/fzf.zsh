#!/usr/bin/env zsh
# FZF configuration and setup

# Check if fzf is installed
if ! command -v fzf &> /dev/null; then
    return 0
fi

# Get fzf installation path dynamically
local fzf_base
if command -v brew &> /dev/null; then
    fzf_base="$(brew --prefix fzf 2>/dev/null)/shell"
fi

# Source completion script
if [[ -n "${fzf_base}" && -f "${fzf_base}/completion.zsh" ]]; then
    source "${fzf_base}/completion.zsh"
fi

# Source key bindings
# CTRL-T - Paste the selected file path(s) into the command line
# CTRL-R - Paste the selected command from history into the command line
# ALT-C  - cd into the selected directory
if [[ -n "${fzf_base}" && -f "${fzf_base}/key-bindings.zsh" ]]; then
    source "${fzf_base}/key-bindings.zsh"
fi

# FZF default options
export FZF_DEFAULT_OPTS='
    --height 40%
    --layout=reverse
    --border
    --inline-info
    --color=dark
    --color=fg:-1,bg:-1,hl:#5fff87,fg+:-1,bg+:-1,hl+:#ffaf5f
    --color=info:#af87ff,prompt:#5fff87,pointer:#af5fff,marker:#ff87d7,spinner:#ff87d7
'

# Use fd instead of find if available (faster)
if command -v fd &> /dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# Preview file content using bat if available, otherwise use cat
if command -v bat &> /dev/null; then
    export FZF_CTRL_T_OPTS="
        --preview 'bat --color=always --style=numbers --line-range=:500 {}'
        --preview-window=right:60%:wrap"
else
    export FZF_CTRL_T_OPTS="
        --preview 'cat {}'
        --preview-window=right:60%:wrap"
fi

# Advanced customizations for CTRL-R (history search)
export FZF_CTRL_R_OPTS="
    --preview 'echo {}'
    --preview-window=down:3:hidden:wrap
    --bind '?:toggle-preview'
"
