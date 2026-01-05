#!/usr/bin/env zsh
# Z alias module - Shell alias manager

# Module dispatcher
_z_alias() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        add)
            _z_alias_add "$@"
            ;;
        list|ls)
            _z_alias_list "$@"
            ;;
        rm|remove)
            _z_alias_rm "$@"
            ;;
        edit)
            _z_alias_edit "$@"
            ;;
        help|--help|-h|"")
            _z_alias_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z alias help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_alias_help() {
    cat <<'EOF'
z alias - Shell alias manager

Usage: z alias <command> [args]

Commands:
  add NAME CMD      Add an alias
      -d, --desc      Add description
  list, ls          List all aliases
  rm NAME           Remove an alias
  edit              Open aliases.zsh in $EDITOR
  help              Show this help

Examples:
  z alias add ls "eza -l" -d "List with eza"
  z alias add g "git" -d "Git shortcut"
  z alias add k "kubectl"
  z alias list
  z alias rm g
EOF
}

# Add an alias
_z_alias_add() {
    local name=""
    local command=""
    local description=""
    local aliases_file="${Z_DIR}/alias/aliases.zsh"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--desc)
                description="$2"
                shift 2
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                elif [[ -z "${command}" ]]; then
                    command="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No alias name provided"
        echo "Usage: z alias add NAME COMMAND [-d|--desc \"description\"]"
        return 1
    fi

    if [[ -z "${command}" ]]; then
        echo "Error: No command provided"
        echo "Usage: z alias add NAME COMMAND [-d|--desc \"description\"]"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -f "${aliases_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Check if alias already exists
    if grep -q "^# \[${name}\]" "${aliases_file}" 2>/dev/null; then
        echo "Alias '${name}' already exists."
        printf "Overwrite? [y/N] "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        # Remove existing alias
        _z_alias_remove_entry "${name}"
    fi

    # Build comment line
    local comment_line="# [${name}]"
    if [[ -n "${description}" ]]; then
        comment_line="${comment_line} ${description}"
    fi

    # Escape double quotes in command for alias definition
    local escaped_command="${command//\"/\\\"}"

    # Append to aliases file
    echo "${comment_line}" >> "${aliases_file}"
    echo "alias ${name}=\"${escaped_command}\"" >> "${aliases_file}"

    # Apply immediately in current shell
    alias "${name}=${command}"

    echo "Added alias ${name}=\"${command}\""
}

# Internal function to remove an entry from aliases file
_z_alias_remove_entry() {
    local name="$1"
    local aliases_file="${Z_DIR}/alias/aliases.zsh"
    local temp_file="${aliases_file}.tmp"

    # Remove the comment line and the following alias line
    awk -v name="${name}" '
        /^# \['"${name}"'\]/ { skip = 1; next }
        skip && /^alias '"${name}"'=/ { skip = 0; next }
        { print }
    ' "${aliases_file}" > "${temp_file}"

    mv "${temp_file}" "${aliases_file}"
}

# List all aliases
_z_alias_list() {
    local aliases_file="${Z_DIR}/alias/aliases.zsh"
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
        _z_alias_list_remote "${machine}" "${json_output}"
        return $?
    fi

    # Check if z is initialized
    if [[ ! -f "${aliases_file}" ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "Error: Z not initialized. Run 'z init' first."
        fi
        return 1
    fi

    # Count entries
    local count=$(grep -c "^# \[" "${aliases_file}" 2>/dev/null || echo 0)

    if [[ "${count}" -eq 0 ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "No aliases set."
            echo "Add one with: z alias add NAME COMMAND"
        fi
        return 0
    fi

    # JSON output
    if [[ "${json_output}" == true ]]; then
        _z_alias_list_json
        return 0
    fi

    echo "Aliases (${count}):"
    echo ""
    printf "%-15s %-50s %s\n" "NAME" "COMMAND" "DESCRIPTION"
    printf "%-15s %-50s %s\n" "----" "-------" "-----------"

    local current_name=""
    local current_desc=""

    while IFS= read -r line; do
        if [[ "${line}" =~ "^# \[([^]]+)\](.*)$" ]]; then
            current_name="${match[1]}"
            current_desc="${match[2]}"
            # Trim leading space from description
            current_desc="${current_desc## }"
        elif [[ "${line}" =~ '^alias ([^=]+)="(.*)"$' && -n "${current_name}" ]]; then
            local alias_name="${match[1]}"
            local alias_cmd="${match[2]}"

            # Truncate command if too long
            if [[ ${#alias_cmd} -gt 50 ]]; then
                alias_cmd="${alias_cmd:0:47}..."
            fi

            # Truncate description if too long
            if [[ ${#current_desc} -gt 30 ]]; then
                current_desc="${current_desc:0:27}..."
            fi

            printf "%-15s %-50s %s\n" "${current_name}" "${alias_cmd}" "${current_desc}"

            current_name=""
            current_desc=""
        fi
    done < "${aliases_file}"
}

# Output alias list as JSON
_z_alias_list_json() {
    local aliases_file="${Z_DIR}/alias/aliases.zsh"
    local first=true
    local current_name=""
    local current_desc=""

    echo "["

    while IFS= read -r line; do
        if [[ "${line}" =~ "^# \[([^]]+)\](.*)$" ]]; then
            current_name="${match[1]}"
            current_desc="${match[2]}"
            current_desc="${current_desc## }"
        elif [[ "${line}" =~ '^alias ([^=]+)="(.*)"$' && -n "${current_name}" ]]; then
            local alias_name="${match[1]}"
            local alias_cmd="${match[2]}"

            # Escape JSON special characters
            alias_cmd="${alias_cmd//\\/\\\\}"
            alias_cmd="${alias_cmd//\"/\\\"}"
            current_desc="${current_desc//\\/\\\\}"
            current_desc="${current_desc//\"/\\\"}"

            if [[ "${first}" == true ]]; then
                first=false
            else
                echo ","
            fi

            printf '  {"name": "%s", "command": "%s", "description": "%s"}' \
                "${current_name}" "${alias_cmd}" "${current_desc}"

            current_name=""
            current_desc=""
        fi
    done < "${aliases_file}"

    echo ""
    echo "]"
}

# List aliases from remote machine
_z_alias_list_remote() {
    local machine="$1"
    local json_output="$2"

    # Handle "all" machines
    if [[ "${machine}" == "all" ]]; then
        _z_alias_list_all "${json_output}"
        return $?
    fi

    # Get remote data via SSH
    local remote_data
    if ! remote_data=$(_z_remote_exec "${machine}" "alias list --json" 2>&1); then
        echo "Error: Failed to connect to '${machine}'" >&2
        return 1
    fi

    if [[ "${json_output}" == true ]]; then
        echo "${remote_data}"
    else
        # Parse JSON and display formatted
        echo "Aliases from ${machine}:"
        echo ""
        printf "%-15s %-50s %s\n" "NAME" "COMMAND" "DESCRIPTION"
        printf "%-15s %-50s %s\n" "----" "-------" "-----------"

        echo "${remote_data}" | while IFS= read -r line; do
            if [[ "${line}" =~ '"name": "([^"]+)".*"command": "([^"]*)".*"description": "([^"]*)"' ]]; then
                local name="${match[1]}"
                local cmd="${match[2]}"
                local desc="${match[3]}"

                # Truncate if needed
                [[ ${#cmd} -gt 50 ]] && cmd="${cmd:0:47}..."
                [[ ${#desc} -gt 30 ]] && desc="${desc:0:27}..."

                printf "%-15s %-50s %s\n" "${name}" "${cmd}" "${desc}"
            fi
        done
    fi
}

# List aliases from all machines
_z_alias_list_all() {
    local json_output="$1"
    local this_machine=$(_z_this_machine)

    if [[ "${json_output}" == true ]]; then
        echo "{"
        echo "  \"${this_machine}\": $(_z_alias_list_json)"

        if [[ -f "${Z_MACHINES_FILE}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
                    local name="${match[1]}"
                    local remote_data=$(_z_remote_exec "${name}" "alias list --json" 2>/dev/null)
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
        _z_alias_list
        echo ""

        if [[ -f "${Z_MACHINES_FILE}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
                    local name="${match[1]}"
                    echo "=== ${name} ==="
                    _z_alias_list_remote "${name}" false
                    echo ""
                fi
            done < "${Z_MACHINES_FILE}"
        fi
    fi
}

# Remove an alias
_z_alias_rm() {
    local name="$1"
    local aliases_file="${Z_DIR}/alias/aliases.zsh"

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No alias name provided"
        echo "Usage: z alias rm NAME"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -f "${aliases_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Check if alias exists
    if ! grep -q "^# \[${name}\]" "${aliases_file}" 2>/dev/null; then
        echo "Error: Alias '${name}' not found"
        echo "Run 'z alias list' to see all aliases"
        return 1
    fi

    # Remove from file
    _z_alias_remove_entry "${name}"

    # Unalias in current shell
    unalias "${name}" 2>/dev/null

    echo "Removed ${name}"
}

# Edit aliases file in $EDITOR
_z_alias_edit() {
    local aliases_file="${Z_DIR}/alias/aliases.zsh"

    if [[ ! -f "${aliases_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    ${EDITOR:-vim} "${aliases_file}"
    echo "Remember to run: source ~/.zshrc"
}
