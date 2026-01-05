#!/usr/bin/env zsh
# Z path module - PATH entry manager

# Module dispatcher
_z_path() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        add)
            _z_path_add "$@"
            ;;
        list|ls)
            _z_path_list "$@"
            ;;
        rm|remove)
            _z_path_rm "$@"
            ;;
        edit)
            _z_path_edit "$@"
            ;;
        help|--help|-h|"")
            _z_path_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z path help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_path_help() {
    cat <<'EOF'
z path - PATH entry manager

Usage: z path <command> [args]

Commands:
  add NAME PATH     Add a path entry
      -d, --desc      Add description
      -p, --prepend   Prepend to PATH (default)
      -a, --append    Append to PATH instead
  list, ls          List all path entries
  rm NAME           Remove a path entry
  edit              Open paths.zsh in $EDITOR
  help              Show this help

Examples:
  z path add golang "$HOME/go/bin" -d "Go binaries"
  z path add lmstudio "$HOME/.lmstudio/bin"
  z path list
  z path rm golang
EOF
}

# Add a path entry
_z_path_add() {
    local name=""
    local path_value=""
    local description=""
    local prepend=true
    local paths_file="${Z_DIR}/path/paths.zsh"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--desc)
                description="$2"
                shift 2
                ;;
            -p|--prepend)
                prepend=true
                shift
                ;;
            -a|--append)
                prepend=false
                shift
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                elif [[ -z "${path_value}" ]]; then
                    path_value="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No name provided"
        echo "Usage: z path add NAME PATH [-d|--desc \"description\"]"
        return 1
    fi

    if [[ -z "${path_value}" ]]; then
        echo "Error: No path provided"
        echo "Usage: z path add NAME PATH [-d|--desc \"description\"]"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -f "${paths_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Check if entry already exists
    if grep -q "^# \[${name}\]" "${paths_file}" 2>/dev/null; then
        echo "Path entry '${name}' already exists."
        printf "Overwrite? [y/N] "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        # Remove existing entry
        _z_path_remove_entry "${name}"
    fi

    # Build comment line
    local comment_line="# [${name}]"
    if [[ -n "${description}" ]]; then
        comment_line="${comment_line} ${description}"
    fi

    # Build export line
    local export_line
    if [[ "${prepend}" == true ]]; then
        export_line="export PATH=\"${path_value}:\${PATH}\""
    else
        export_line="export PATH=\"\${PATH}:${path_value}\""
    fi

    # Append to paths file
    echo "${comment_line}" >> "${paths_file}"
    echo "${export_line}" >> "${paths_file}"

    # Apply immediately in current shell
    if [[ "${prepend}" == true ]]; then
        export PATH="${path_value}:${PATH}"
    else
        export PATH="${PATH}:${path_value}"
    fi

    echo "Added ${name}: ${path_value}"
}

# Internal function to remove an entry from paths file
_z_path_remove_entry() {
    local name="$1"
    local paths_file="${Z_DIR}/path/paths.zsh"
    local temp_file="${paths_file}.tmp"

    # Remove the comment line and the following export line
    awk -v name="${name}" '
        /^# \['"${name}"'\]/ { skip = 1; next }
        skip && /^export PATH=/ { skip = 0; next }
        { print }
    ' "${paths_file}" > "${temp_file}"

    mv "${temp_file}" "${paths_file}"
}

# List all path entries
_z_path_list() {
    local paths_file="${Z_DIR}/path/paths.zsh"
    local json_output=false
    local machine=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=true
                shift
                ;;
            -m|--machine)
                machine="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Handle remote machine query
    if [[ -n "${machine}" ]]; then
        _z_path_list_remote "${machine}" "${json_output}"
        return $?
    fi

    # Check if z is initialized
    if [[ ! -f "${paths_file}" ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "Error: Z not initialized. Run 'z init' first."
        fi
        return 1
    fi

    # Count entries
    local count=$(grep -c "^# \[" "${paths_file}" 2>/dev/null || echo 0)

    if [[ "${count}" -eq 0 ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "No path entries set."
            echo "Add one with: z path add NAME PATH"
        fi
        return 0
    fi

    # JSON output
    if [[ "${json_output}" == true ]]; then
        _z_path_list_json
        return 0
    fi

    echo "PATH entries (${count}):"
    echo ""
    printf "%-20s %-50s %s\n" "NAME" "PATH" "DESCRIPTION"
    printf "%-20s %-50s %s\n" "----" "----" "-----------"

    local current_name=""
    local current_desc=""

    while IFS= read -r line; do
        if [[ "${line}" =~ "^# \[([^]]+)\](.*)$" ]]; then
            current_name="${match[1]}"
            current_desc="${match[2]}"
            # Trim leading space from description
            current_desc="${current_desc## }"
        elif [[ "${line}" =~ '^export PATH="([^"]+)"' && -n "${current_name}" ]]; then
            local path_expr="${match[1]}"
            # Extract the actual path (remove :${PATH} or ${PATH}:)
            local actual_path="${path_expr//:\$\{PATH\}/}"
            actual_path="${actual_path//\$\{PATH\}:/}"

            # Truncate path if too long
            if [[ ${#actual_path} -gt 50 ]]; then
                actual_path="${actual_path:0:47}..."
            fi

            # Truncate description if too long
            if [[ ${#current_desc} -gt 30 ]]; then
                current_desc="${current_desc:0:27}..."
            fi

            printf "%-20s %-50s %s\n" "${current_name}" "${actual_path}" "${current_desc}"

            current_name=""
            current_desc=""
        fi
    done < "${paths_file}"
}

# Output path list as JSON
_z_path_list_json() {
    local paths_file="${Z_DIR}/path/paths.zsh"
    local first=true
    local current_name=""
    local current_desc=""

    echo "["

    while IFS= read -r line; do
        if [[ "${line}" =~ "^# \[([^]]+)\](.*)$" ]]; then
            current_name="${match[1]}"
            current_desc="${match[2]}"
            current_desc="${current_desc## }"
        elif [[ "${line}" =~ '^export PATH="([^"]+)"' && -n "${current_name}" ]]; then
            local path_expr="${match[1]}"
            local actual_path="${path_expr//:\$\{PATH\}/}"
            actual_path="${actual_path//\$\{PATH\}:/}"

            # Check if prepend or append
            local position="prepend"
            if [[ "${path_expr}" == \$\{PATH\}:* ]]; then
                position="append"
            fi

            # Escape JSON special characters
            actual_path="${actual_path//\\/\\\\}"
            actual_path="${actual_path//\"/\\\"}"
            current_desc="${current_desc//\\/\\\\}"
            current_desc="${current_desc//\"/\\\"}"

            if [[ "${first}" == true ]]; then
                first=false
            else
                echo ","
            fi

            printf '  {"name": "%s", "path": "%s", "position": "%s", "description": "%s"}' \
                "${current_name}" "${actual_path}" "${position}" "${current_desc}"

            current_name=""
            current_desc=""
        fi
    done < "${paths_file}"

    echo ""
    echo "]"
}

# List paths from remote machine
_z_path_list_remote() {
    local machine="$1"
    local json_output="$2"

    # Handle "all" machines
    if [[ "${machine}" == "all" ]]; then
        _z_path_list_all "${json_output}"
        return $?
    fi

    # Get remote data via SSH
    local remote_data
    if ! remote_data=$(_z_remote_exec "${machine}" "path list --json" 2>&1); then
        echo "Error: Failed to connect to '${machine}'" >&2
        return 1
    fi

    if [[ "${json_output}" == true ]]; then
        echo "${remote_data}"
    else
        # Parse JSON and display formatted
        echo "PATH entries from ${machine}:"
        echo ""
        printf "%-20s %-50s %s\n" "NAME" "PATH" "DESCRIPTION"
        printf "%-20s %-50s %s\n" "----" "----" "-----------"

        echo "${remote_data}" | while IFS= read -r line; do
            if [[ "${line}" =~ '"name": "([^"]+)".*"path": "([^"]*)".*"description": "([^"]*)"' ]]; then
                local name="${match[1]}"
                local path="${match[2]}"
                local desc="${match[3]}"

                # Truncate if needed
                [[ ${#path} -gt 50 ]] && path="${path:0:47}..."
                [[ ${#desc} -gt 30 ]] && desc="${desc:0:27}..."

                printf "%-20s %-50s %s\n" "${name}" "${path}" "${desc}"
            fi
        done
    fi
}

# List paths from all machines
_z_path_list_all() {
    local json_output="$1"
    local this_machine=$(_z_this_machine)

    if [[ "${json_output}" == true ]]; then
        echo "{"
        echo "  \"${this_machine}\": $(_z_path_list_json)"

        if [[ -f "${Z_MACHINES_FILE}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
                    local name="${match[1]}"
                    local remote_data=$(_z_remote_exec "${name}" "path list --json" 2>/dev/null)
                    if [[ -n "${remote_data}" ]]; then
                        echo ","
                        echo "  \"${name}\": ${remote_data}"
                    fi
                fi
            done < "${Z_MACHINES_FILE}"
        fi

        echo "}"
    else
        echo "=== ${this_machine} (local) ==="
        _z_path_list
        echo ""

        if [[ -f "${Z_MACHINES_FILE}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
                    local name="${match[1]}"
                    echo "=== ${name} ==="
                    _z_path_list_remote "${name}" false
                    echo ""
                fi
            done < "${Z_MACHINES_FILE}"
        fi
    fi
}

# Remove a path entry
_z_path_rm() {
    local name="$1"
    local paths_file="${Z_DIR}/path/paths.zsh"

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No name provided"
        echo "Usage: z path rm NAME"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -f "${paths_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Check if entry exists
    if ! grep -q "^# \[${name}\]" "${paths_file}" 2>/dev/null; then
        echo "Error: Path entry '${name}' not found"
        echo "Run 'z path list' to see all entries"
        return 1
    fi

    # Remove from file
    _z_path_remove_entry "${name}"

    echo "Removed ${name}"
    echo "Note: PATH change takes effect in new shells"
}

# Edit paths file in $EDITOR
_z_path_edit() {
    local paths_file="${Z_DIR}/path/paths.zsh"

    if [[ ! -f "${paths_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    ${EDITOR:-vim} "${paths_file}"
    echo "Remember to run: source ~/.zshrc"
}
