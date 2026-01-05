#!/usr/bin/env zsh
# Z beacon module - Auto-discovery beacon management

Z_BEACON_PORT="${Z_BEACON_PORT:-7681}"
Z_BEACON_DIR="${Z_DIR}/beacon"
Z_BEACON_PID_FILE="${Z_BEACON_DIR}/z-beacon.pid"
Z_BEACON_LOG_FILE="${Z_BEACON_DIR}/z-beacon.log"
Z_BEACON_BIN="${Z_BEACON_BIN:-${Z_DIR}/bin/z-beacon}"
Z_BEACON_AUTOSTART="${Z_BEACON_AUTOSTART:-true}"

# Module dispatcher
_z_beacon() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        start)
            _z_beacon_start "$@"
            ;;
        stop)
            _z_beacon_stop "$@"
            ;;
        status)
            _z_beacon_status "$@"
            ;;
        help|--help|-h|"")
            _z_beacon_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z beacon help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_beacon_help() {
    cat <<'EOF'
z beacon - Auto-discovery beacon management

Usage: z beacon <command>

Commands:
  start       Start the beacon server
  stop        Stop the beacon server
  status      Show beacon status
  help        Show this help

The beacon allows other z instances on your Tailscale network
to discover this machine automatically.

Configuration:
  Z_BEACON_PORT       Port to listen on (default: 7681)
  Z_BEACON_AUTOSTART  Auto-start on shell init (default: true)

The beacon is started automatically when your shell loads
(if Tailscale is available and the binary is installed).

Install the beacon binary:
  cd ~/.z/z-beacon && make install
EOF
}

# Ensure beacon directory exists
_z_beacon_ensure_dir() {
    [[ ! -d "${Z_BEACON_DIR}" ]] && mkdir -p "${Z_BEACON_DIR}"
}

# Check if z-beacon binary exists
_z_beacon_check_binary() {
    if [[ ! -x "${Z_BEACON_BIN}" ]]; then
        echo "Error: z-beacon binary not found at ${Z_BEACON_BIN}"
        echo ""
        echo "Build and install it with:"
        echo "  cd ~/.z/z-beacon && make install"
        echo ""
        echo "Or from the z repository:"
        echo "  cd /path/to/z/z-beacon && make install"
        return 1
    fi
    return 0
}

# Check if Tailscale is available
_z_beacon_check_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        return 1
    fi
    if ! tailscale status &>/dev/null; then
        return 1
    fi
    return 0
}

# Start the beacon (manual)
_z_beacon_start() {
    _z_beacon_ensure_dir
    _z_beacon_check_binary || return 1

    if ! _z_beacon_check_tailscale; then
        echo "Error: Tailscale not available or not connected"
        return 1
    fi

    # Check if already running
    if [[ -f "${Z_BEACON_PID_FILE}" ]]; then
        local pid=$(cat "${Z_BEACON_PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo "z-beacon is already running (PID: ${pid})"
            _z_beacon_status
            return 0
        else
            rm -f "${Z_BEACON_PID_FILE}"
        fi
    fi

    echo "Starting z-beacon..."

    nohup "${Z_BEACON_BIN}" --port "${Z_BEACON_PORT}" > "${Z_BEACON_LOG_FILE}" 2>&1 &
    local pid=$!

    echo "${pid}" > "${Z_BEACON_PID_FILE}"

    sleep 1

    if kill -0 "${pid}" 2>/dev/null; then
        local ts_ip=$(tailscale ip -4 2>/dev/null)
        echo "z-beacon started successfully"
        echo ""
        echo "  Address: http://${ts_ip}:${Z_BEACON_PORT}"
        echo "  PID:     ${pid}"
    else
        echo "Error: z-beacon failed to start"
        echo "Check logs with: tail ${Z_BEACON_LOG_FILE}"
        rm -f "${Z_BEACON_PID_FILE}"
        return 1
    fi
}

# Stop the beacon
_z_beacon_stop() {
    if [[ ! -f "${Z_BEACON_PID_FILE}" ]]; then
        echo "z-beacon is not running"
        return 0
    fi

    local pid=$(cat "${Z_BEACON_PID_FILE}")

    if kill -0 "${pid}" 2>/dev/null; then
        echo "Stopping z-beacon (PID: ${pid})..."
        kill "${pid}"

        local count=0
        while kill -0 "${pid}" 2>/dev/null && [[ ${count} -lt 10 ]]; do
            sleep 0.5
            ((count++))
        done

        if kill -0 "${pid}" 2>/dev/null; then
            echo "Force killing..."
            kill -9 "${pid}" 2>/dev/null
        fi

        echo "z-beacon stopped"
    else
        echo "z-beacon is not running (stale PID file)"
    fi

    rm -f "${Z_BEACON_PID_FILE}"
}

# Show status
_z_beacon_status() {
    if [[ ! -f "${Z_BEACON_PID_FILE}" ]]; then
        echo "z-beacon is not running"
        echo ""
        echo "Start with: z beacon start"
        return 0
    fi

    local pid=$(cat "${Z_BEACON_PID_FILE}")

    if kill -0 "${pid}" 2>/dev/null; then
        local ps_info=$(ps -p "${pid}" -o etime= 2>/dev/null | xargs)
        local ts_ip=$(tailscale ip -4 2>/dev/null)

        echo "z-beacon is running"
        echo ""
        echo "  PID:     ${pid}"
        echo "  Uptime:  ${ps_info:-unknown}"
        echo "  Address: http://${ts_ip}:${Z_BEACON_PORT}"
    else
        echo "z-beacon is not running (stale PID file)"
        rm -f "${Z_BEACON_PID_FILE}"
    fi
}

# Auto-start beacon (called from z.plugin.zsh)
# This runs silently and only starts if conditions are met
_z_beacon_autostart() {
    # Skip if disabled
    [[ "${Z_BEACON_AUTOSTART}" == "false" ]] && return 0

    # Skip if binary doesn't exist
    [[ ! -x "${Z_BEACON_BIN}" ]] && return 0

    # Skip if Tailscale isn't running
    _z_beacon_check_tailscale || return 0

    # Ensure directory exists
    _z_beacon_ensure_dir

    # Check if already running
    if [[ -f "${Z_BEACON_PID_FILE}" ]]; then
        local pid=$(cat "${Z_BEACON_PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            return 0  # Already running
        fi
        rm -f "${Z_BEACON_PID_FILE}"
    fi

    # Start beacon in background (silently)
    nohup "${Z_BEACON_BIN}" --port "${Z_BEACON_PORT}" > "${Z_BEACON_LOG_FILE}" 2>&1 &
    echo $! > "${Z_BEACON_PID_FILE}"
}
