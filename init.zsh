#!/usr/bin/env zsh
# Main ZSH configuration loader

# Base directory for modular config
ZSH_CONFIG_DIR="${HOME}/.config/zsh"

# Load core configurations (always needed)
source "${ZSH_CONFIG_DIR}/core/env.zsh"
source "${ZSH_CONFIG_DIR}/core/paths.zsh"
source "${ZSH_CONFIG_DIR}/core/aliases.zsh"

# Load Z plugin (unified shell tools)
source "${ZSH_CONFIG_DIR}/plugins/z/z.plugin.zsh"

# Load utility functions
for func_file in "${ZSH_CONFIG_DIR}"/functions/*.zsh; do
    source "$func_file"
done

# Load lazy configurations
source "${ZSH_CONFIG_DIR}/lazy/conda.zsh"
source "${ZSH_CONFIG_DIR}/lazy/fzf.zsh"

# Optional: Load Oh My Zsh (comment out for faster startup)
source "${ZSH_CONFIG_DIR}/lazy/omz.zsh"

# Optional: Add timing information during development
# zmodload zsh/zprof  # Enable profiling
# At the end of .zshrc, add: zprof  # Show profiling results