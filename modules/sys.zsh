#!/usr/bin/env zsh
# Z sys module - Multi-machine management

# Module dispatcher
_z_sys() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        init)
            _z_sys_init "$@"
            ;;
        add)
            _z_sys_add "$@"
            ;;
        rm|remove)
            _z_sys_rm "$@"
            ;;
        list|ls)
            _z_sys_list "$@"
            ;;
        rename)
            _z_sys_rename "$@"
            ;;
        help|--help|-h|"")
            _z_sys_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z sys help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_sys_help() {
    cat <<'EOF'
z sys - Multi-machine management

Usage: z sys <command> [args]

Commands:
  init [name]         Initialize this machine (set name)
  add <name> <host>   Add a remote machine
      [user]            Optional SSH user (default: current user)
  rm <name>           Remove a machine
  list                List all machines with status
  rename <name>       Rename this machine
  help                Show this help

Cross-machine queries:
  z env list -m <machine>     List env vars from another machine
  z env copy VAR [-m <machine>] Copy a variable to clipboard
  z path list -m all          List paths from all machines

Examples:
  z sys init macbook
  z sys add work myserver.example.com
  z sys add server server.example.com myuser
  z sys list
  z env list -m work
EOF
}

# Initialize this machine
_z_sys_init() {
    local name="$1"

    # Create sys directory
    [[ ! -d "${Z_SYS_DIR}" ]] && mkdir -p "${Z_SYS_DIR}"

    # Prompt for name if not provided
    if [[ -z "${name}" ]]; then
        local default_name=$(hostname -s 2>/dev/null || echo "localhost")
        printf "Machine name [${default_name}]: "
        read -r name
        [[ -z "${name}" ]] && name="${default_name}"
    fi

    # Create or update machines.json
    if [[ -f "${Z_MACHINES_FILE}" ]]; then
        # Update this_machine
        local temp_file="${Z_MACHINES_FILE}.tmp"
        sed 's/"this_machine": "[^"]*"/"this_machine": "'"${name}"'"/' "${Z_MACHINES_FILE}" > "${temp_file}"
        mv "${temp_file}" "${Z_MACHINES_FILE}"
        echo "Updated machine name to: ${name}"
    else
        # Create new machines.json
        cat > "${Z_MACHINES_FILE}" <<EOF
{
  "this_machine": "${name}",
  "machines": []
}
EOF
        echo "Initialized sys module"
        echo "This machine: ${name}"
    fi

    echo ""
    echo "Add remote machines with: z sys add <name> <host>"
}

# Add a remote machine
_z_sys_add() {
    local name="$1"
    local host="$2"
    local user="${3:-$(whoami)}"

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No machine name provided"
        echo "Usage: z sys add <name> <host> [user]"
        return 1
    fi

    if [[ -z "${host}" ]]; then
        echo "Error: No host provided"
        echo "Usage: z sys add <name> <host> [user]"
        return 1
    fi

    # Check if sys is initialized
    if [[ ! -f "${Z_MACHINES_FILE}" ]]; then
        echo "Error: Sys not initialized. Run 'z sys init' first."
        return 1
    fi

    # Check if machine already exists
    if grep -q "\"name\": \"${name}\"" "${Z_MACHINES_FILE}" 2>/dev/null; then
        echo "Machine '${name}' already exists."
        printf "Overwrite? [y/N] "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        # Remove existing machine
        _z_sys_remove_machine "${name}"
    fi

    # Add machine to JSON
    local date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local temp_file="${Z_MACHINES_FILE}.tmp"

    # Check if machines array is empty
    if grep -q '"machines": \[\]' "${Z_MACHINES_FILE}"; then
        # Empty array - add first machine
        sed 's/"machines": \[\]/"machines": [\n    {\n      "name": "'"${name}"'",\n      "host": "'"${host}"'",\n      "user": "'"${user}"'",\n      "added": "'"${date}"'"\n    }\n  ]/' "${Z_MACHINES_FILE}" > "${temp_file}"
    else
        # Add to existing array
        sed 's/\(  "machines": \[\)/\1\n    {\n      "name": "'"${name}"'",\n      "host": "'"${host}"'",\n      "user": "'"${user}"'",\n      "added": "'"${date}"'"\n    },/' "${Z_MACHINES_FILE}" > "${temp_file}"
    fi

    mv "${temp_file}" "${Z_MACHINES_FILE}"

    echo "Added machine: ${name}"
    echo "  Host: ${host}"
    echo "  User: ${user}"

    # Test connection
    echo ""
    printf "Testing connection... "
    local ssh_target="${user}@${host}"
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${ssh_target}" "echo ok" &>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        echo "  (Machine added but SSH connection failed. Check host/credentials.)"
    fi
}

# Internal: Remove a machine from JSON
_z_sys_remove_machine() {
    local name="$1"
    local temp_file="${Z_MACHINES_FILE}.tmp"

    # Use awk to remove the machine entry
    awk -v name="${name}" '
        BEGIN { skip = 0; comma_pending = 0 }
        /"name": "'"${name}"'"/ { skip = 1 }
        skip && /\}/ { skip = 0; next }
        skip { next }
        {
            if (comma_pending && /^\s*\{/) {
                print prev_line
            }
            comma_pending = 0
            if (/\},?\s*$/) {
                prev_line = $0
                comma_pending = 1
            } else {
                print
            }
        }
        END {
            if (comma_pending) {
                gsub(/,\s*$/, "", prev_line)
                print prev_line
            }
        }
    ' "${Z_MACHINES_FILE}" > "${temp_file}"

    mv "${temp_file}" "${Z_MACHINES_FILE}"
}

# Remove a machine
_z_sys_rm() {
    local name="$1"

    if [[ -z "${name}" ]]; then
        echo "Error: No machine name provided"
        echo "Usage: z sys rm <name>"
        return 1
    fi

    if [[ ! -f "${Z_MACHINES_FILE}" ]]; then
        echo "Error: Sys not initialized. Run 'z sys init' first."
        return 1
    fi

    # Check if machine exists
    if ! grep -q "\"name\": \"${name}\"" "${Z_MACHINES_FILE}" 2>/dev/null; then
        echo "Error: Machine '${name}' not found"
        echo "Run 'z sys list' to see all machines"
        return 1
    fi

    _z_sys_remove_machine "${name}"
    echo "Removed machine: ${name}"
}

# List all machines
_z_sys_list() {
    if [[ ! -f "${Z_MACHINES_FILE}" ]]; then
        echo "Sys not initialized. Run 'z sys init' first."
        return 1
    fi

    local this_machine=$(_z_this_machine)
    echo "Machines:"
    echo ""
    printf "  %-15s %-35s %-15s %s\n" "NAME" "HOST" "USER" "STATUS"
    printf "  %-15s %-35s %-15s %s\n" "----" "----" "----" "------"

    # Show this machine
    printf "  %-15s %-35s %-15s %s\n" "${this_machine}" "(this machine)" "-" "local"

    # Parse machines from JSON and show status
    local in_machine=false
    local name="" host="" user=""

    while IFS= read -r line; do
        if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
            name="${match[1]}"
        elif [[ "${line}" =~ '"host": "([^"]+)"' ]]; then
            host="${match[1]}"
        elif [[ "${line}" =~ '"user": "([^"]+)"' ]]; then
            user="${match[1]}"
        elif [[ "${line}" =~ '^\s*\}' && -n "${name}" ]]; then
            # Check connection status
            local conn_status="?"
            local ssh_target="${user}@${host}"
            if ssh -o ConnectTimeout=2 -o BatchMode=yes "${ssh_target}" "exit" &>/dev/null; then
                conn_status="online"
            else
                conn_status="offline"
            fi

            # Truncate host if too long
            local display_host="${host}"
            if [[ ${#display_host} -gt 35 ]]; then
                display_host="${display_host:0:32}..."
            fi

            printf "  %-15s %-35s %-15s %s\n" "${name}" "${display_host}" "${user}" "${conn_status}"

            name="" host="" user=""
        fi
    done < "${Z_MACHINES_FILE}"
}

# Rename this machine
_z_sys_rename() {
    local name="$1"

    if [[ -z "${name}" ]]; then
        echo "Error: No name provided"
        echo "Usage: z sys rename <new-name>"
        return 1
    fi

    if [[ ! -f "${Z_MACHINES_FILE}" ]]; then
        echo "Error: Sys not initialized. Run 'z sys init' first."
        return 1
    fi

    local temp_file="${Z_MACHINES_FILE}.tmp"
    sed 's/"this_machine": "[^"]*"/"this_machine": "'"${name}"'"/' "${Z_MACHINES_FILE}" > "${temp_file}"
    mv "${temp_file}" "${Z_MACHINES_FILE}"

    echo "Renamed this machine to: ${name}"
}
