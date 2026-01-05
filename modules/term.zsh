#!/usr/bin/env zsh
# Z term module - Remote terminal session management

# Term data directory
Z_TERM_DIR="${Z_TERM_DIR:-${Z_DIR}/term}"
Z_TERM_SESSIONS_FILE="${Z_TERM_DIR}/sessions.json"
Z_TERM_PREFIX="z-"

# Module dispatcher
_z_term() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        start)
            _z_term_start "$@"
            ;;
        list|ls)
            _z_term_list "$@"
            ;;
        attach|a)
            _z_term_attach "$@"
            ;;
        stop|kill)
            _z_term_stop "$@"
            ;;
        status)
            _z_term_status "$@"
            ;;
        help|--help|-h|"")
            _z_term_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z term help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_term_help() {
    cat <<'EOF'
z term - Remote terminal session management

Usage: z term <command> [args]

Commands:
  start [name] [-d desc] [--bg]  Start a new shareable session
  list [-m machine|all] [--json] List available sessions
  attach <name> [-m machine]     Attach to a session
  stop <name>                    Stop a session
  status                         Show current session status
  help                           Show this help

Options:
  -d, --description    Description for the session
  --bg                 Start in background (don't attach)
  -m, --machine        Target machine (or 'all')
  --json               Output in JSON format

Examples:
  z term start                    # Start session with auto name
  z term start agent-work         # Start named session
  z term start work -d "Feature"  # Start with description
  z term start work --bg          # Start without attaching
  z term list                     # List local sessions
  z term list -m all              # List from all machines
  z term attach agent-work        # Attach to session
  z term attach work -m server    # Attach to remote session
  z term stop agent-work          # Stop a session

Session Info:
  Sessions show: working directory, running command, git branch,
  last activity, and number of attached clients.
EOF
}

# Check if tmux is installed
_z_term_check_tmux() {
    if ! command -v tmux &>/dev/null; then
        echo "Error: tmux is not installed"
        echo ""
        echo "Install tmux:"
        echo "  macOS:  brew install tmux"
        echo "  Ubuntu: sudo apt install tmux"
        echo "  Fedora: sudo dnf install tmux"
        return 1
    fi
    return 0
}

# Ensure term directory exists
_z_term_ensure_dir() {
    [[ ! -d "${Z_TERM_DIR}" ]] && mkdir -p "${Z_TERM_DIR}"
}

# Generate session name
_z_term_gen_name() {
    local machine=$(_z_this_machine 2>/dev/null || hostname -s)
    local timestamp=$(date +%s)
    echo "${machine}-${timestamp}"
}

# Get full tmux session name (with prefix)
_z_term_session_name() {
    local name="$1"
    # If already has prefix, return as-is
    if [[ "${name}" == ${Z_TERM_PREFIX}* ]]; then
        echo "${name}"
    else
        echo "${Z_TERM_PREFIX}${name}"
    fi
}

# Get display name (without prefix)
_z_term_display_name() {
    local name="$1"
    echo "${name#${Z_TERM_PREFIX}}"
}

# Start a new session
_z_term_start() {
    _z_term_check_tmux || return 1
    _z_term_ensure_dir

    local name=""
    local description=""
    local background=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--description)
                description="$2"
                shift 2
                ;;
            --bg|--background)
                background=true
                shift
                ;;
            -*)
                echo "Error: Unknown option '$1'"
                return 1
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                fi
                shift
                ;;
        esac
    done

    # Generate name if not provided
    [[ -z "${name}" ]] && name=$(_z_term_gen_name)

    local session_name=$(_z_term_session_name "${name}")

    # Check if session already exists
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        echo "Error: Session '${name}' already exists"
        echo "Use 'z term attach ${name}' to connect, or 'z term stop ${name}' to remove it"
        return 1
    fi

    # Check if inside tmux already
    if [[ -n "${TMUX}" ]] && [[ "${background}" == false ]]; then
        echo "Warning: Already inside a tmux session"
        printf "Create nested session? [y/N] "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Cancelled. Use --bg to create in background."
            return 0
        fi
    fi

    # Create the session
    local cwd="${PWD}"
    tmux new-session -d -s "${session_name}" -c "${cwd}"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create tmux session"
        return 1
    fi

    echo "Started session: ${name}"

    # Save metadata
    _z_term_save_metadata "${name}" "${description}" "${cwd}"

    # Attach unless --bg
    if [[ "${background}" == false ]]; then
        tmux attach-session -t "${session_name}"
    else
        echo "  (running in background)"
        echo "  Attach with: z term attach ${name}"
    fi
}

# Save session metadata
_z_term_save_metadata() {
    local name="$1"
    local description="$2"
    local cwd="$3"
    local created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # For now, metadata is queried live from tmux
    # This function is a placeholder for future stored metadata
    :
}

# List sessions
_z_term_list() {
    _z_term_check_tmux || return 1

    local machine=""
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--machine)
                machine="$2"
                shift 2
                ;;
            --json)
                json_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Handle remote machine queries
    if [[ -n "${machine}" ]]; then
        _z_term_list_remote "${machine}" "${json_output}"
        return $?
    fi

    # Get local sessions
    local sessions=$(tmux list-sessions -F "#{session_name}|#{session_activity}|#{session_attached}" 2>/dev/null | grep "^${Z_TERM_PREFIX}")

    if [[ -z "${sessions}" ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "No sessions found"
            echo ""
            echo "Start a session with: z term start [name]"
        fi
        return 0
    fi

    if [[ "${json_output}" == true ]]; then
        _z_term_list_json "${sessions}"
    else
        _z_term_list_table "${sessions}"
    fi
}

# Format relative time
_z_term_relative_time() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [[ ${diff} -lt 60 ]]; then
        echo "${diff}s ago"
    elif [[ ${diff} -lt 3600 ]]; then
        echo "$((diff / 60))m ago"
    elif [[ ${diff} -lt 86400 ]]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# List sessions as table
_z_term_list_table() {
    local sessions="$1"

    printf "%-15s %-25s %-15s %-12s %-10s %s\n" \
        "SESSION" "CWD" "CMD" "BRANCH" "ACTIVITY" "CLIENTS"
    printf "%-15s %-25s %-15s %-12s %-10s %s\n" \
        "-------" "---" "---" "------" "--------" "-------"

    echo "${sessions}" | while IFS='|' read -r session_name activity attached; do
        local display_name=$(_z_term_display_name "${session_name}")

        # Get pane info
        local pane_info=$(tmux list-panes -t "${session_name}" -F "#{pane_current_path}|#{pane_current_command}" 2>/dev/null | head -1)
        local cwd=$(echo "${pane_info}" | cut -d'|' -f1)
        local cmd=$(echo "${pane_info}" | cut -d'|' -f2)

        # Shorten cwd
        cwd="${cwd/#$HOME/~}"
        [[ ${#cwd} -gt 25 ]] && cwd="...${cwd: -22}"

        # Shorten cmd
        [[ ${#cmd} -gt 15 ]] && cmd="${cmd:0:12}..."

        # Get git branch
        local branch=""
        local full_cwd="${cwd/#\~/$HOME}"
        if [[ -d "${full_cwd}/.git" ]] || git -C "${full_cwd}" rev-parse --git-dir &>/dev/null 2>&1; then
            branch=$(git -C "${full_cwd}" branch --show-current 2>/dev/null)
        fi
        [[ ${#branch} -gt 12 ]] && branch="${branch:0:9}..."

        # Format activity
        local activity_str=$(_z_term_relative_time "${activity}")

        printf "%-15s %-25s %-15s %-12s %-10s %s\n" \
            "${display_name}" "${cwd}" "${cmd}" "${branch:--}" "${activity_str}" "${attached}"
    done
}

# List sessions as JSON
_z_term_list_json() {
    local sessions="$1"
    local first=true

    echo "["
    echo "${sessions}" | while IFS='|' read -r session_name activity attached; do
        local display_name=$(_z_term_display_name "${session_name}")

        # Get pane info
        local pane_info=$(tmux list-panes -t "${session_name}" -F "#{pane_current_path}|#{pane_current_command}" 2>/dev/null | head -1)
        local cwd=$(echo "${pane_info}" | cut -d'|' -f1)
        local cmd=$(echo "${pane_info}" | cut -d'|' -f2)

        # Get git branch
        local branch=""
        if [[ -d "${cwd}/.git" ]] || git -C "${cwd}" rev-parse --git-dir &>/dev/null 2>&1; then
            branch=$(git -C "${cwd}" branch --show-current 2>/dev/null)
        fi

        [[ "${first}" == true ]] && first=false || echo ","

        cat <<EOF
  {
    "name": "${display_name}",
    "session": "${session_name}",
    "cwd": "${cwd}",
    "command": "${cmd}",
    "git_branch": "${branch}",
    "last_activity": ${activity},
    "clients": ${attached}
  }
EOF
    done
    echo "]"
}

# List sessions from remote machine
_z_term_list_remote() {
    local machine="$1"
    local json_output="$2"

    if [[ "${machine}" == "all" ]]; then
        # Query all machines
        local this_machine=$(_z_this_machine 2>/dev/null || hostname -s)

        if [[ "${json_output}" == true ]]; then
            echo "{"
            echo "  \"${this_machine}\": $(_z_term_list_local_json),"

            # Get all remote machines and query them
            # TODO: Implement remote machine iteration
            echo "}"
        else
            echo "Machine: ${this_machine} (local)"
            _z_term_list
            echo ""

            # TODO: Query remote machines
            echo "(Remote machine queries not yet implemented)"
        fi
    else
        # Query specific machine
        local result=$(_z_remote_exec "${machine}" "term list --json" 2>&1)
        if [[ $? -ne 0 ]]; then
            echo "Error: Could not connect to machine '${machine}'"
            echo "${result}"
            return 1
        fi

        if [[ "${json_output}" == true ]]; then
            echo "${result}"
        else
            echo "Machine: ${machine}"
            echo "${result}" | _z_term_format_remote_json
        fi
    fi
}

# Helper for local JSON (used in aggregation)
_z_term_list_local_json() {
    local sessions=$(tmux list-sessions -F "#{session_name}|#{session_activity}|#{session_attached}" 2>/dev/null | grep "^${Z_TERM_PREFIX}")
    if [[ -z "${sessions}" ]]; then
        echo "[]"
    else
        _z_term_list_json "${sessions}"
    fi
}

# Attach to a session
_z_term_attach() {
    _z_term_check_tmux || return 1

    local name=""
    local machine=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--machine)
                machine="$2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option '$1'"
                return 1
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "${name}" ]]; then
        echo "Error: No session name provided"
        echo "Usage: z term attach <name> [-m machine]"
        echo ""
        echo "Available sessions:"
        _z_term_list
        return 1
    fi

    local session_name=$(_z_term_session_name "${name}")

    # Remote attach
    if [[ -n "${machine}" ]]; then
        _z_term_attach_remote "${name}" "${machine}"
        return $?
    fi

    # Local attach
    if ! tmux has-session -t "${session_name}" 2>/dev/null; then
        echo "Error: Session '${name}' not found"
        echo ""
        echo "Available sessions:"
        _z_term_list
        return 1
    fi

    tmux attach-session -t "${session_name}"
}

# Attach to remote session
_z_term_attach_remote() {
    local name="$1"
    local machine="$2"

    local session_name=$(_z_term_session_name "${name}")

    # Get machine info
    local host=$(grep -A3 "\"name\": \"${machine}\"" "${Z_MACHINES_FILE}" 2>/dev/null | grep '"host"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    local user=$(grep -A4 "\"name\": \"${machine}\"" "${Z_MACHINES_FILE}" 2>/dev/null | grep '"user"' | sed 's/.*: *"\([^"]*\)".*/\1/')

    if [[ -z "${host}" ]]; then
        echo "Error: Machine '${machine}' not found"
        echo "Run 'z sys list' to see available machines"
        return 1
    fi

    local ssh_target="${host}"
    [[ -n "${user}" ]] && ssh_target="${user}@${host}"

    echo "Connecting to ${machine}:${name}..."
    ssh -t "${ssh_target}" "tmux attach-session -t '${session_name}'"
}

# Stop a session
_z_term_stop() {
    _z_term_check_tmux || return 1

    local name="$1"

    if [[ -z "${name}" ]]; then
        # If inside a tmux session, offer to stop current
        if [[ -n "${TMUX}" ]]; then
            local current=$(tmux display-message -p '#{session_name}')
            if [[ "${current}" == ${Z_TERM_PREFIX}* ]]; then
                local display=$(_z_term_display_name "${current}")
                printf "Stop current session '${display}'? [y/N] "
                read -r response
                if [[ "${response}" =~ ^[Yy]$ ]]; then
                    name="${display}"
                else
                    return 0
                fi
            else
                echo "Error: Current session is not a z term session"
                return 1
            fi
        else
            echo "Error: No session name provided"
            echo "Usage: z term stop <name>"
            return 1
        fi
    fi

    local session_name=$(_z_term_session_name "${name}")

    if ! tmux has-session -t "${session_name}" 2>/dev/null; then
        echo "Error: Session '${name}' not found"
        echo ""
        echo "Available sessions:"
        _z_term_list
        return 1
    fi

    tmux kill-session -t "${session_name}"
    echo "Stopped session: ${name}"
}

# Show current session status
_z_term_status() {
    if [[ -z "${TMUX}" ]]; then
        echo "Not in a tmux session"
        echo ""
        echo "Start a session with: z term start [name]"
        echo "Or list sessions with: z term list"
        return 0
    fi

    local session_name=$(tmux display-message -p '#{session_name}')

    if [[ "${session_name}" != ${Z_TERM_PREFIX}* ]]; then
        echo "In tmux session: ${session_name}"
        echo "(Not a z term session)"
        return 0
    fi

    local display_name=$(_z_term_display_name "${session_name}")

    # Get session info
    local session_info=$(tmux list-sessions -F "#{session_name}|#{session_created}|#{session_attached}" | grep "^${session_name}|")
    local created=$(echo "${session_info}" | cut -d'|' -f2)
    local attached=$(echo "${session_info}" | cut -d'|' -f3)

    # Get pane info
    local pane_info=$(tmux list-panes -F "#{pane_current_path}|#{pane_current_command}" | head -1)
    local cwd=$(echo "${pane_info}" | cut -d'|' -f1)
    local cmd=$(echo "${pane_info}" | cut -d'|' -f2)

    # Get git branch
    local branch=""
    if [[ -d "${cwd}/.git" ]] || git -C "${cwd}" rev-parse --git-dir &>/dev/null 2>&1; then
        branch=$(git -C "${cwd}" branch --show-current 2>/dev/null)
    fi

    local machine=$(_z_this_machine 2>/dev/null || hostname -s)
    local created_str=$(date -d "@${created}" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "${created}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")

    echo "Session: ${display_name}"
    echo "Machine: ${machine}"
    echo "Created: ${created_str}"
    echo "CWD:     ${cwd}"
    echo "Command: ${cmd}"
    [[ -n "${branch}" ]] && echo "Branch:  ${branch}"
    echo "Clients: ${attached}"
    echo ""
    echo "Detach with: Ctrl-B d (or z term detach)"
    echo "Stop with:   z term stop ${display_name}"
}
