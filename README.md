# Modular ZSH Configuration

## Security Note

The `~/.z/` data directory contains sensitive information including:
- Environment variables (may contain API keys marked as secrets)
- Machine configurations with hostnames
- Custom paths and aliases

**Never commit `~/.z/` to version control.** This directory is intentionally stored outside this repo.

## Structure

```
~/.config/zsh/
├── core/           # Essential configs loaded on every shell
│   ├── env.zsh     # Environment variables
│   ├── paths.zsh   # PATH exports
│   └── aliases.zsh # Command aliases
├── functions/      # Function definitions (autoloaded)
│   ├── file.zsh    # File management (fman, fm, ftext)
│   ├── process.zsh # Process management (fproc, fnet)
│   ├── search.zsh  # Search functions (tgrep, rg_fzf)
│   ├── docker.zsh  # Docker utilities
│   ├── system.zsh  # System utilities (fbrew, fcleanup)
│   └── utils.zsh   # Misc utilities (fnotes, fmusic)
├── lazy/           # Lazy-loaded components
│   ├── conda.zsh   # Conda (loads on first use)
│   └── omz.zsh     # Oh My Zsh (optional)
└── init.zsh        # Main loader
```

## Installation

1. The modular config is already set up in `~/.config/zsh/`
2. To activate it, replace your `.zshrc`:
   ```bash
   mv ~/.zshrc.new ~/.zshrc
   ```

3. To revert to the original:
   ```bash
   cp ~/.zshrc.backup.* ~/.zshrc
   ```

## Performance Improvements

1. **Lazy Conda**: Conda only initializes when you first use it
2. **Optional OMZ**: Oh My Zsh is now optional (commented out by default)
3. **Modular Functions**: Functions are organized by category
4. **Cleaner PATH**: Consolidated PATH exports in one file

## Testing

Run the benchmark script to compare startup times:
```bash
~/.config/zsh/benchmark.sh
```

## Customization

- Add new functions to the appropriate file in `functions/`
- Machine-specific settings go in `~/.zshrc`
- To enable Oh My Zsh, uncomment the line in `init.zsh`
- To disable lazy conda, comment out the source line in `init.zsh`