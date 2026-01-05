#!/usr/bin/env zsh
# Z web module - Browser-based terminal access

Z_WEB_PORT="${Z_WEB_PORT:-7680}"
Z_WEB_DIR="${Z_DIR}/web"
Z_WEB_PID_FILE="${Z_WEB_DIR}/z-web.pid"
Z_WEB_LOG_FILE="${Z_WEB_DIR}/z-web.log"
Z_WEB_BIN="${Z_WEB_BIN:-${Z_DIR}/bin/z-web}"

# Module dispatcher
_z_web() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        start)
            _z_web_start "$@"
            ;;
        stop)
            _z_web_stop "$@"
            ;;
        status)
            _z_web_status "$@"
            ;;
        open)
            _z_web_open "$@"
            ;;
        logs)
            _z_web_logs "$@"
            ;;
        help|--help|-h|"")
            _z_web_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z web help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_web_help() {
    cat <<'EOF'
z web - Browser-based terminal access

Usage: z web <command> [options]

Commands:
  start [-p port] [--host host]  Start the web server
  stop                           Stop the web server
  status                         Show server status
  open                           Open in default browser
  logs                           Show server logs
  help                           Show this help

Options:
  -p, --port     Port to listen on (default: 7680)
  --host         Host to bind to: tailscale, localhost, or IP
                 (default: tailscale)

Examples:
  z web start                    # Start on Tailscale IP:7680
  z web start -p 8080            # Start on port 8080
  z web start --host localhost   # Start on localhost only
  z web stop                     # Stop the server
  z web open                     # Open in browser

Access from any device on your Tailscale network.
EOF
}

# Ensure web directory exists
_z_web_ensure_dir() {
    [[ ! -d "${Z_WEB_DIR}" ]] && mkdir -p "${Z_WEB_DIR}"
}

# Check if z-web binary exists
_z_web_check_binary() {
    if [[ ! -x "${Z_WEB_BIN}" ]]; then
        echo "Error: z-web binary not found at ${Z_WEB_BIN}"
        echo ""
        echo "Build it with:"
        echo "  cd ~/.z/z-web && make build"
        echo ""
        echo "Or install from the z repository:"
        echo "  cd /path/to/z/z-web && make install"
        return 1
    fi
    return 0
}

# Get the server URL
_z_web_get_url() {
    local host="$1"
    local port="$2"

    if [[ "${host}" == "tailscale" ]]; then
        # Try to get Tailscale IP
        local ts_ip=$(tailscale ip -4 2>/dev/null)
        if [[ -n "${ts_ip}" ]]; then
            echo "http://${ts_ip}:${port}"
        else
            echo "http://localhost:${port}"
        fi
    else
        echo "http://${host}:${port}"
    fi
}

# Start the server
_z_web_start() {
    _z_web_ensure_dir
    _z_web_check_binary || return 1

    local port="${Z_WEB_PORT}"
    local host="tailscale"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--port)
                port="$2"
                shift 2
                ;;
            --host)
                host="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check if already running
    if [[ -f "${Z_WEB_PID_FILE}" ]]; then
        local pid=$(cat "${Z_WEB_PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo "z-web is already running (PID: ${pid})"
            _z_web_status
            return 0
        else
            # Stale PID file
            rm -f "${Z_WEB_PID_FILE}"
        fi
    fi

    # Start the server
    echo "Starting z-web server..."

    nohup "${Z_WEB_BIN}" --port "${port}" --host "${host}" > "${Z_WEB_LOG_FILE}" 2>&1 &
    local pid=$!

    # Save PID
    echo "${pid}" > "${Z_WEB_PID_FILE}"

    # Wait a moment for startup
    sleep 1

    # Check if it started successfully
    if kill -0 "${pid}" 2>/dev/null; then
        local url=$(_z_web_get_url "${host}" "${port}")
        echo "z-web started successfully"
        echo ""
        echo "  URL: ${url}"
        echo "  PID: ${pid}"
        echo ""
        echo "Open on your phone: ${url}"
    else
        echo "Error: z-web failed to start"
        echo "Check logs with: z web logs"
        rm -f "${Z_WEB_PID_FILE}"
        return 1
    fi
}

# Stop the server
_z_web_stop() {
    if [[ ! -f "${Z_WEB_PID_FILE}" ]]; then
        echo "z-web is not running"
        return 0
    fi

    local pid=$(cat "${Z_WEB_PID_FILE}")

    if kill -0 "${pid}" 2>/dev/null; then
        echo "Stopping z-web (PID: ${pid})..."
        kill "${pid}"

        # Wait for process to stop
        local count=0
        while kill -0 "${pid}" 2>/dev/null && [[ ${count} -lt 10 ]]; do
            sleep 0.5
            ((count++))
        done

        if kill -0 "${pid}" 2>/dev/null; then
            echo "Force killing..."
            kill -9 "${pid}" 2>/dev/null
        fi

        echo "z-web stopped"
    else
        echo "z-web is not running (stale PID file)"
    fi

    rm -f "${Z_WEB_PID_FILE}"
}

# Show status
_z_web_status() {
    if [[ ! -f "${Z_WEB_PID_FILE}" ]]; then
        echo "z-web is not running"
        echo ""
        echo "Start with: z web start"
        return 0
    fi

    local pid=$(cat "${Z_WEB_PID_FILE}")

    if kill -0 "${pid}" 2>/dev/null; then
        # Get process info
        local ps_info=$(ps -p "${pid}" -o etime= 2>/dev/null | xargs)

        echo "z-web is running"
        echo ""
        echo "  PID:    ${pid}"
        echo "  Uptime: ${ps_info:-unknown}"

        # Try to get URL from process args or default
        local url=$(_z_web_get_url "tailscale" "${Z_WEB_PORT}")
        echo "  URL:    ${url}"
    else
        echo "z-web is not running (stale PID file)"
        rm -f "${Z_WEB_PID_FILE}"
    fi
}

# Open in browser
_z_web_open() {
    local url=$(_z_web_get_url "tailscale" "${Z_WEB_PORT}")

    # Check if running
    if [[ -f "${Z_WEB_PID_FILE}" ]]; then
        local pid=$(cat "${Z_WEB_PID_FILE}")
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "z-web is not running. Start with: z web start"
            return 1
        fi
    else
        echo "z-web is not running. Start with: z web start"
        return 1
    fi

    echo "Opening ${url}..."

    # Try different open commands
    if command -v xdg-open &>/dev/null; then
        xdg-open "${url}"
    elif command -v open &>/dev/null; then
        open "${url}"
    elif command -v wslview &>/dev/null; then
        wslview "${url}"
    else
        echo "Could not detect browser. Open manually:"
        echo "  ${url}"
    fi
}

# Show logs
_z_web_logs() {
    if [[ -f "${Z_WEB_LOG_FILE}" ]]; then
        tail -f "${Z_WEB_LOG_FILE}"
    else
        echo "No log file found"
    fi
}
