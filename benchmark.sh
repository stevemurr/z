#!/bin/bash
# Benchmark ZSH startup time

echo "=== ZSH Startup Time Benchmark ==="
echo ""

# Test current config
echo "Current .zshrc:"
time zsh -i -c exit

echo ""
echo "New modular config:"
ZDOTDIR=$HOME/.config/zsh time zsh -i -c exit

echo ""
echo "Detailed timing (new config):"
zsh -i -c 'zmodload zsh/zprof && source ~/.config/zsh/init.zsh && zprof | head -20'