#!/usr/bin/env zsh
# Optional Oh My Zsh loader - can be sourced manually if needed

# Load Oh My Zsh
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
    plugins=(git)
    source "$ZSH/oh-my-zsh.sh"
fi