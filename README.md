# Z - Unified Shell Tools

A modular command-line tool for managing your shell environment across machines.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/stevemurr/z/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/stevemurr/z.git ~/.local/share/z
echo 'source ~/.local/share/z/z.plugin.zsh' >> ~/.zshrc
source ~/.zshrc
```

## Quick Start

```bash
z                              # Show overview and status
z modules                      # List available modules

# Environment variables
z env add API_KEY "your-key" -s   # Add secret env var
z env list                        # List all env vars
z env rm API_KEY                  # Remove env var

# PATH management
z path add golang "$HOME/go/bin"  # Add path entry
z path list                       # List all paths
z path rm golang                  # Remove path

# Aliases
z alias add k kubectl             # Add alias
z alias list                      # List all aliases

# Multi-machine (requires Tailscale/SSH)
z sys init                        # Configure this machine
z sys add work server.example.com # Add remote machine
z env list -m work                # List env from remote
```

## Modules

| Module | Description |
|--------|-------------|
| `env` | Environment variable management |
| `path` | PATH directory management |
| `alias` | Shell alias management |
| `app` | Application/binary management |
| `bench` | Shell startup benchmarking |
| `sys` | Multi-machine sync and system utilities |
| `term` | Remote terminal session management |
| `web` | Browser-based terminal access |
| `modules` | Module discovery and management |

Enable/disable modules:

```bash
z enable term      # Enable the term module
z disable bench    # Disable the bench module
```

## Data Storage

Z stores data in `~/.z/`:

```
~/.z/
├── config.zsh      # Module configuration
├── env/            # Environment variables
├── path/           # PATH entries
├── alias/          # Aliases
├── app/            # Managed applications
└── sys/            # Machine configurations
```

**Note:** The `~/.z/` directory may contain sensitive data (API keys, etc). Do not commit it to version control.

## Web Terminal (z-web)

For browser-based terminal access, see [z-web/README.md](z-web/README.md).

```bash
cd z-web && make install   # Build and install z-web
z web start                # Start web terminal server
```

## Requirements

- zsh
- git
- (optional) Tailscale or SSH for multi-machine features

## License

MIT
