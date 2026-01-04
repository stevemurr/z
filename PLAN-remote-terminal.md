# Remote Terminal Module (`z term`) - Implementation Plan

## Overview

A module that enables connecting to any terminal session running z, both locally and remotely. Uses tmux as the underlying session multiplexer, with z providing a clean interface for session management and discovery.

## Use Cases

1. **Monitor long-running processes** - Attach to a session running a build, deployment, or training job
2. **Respond to AI agents** - Connect to sessions where Claude Code or other agents need input
3. **Pair programming** - Share terminal sessions with teammates (via Tailscale)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         z term module                            │
├─────────────────────────────────────────────────────────────────┤
│  Commands:                                                       │
│    z term start [name]     - Start a shareable session          │
│    z term list [-m host]   - List available sessions            │
│    z term attach <name>    - Attach to a session                │
│    z term detach           - Detach from current session        │
│    z term stop [name]      - Stop a session                     │
│    z term status           - Show current session status        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         tmux backend                             │
├─────────────────────────────────────────────────────────────────┤
│  - Named sessions with z- prefix (e.g., z-agent-work)           │
│  - Session metadata stored in ~/.z/term/sessions.json           │
│  - Remote access via SSH + tmux attach                          │
└─────────────────────────────────────────────────────────────────┘
```

## Data Storage

### Session Metadata: `~/.z/term/sessions.json`
```json
{
  "sessions": [
    {
      "name": "agent-work",
      "tmux_session": "z-agent-work",
      "created": "2026-01-04T12:00:00Z",
      "description": "Claude Code session for project X",
      "pid": 12345
    }
  ]
}
```

## Commands Specification

### `z term start [name] [-d description]`
Start a new shareable terminal session.

```bash
# Start with auto-generated name
z term start
# → Started session: z-macbook-1704380400

# Start with custom name
z term start agent-work
# → Started session: z-agent-work

# Start with description
z term start agent-work -d "Working on auth feature"
```

**Implementation:**
1. Generate session name (user-provided or `z-{machine}-{timestamp}`)
2. Create tmux session: `tmux new-session -d -s "z-{name}"`
3. Record metadata to `~/.z/term/sessions.json`
4. Attach to the new session

### `z term list [-m machine|all] [--json]`
List available sessions (local and remote).

```bash
# List local sessions
z term list
# → MACHINE     SESSION          CREATED              DESCRIPTION
#   macbook     z-agent-work     2026-01-04 12:00     Working on auth
#   macbook     z-build          2026-01-04 11:30     -

# List from specific remote machine
z term list -m work
# → MACHINE     SESSION          CREATED              DESCRIPTION
#   work        z-deploy         2026-01-04 10:00     Production deploy

# List from all machines
z term list -m all
# → Shows aggregated list from all registered machines
```

**Implementation:**
1. Query local tmux: `tmux list-sessions -F "#{session_name}"`
2. Filter to z- prefixed sessions
3. If `-m` specified, use `_z_remote_exec` to query remote machines
4. Display formatted table or JSON

### `z term attach <name|session> [-m machine]`
Attach to an existing session.

```bash
# Attach to local session
z term attach agent-work

# Attach to remote session
z term attach deploy -m work
# → Connects via: ssh -t user@work "tmux attach -t z-deploy"
```

**Implementation:**
1. If local: `tmux attach-session -t "z-{name}"`
2. If remote: `ssh -t {user}@{host} "tmux attach-session -t z-{name}"`
3. Handle "session not found" gracefully

### `z term detach`
Detach from current session (returns to original terminal).

```bash
z term detach
# → Sends Ctrl-B d (or configured prefix)
```

**Implementation:**
- This is handled by tmux natively (Ctrl-B d)
- The command is a convenience alias / documentation

### `z term stop [name]`
Stop a session (kills the tmux session).

```bash
# Stop specific session
z term stop agent-work

# Stop current session (if inside one)
z term stop
```

**Implementation:**
1. `tmux kill-session -t "z-{name}"`
2. Remove from sessions.json
3. If no name provided and inside a session, kill current

### `z term status`
Show current session status.

```bash
z term status
# → Current session: z-agent-work
#   Machine: macbook
#   Created: 2026-01-04 12:00
#   Attached clients: 2
```

**Implementation:**
1. Check `$TMUX` env var
2. Query tmux for session info
3. Display formatted status

## Implementation Files

### New Files
- `plugins/z/modules/term.zsh` - Main module implementation
- `plugins/z/completions/_z_term` - Zsh completions

### Modified Files
- `plugins/z/lib/core.zsh` - Add term to builtin modules list
- `plugins/z/z.plugin.zsh` - Register term module

## Implementation Steps

### Phase 1: Core Functionality
1. Create `term.zsh` module skeleton with dispatcher
2. Implement `z term start` - create tmux sessions
3. Implement `z term list` - local session discovery
4. Implement `z term attach` - local attachment
5. Implement `z term stop` - session cleanup

### Phase 2: Remote Support
6. Implement `z term list -m <machine>` - remote discovery
7. Implement `z term attach -m <machine>` - remote attachment
8. Add JSON output for remote queries

### Phase 3: Polish
9. Add zsh completions
10. Add help documentation
11. Handle edge cases (no tmux, session conflicts, etc.)

## Warp Terminal Considerations

When attached to a tmux session from Warp:
- Warp's special features (blocks, AI, completions) will be disabled
- Basic terminal functionality works normally
- User can detach anytime to return to full Warp experience
- This is acceptable for the monitoring/response use case

## Dependencies

- **tmux** - Required, will check on first use
- **ssh** - For remote connections (already used by sys module)
- Relies on existing machine registry from `z sys`

## Example Workflows

### Workflow 1: Monitor a Build
```bash
# Terminal 1: Start a session and run build
z term start build
npm run build:watch

# Terminal 2: Attach to monitor
z term list
z term attach build
# Both terminals now show the same session
```

### Workflow 2: Remote Agent Response
```bash
# On remote server: Claude Code is waiting for input
z term start agent-session

# From local machine: Connect and respond
z term list -m work
z term attach agent-session -m work
# Now interacting with the remote session
```

### Workflow 3: Quick Session Sharing
```bash
# Person A starts a session
z term start pair -d "Debugging auth issue"

# Person B (on same Tailnet) connects
z term attach pair -m personA-machine
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| tmux not installed | Show install instructions |
| Session doesn't exist | Clear error + list available sessions |
| Remote machine offline | Show error + suggest `z sys list` |
| Already in tmux session | Warn about nested sessions |
| Session name conflict | Prompt to overwrite or choose new name |

## Security Notes

- Relies on Tailscale/SSH for authentication (no additional auth layer)
- Session names are prefixed with `z-` to avoid conflicts
- No sensitive data stored in session metadata
