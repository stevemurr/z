# z-web

Browser-based terminal access for z term sessions. Access your terminal from any device over Tailscale.

## Quick Start

```bash
# Build everything
make build

# Install to ~/.z/bin
make install

# Start the server
z web start

# Open in browser
z web open
```

## Development

```bash
# Install dependencies
make deps

# Run frontend dev server (with hot reload)
make dev-frontend

# Run backend (in another terminal)
make dev-backend

# Or run both together
make dev
```

## Architecture

- **Frontend**: TypeScript + xterm.js + Vite
- **Backend**: Go with WebSocket support
- **Transport**: WebSocket for terminal I/O

## Commands

```bash
z web start              # Start server on Tailscale IP
z web start -p 8080      # Use custom port
z web start --host localhost  # Bind to localhost only
z web stop               # Stop server
z web status             # Show server status
z web open               # Open in browser
z web logs               # Tail server logs
```

## Security

No authentication - relies on Tailscale for network-level security. The server binds to your Tailscale IP by default, so it's only accessible from your tailnet.
