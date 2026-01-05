# Z Web - Browser-based Terminal Access

## Overview

A web-based terminal interface for accessing `z term` sessions from any device, optimized for mobile. Access your terminal sessions from your phone over Tailscale.

## Goals

1. **Mobile-first**: Usable input on phone keyboards
2. **Session switching**: Quick access to all `z term` sessions
3. **Simple deployment**: Single binary + static files
4. **Tailscale-only**: No authentication layer (network provides security)

## UI Design

### Initial State (No Session)

```
┌─────────────────────────────────┐
│                                 │
│                                 │
│   ┌─────────────────────────┐   │
│   │     agent-work          │   │
│   ├─────────────────────────┤   │
│   │     build-server        │   │
│   ├─────────────────────────┤   │
│   │  +  New Session         │   │
│   └─────────────────────────┘   │
│                                 │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ Select a session...         │ │
│ └─────────────────────────────┘ │
│ [No session ▼]           [+][↑] │
└─────────────────────────────────┘
```

### Active Session

```
┌─────────────────────────────────┐
│ $ npm run dev                   │
│ > myapp@1.0.0 dev               │
│ > vite                          │
│                                 │
│ VITE v5.0.0  ready in 200ms     │
│ ➜  Local: http://localhost:5173 │
│ █                               │
│                                 │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ └─────────────────────────────┘ │
│ [agent-work ▼]           [+][↑] │
└─────────────────────────────────┘
```

### Components

| Element | Behavior |
|---------|----------|
| **Terminal area** | xterm.js, displays tmux session output, scrollable |
| **Input box** | Text input, Enter sends to session, mobile-friendly |
| **Session chip** | Shows current session, tap to open picker |
| **+ button** | Create new session (prompts for name) |
| **↑ button** | Send input (same as Enter key) |

### Session Picker (on chip tap)

```
┌─────────────────────────────┐
│ Sessions                  ✕ │
├─────────────────────────────┤
│ ● agent-work      ~/proj    │
│   build-server    ~/api     │
│   deploy          ~/infra   │
├─────────────────────────────┤
│ + New Session               │
│ ⏏ Detach                    │
└─────────────────────────────┘
```

- Shows all `z term` sessions
- Current session marked with ●
- Shows working directory
- Quick actions: new session, detach

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                          Browser                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  xterm.js (terminal display, disableStdin: true)         │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Input bar + Session picker                               │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────┬──────────────────────────────────────┘
                          │ WebSocket
                          │ - Terminal I/O (binary)
                          │ - Commands (JSON)
                          ▼
┌────────────────────────────────────────────────────────────────┐
│                      z-web server (Go)                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ HTTP Server │  │  WebSocket  │  │   Session Manager       │ │
│  │ (static)    │  │   Handler   │  │   - list sessions       │ │
│  │             │  │             │  │   - attach/detach       │ │
│  │             │  │             │  │   - create/stop         │ │
│  └─────────────┘  └──────┬──────┘  └───────────┬─────────────┘ │
└──────────────────────────┼─────────────────────┼───────────────┘
                           │                     │
                           │ PTY I/O             │ tmux commands
                           ▼                     ▼
                    ┌─────────────────────────────────┐
                    │            tmux                  │
                    │  z-agent-work  z-build  z-xyz   │
                    └─────────────────────────────────┘
```

## Tech Stack

### Frontend
- **TypeScript** - Type safety, good xterm.js support
- **xterm.js** - Terminal emulation
- **xterm-addon-fit** - Responsive terminal sizing
- **Vite** - Build tool, dev server
- **Vanilla CSS** - Simple styling, mobile-first

### Backend
- **Go** - Single binary, no runtime deps
- **gorilla/websocket** - WebSocket handling
- **creack/pty** - PTY allocation for tmux attach
- **embed** - Embed frontend in binary

## WebSocket Protocol

### Message Types

```typescript
// Client → Server
type ClientMessage =
  | { type: 'input', data: string }      // Terminal input
  | { type: 'resize', cols: number, rows: number }
  | { type: 'attach', session: string }  // Attach to session
  | { type: 'detach' }                   // Detach from session
  | { type: 'list' }                     // List sessions
  | { type: 'create', name?: string }    // Create new session
  | { type: 'stop', session: string }    // Stop session

// Server → Client
type ServerMessage =
  | { type: 'output', data: string }     // Terminal output (base64)
  | { type: 'sessions', sessions: Session[] }
  | { type: 'attached', session: string }
  | { type: 'detached' }
  | { type: 'error', message: string }

type Session = {
  name: string
  cwd: string
  command: string
  branch?: string
  activity: number  // Unix timestamp
  clients: number
}
```

### Connection Flow

```
Client                          Server
   │                               │
   │──── connect ─────────────────►│
   │                               │
   │◄─── sessions [...] ──────────│  (auto-send on connect)
   │                               │
   │──── attach "agent-work" ────►│
   │                               │
   │◄─── attached "agent-work" ───│
   │◄─── output "$ ..." ──────────│  (tmux output stream)
   │                               │
   │──── input "ls\r" ────────────►│
   │◄─── output "file1 file2..." ─│
   │                               │
   │──── detach ──────────────────►│
   │◄─── detached ────────────────│
   │◄─── sessions [...] ──────────│  (refresh list)
```

## File Structure

```
z-web/
├── cmd/
│   └── z-web/
│       └── main.go           # Entry point
├── internal/
│   ├── server/
│   │   ├── server.go         # HTTP + WebSocket server
│   │   └── handlers.go       # Route handlers
│   ├── session/
│   │   ├── manager.go        # Session lifecycle
│   │   ├── tmux.go           # tmux interaction
│   │   └── pty.go            # PTY management
│   └── ws/
│       ├── client.go         # WebSocket client
│       └── protocol.go       # Message types
├── web/
│   ├── src/
│   │   ├── main.ts           # Entry point
│   │   ├── terminal.ts       # xterm.js wrapper
│   │   ├── session.ts        # Session picker UI
│   │   ├── input.ts          # Input bar component
│   │   ├── websocket.ts      # WebSocket client
│   │   └── types.ts          # Shared types
│   ├── index.html
│   ├── style.css
│   ├── package.json
│   ├── tsconfig.json
│   └── vite.config.ts
├── Makefile
├── go.mod
└── README.md
```

## Integration with z

### New Module: `z web`

```bash
# Start the web server
z web start
# → Starting z-web on http://100.x.x.x:7680
# → Access from any device on your Tailscale network

# Start on specific port
z web start -p 8080

# Start and bind to specific interface
z web start --host 0.0.0.0  # All interfaces (use with caution)
z web start --host tailscale # Tailscale IP only (default)

# Stop the server
z web stop

# Show status
z web status
# → z-web running on http://100.x.x.x:7680 (PID: 12345)
# → 2 active connections

# Open in browser (macOS)
z web open
```

### Module File: `plugins/z/modules/web.zsh`

```zsh
Z_WEB_PORT="${Z_WEB_PORT:-7680}"
Z_WEB_PID_FILE="${Z_DIR}/web/z-web.pid"

_z_web() {
    local cmd="$1"
    shift

    case "${cmd}" in
        start)  _z_web_start "$@" ;;
        stop)   _z_web_stop "$@" ;;
        status) _z_web_status "$@" ;;
        open)   _z_web_open "$@" ;;
        help|*) _z_web_help ;;
    esac
}
```

## Implementation Phases

### Phase 1: Backend Foundation
1. Set up Go project structure
2. Implement WebSocket server
3. Implement tmux session listing (parse `tmux list-sessions`)
4. Implement attach/detach via PTY
5. Basic terminal I/O over WebSocket

### Phase 2: Frontend Foundation
1. Set up Vite + TypeScript project
2. Implement xterm.js terminal (display only)
3. Implement WebSocket client
4. Basic input → server → tmux → output flow

### Phase 3: Session Management UI
1. Session picker component
2. Session chip with current session
3. Create new session flow
4. Detach functionality

### Phase 4: Mobile Polish
1. Mobile-responsive CSS
2. Touch-friendly session picker
3. Input bar keyboard handling
4. Viewport height fixes (mobile browser chrome)

### Phase 5: Integration
1. Create `web.zsh` module
2. Binary distribution via `z app`
3. Auto-detect Tailscale IP
4. Add to z completions

### Phase 6: Polish
1. Error handling and reconnection
2. Loading states
3. Session activity indicators
4. Dark/light theme (respect system preference)

## Mobile Considerations

### Viewport Height
Mobile browsers have dynamic toolbars. Use:
```css
height: 100dvh;  /* Dynamic viewport height */
```

### Input Handling
- Prevent zoom on input focus: `font-size: 16px` minimum
- Handle virtual keyboard appearance
- Keep input visible when keyboard opens

### Touch
- Large tap targets (44px minimum)
- Swipe to dismiss session picker
- Pull to refresh session list

## Security

- **No authentication**: Relies entirely on Tailscale
- **Bind to Tailscale IP by default**: Won't be accessible outside tailnet
- **No secrets in code**: Session names, paths are not sensitive
- **Consider**: Optional PIN/password for extra layer

## Dependencies

### Go
```go
require (
    github.com/gorilla/websocket v1.5.0
    github.com/creack/pty v1.1.18
)
```

### Node (Frontend)
```json
{
  "dependencies": {
    "xterm": "^5.3.0",
    "xterm-addon-fit": "^0.8.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "vite": "^5.0.0"
  }
}
```

## Example Usage

### Starting the Server
```bash
$ z web start
Starting z-web server...
Listening on http://100.78.42.15:7680
Open on your phone: http://macbook:7680

$ z web status
z-web running
  URL: http://100.78.42.15:7680
  PID: 45231
  Uptime: 2h 15m
  Connections: 1 active
```

### From Phone
1. Open Safari/Chrome: `http://macbook:7680`
2. See list of sessions (or empty state)
3. Tap "agent-work" to attach
4. Terminal output appears
5. Type in input box, tap send
6. Tap session chip to switch sessions

## Future Enhancements

- [ ] Multiple terminal tabs in UI
- [ ] Session search/filter
- [ ] Keyboard shortcuts
- [ ] Command history (up arrow)
- [ ] Copy/paste improvements
- [ ] Notifications when session needs attention
- [ ] Remote machine support (`z web` queries remote `z term list`)
