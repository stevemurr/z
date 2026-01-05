#!/usr/bin/env zsh
# Z env module - Environment variable manager

# Module dispatcher
_z_env() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        add)
            _z_env_add "$@"
            ;;
        list|ls)
            _z_env_list "$@"
            ;;
        rm|remove)
            _z_env_rm "$@"
            ;;
        copy)
            _z_env_copy "$@"
            ;;
        push)
            _z_env_push "$@"
            ;;
        edit)
            _z_env_edit "$@"
            ;;
        help|--help|-h|"")
            _z_env_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z env help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_env_help() {
    cat <<'EOF'
z env - Environment variable manager

Usage: z env <command> [args]

Commands:
  add NAME VALUE    Add or update a variable
      -s, --secret    Mark as secret (masked in list)
      -d, --desc      Add description
  list, ls          List all variables
      --json          Output as JSON
      -m, --machine   Query from specific machine (or "all")
  copy NAME         Copy a variable's value to clipboard
      -m, --machine   Source machine (default: local)
  push NAME         Push a local variable to a remote machine
      -m, --machine   Target machine (required)
  rm NAME           Remove a variable
  edit              Open vars.zsh in $EDITOR
  help              Show this help

Examples:
  z env add API_KEY "sk-xxx" -s -d "OpenAI key"
  z env add SERVER "https://api.example.com"
  z env list
  z env list -m work
  z env list -m all
  z env copy API_KEY            # copy local var to clipboard
  z env copy API_KEY -m work    # copy from remote machine
  z env push DEBUG_MODE -m server
  z env rm API_KEY
EOF
}

# Add or update an environment variable
_z_env_add() {
    local name=""
    local value=""
    local secret=false
    local description=""
    local vars_file="${Z_DIR}/env/vars.zsh"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--secret)
                secret=true
                shift
                ;;
            -d|--desc)
                description="$2"
                shift 2
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                elif [[ -z "${value}" ]]; then
                    value="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No variable name provided"
        echo "Usage: z env add NAME VALUE [-s|--secret] [-d|--desc \"description\"]"
        return 1
    fi

    if [[ -z "${value}" ]]; then
        echo "Error: No value provided"
        echo "Usage: z env add NAME VALUE [-s|--secret] [-d|--desc \"description\"]"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -f "${vars_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Check if variable already exists
    if grep -q "^export ${name}=" "${vars_file}" 2>/dev/null; then
        echo "Variable '${name}' already exists."
        printf "Overwrite? [y/N] "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        # Remove existing variable (both comment and export lines)
        _z_env_remove_var "${name}"
    fi

    # Build comment line
    local comment_line="#"
    if [[ "${secret}" == true ]]; then
        comment_line="${comment_line} [secret]"
    fi
    if [[ -n "${description}" ]]; then
        comment_line="${comment_line} ${description}"
    else
        comment_line="${comment_line} ${name}"
    fi

    # Append to vars file
    echo "${comment_line}" >> "${vars_file}"
    echo "export ${name}=\"${value}\"" >> "${vars_file}"

    # Export immediately in current shell
    export "${name}=${value}"

    local display_value="${value}"
    if [[ "${secret}" == true ]]; then
        display_value="****"
    fi

    echo "Added ${name}=${display_value}"
}

# Internal function to remove a variable from vars file
_z_env_remove_var() {
    local name="$1"
    local vars_file="${Z_DIR}/env/vars.zsh"
    local temp_file="${vars_file}.tmp"

    # Remove the export line and its preceding comment
    awk -v var="${name}" '
        /^#/ { comment = $0; next }
        /^export '"${name}"'=/ { next }
        { if (comment != "") print comment; print; comment = "" }
    ' "${vars_file}" > "${temp_file}"

    mv "${temp_file}" "${vars_file}"
}

# List all environment variables
_z_env_list() {
    local vars_file="${Z_DIR}/env/vars.zsh"
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
        _z_env_list_remote "${machine}" "${json_output}"
        return $?
    fi

    # Check if z is initialized
    if [[ ! -f "${vars_file}" ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "Error: Z not initialized. Run 'z init' first."
        fi
        return 1
    fi

    # Count variables
    local count=$(grep -c "^export " "${vars_file}" 2>/dev/null || echo 0)

    if [[ "${count}" -eq 0 ]]; then
        if [[ "${json_output}" == true ]]; then
            echo "[]"
        else
            echo "No environment variables set."
            echo "Add one with: z env add NAME VALUE"
        fi
        return 0
    fi

    # JSON output
    if [[ "${json_output}" == true ]]; then
        _z_env_list_json
        return 0
    fi

    echo "Environment variables (${count}):"
    echo ""
    printf "%-25s %-50s %s\n" "NAME" "VALUE" "DESCRIPTION"
    printf "%-25s %-50s %s\n" "----" "-----" "-----------"

    local current_comment=""
    local is_secret=false

    while IFS= read -r line; do
        if [[ "${line}" =~ ^#\ (.*)$ ]]; then
            current_comment="${match[1]}"
            if [[ "${current_comment}" == \[secret\]* ]]; then
                is_secret=true
                current_comment="${current_comment#\[secret\]}"
            else
                is_secret=false
            fi
            # Trim leading space
            current_comment="${current_comment## }"
        elif [[ "${line}" =~ ^export\ ([^=]+)=\"(.*)\"$ ]]; then
            local var_name="${match[1]}"
            local var_value="${match[2]}"

            # Mask secret values
            if [[ "${is_secret}" == true ]]; then
                var_value="****"
            fi

            # Truncate value if too long
            if [[ ${#var_value} -gt 50 ]]; then
                var_value="${var_value:0:47}..."
            fi

            # Truncate description if too long
            local desc="${current_comment}"
            if [[ ${#desc} -gt 30 ]]; then
                desc="${desc:0:27}..."
            fi

            printf "%-25s %-50s %s\n" "${var_name}" "${var_value}" "${desc}"

            current_comment=""
            is_secret=false
        fi
    done < "${vars_file}"
}

# Output env list as JSON
_z_env_list_json() {
    local vars_file="${Z_DIR}/env/vars.zsh"
    local first=true
    local current_comment=""
    local is_secret=false

    echo "["

    while IFS= read -r line; do
        if [[ "${line}" =~ ^#\ (.*)$ ]]; then
            current_comment="${match[1]}"
            if [[ "${current_comment}" == \[secret\]* ]]; then
                is_secret=true
                current_comment="${current_comment#\[secret\]}"
            else
                is_secret=false
            fi
            current_comment="${current_comment## }"
        elif [[ "${line}" =~ ^export\ ([^=]+)=\"(.*)\"$ ]]; then
            local var_name="${match[1]}"
            local var_value="${match[2]}"

            # Mask secret values
            if [[ "${is_secret}" == true ]]; then
                var_value="****"
            fi

            # Escape JSON special characters
            var_value="${var_value//\\/\\\\}"
            var_value="${var_value//\"/\\\"}"
            current_comment="${current_comment//\\/\\\\}"
            current_comment="${current_comment//\"/\\\"}"

            if [[ "${first}" == true ]]; then
                first=false
            else
                echo ","
            fi

            printf '  {"name": "%s", "value": "%s", "secret": %s, "description": "%s"}' \
                "${var_name}" "${var_value}" "${is_secret}" "${current_comment}"

            current_comment=""
            is_secret=false
        fi
    done < "${vars_file}"

    echo ""
    echo "]"
}

# List env vars from remote machine
_z_env_list_remote() {
    local machine="$1"
    local json_output="$2"

    # Handle "all" machines
    if [[ "${machine}" == "all" ]]; then
        _z_env_list_all "${json_output}"
        return $?
    fi

    # Get remote data via SSH
    local remote_data
    if ! remote_data=$(_z_remote_exec "${machine}" "env list --json" 2>&1); then
        echo "Error: Failed to connect to '${machine}'" >&2
        return 1
    fi

    if [[ "${json_output}" == true ]]; then
        echo "${remote_data}"
    else
        # Parse JSON and display formatted
        echo "Environment variables from ${machine}:"
        echo ""
        printf "%-25s %-50s %s\n" "NAME" "VALUE" "DESCRIPTION"
        printf "%-25s %-50s %s\n" "----" "-----" "-----------"

        echo "${remote_data}" | while IFS= read -r line; do
            if [[ "${line}" =~ '"name": "([^"]+)".*"value": "([^"]*)".*"description": "([^"]*)"' ]]; then
                local name="${match[1]}"
                local value="${match[2]}"
                local desc="${match[3]}"

                # Truncate if needed
                [[ ${#value} -gt 50 ]] && value="${value:0:47}..."
                [[ ${#desc} -gt 30 ]] && desc="${desc:0:27}..."

                printf "%-25s %-50s %s\n" "${name}" "${value}" "${desc}"
            fi
        done
    fi
}

# List env vars from all machines
_z_env_list_all() {
    local json_output="$1"
    local this_machine=$(_z_this_machine)

    if [[ "${json_output}" == true ]]; then
        echo "{"
        echo "  \"${this_machine}\": $(_z_env_list_json)"

        # Get all remote machines
        if [[ -f "${Z_MACHINES_FILE}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
                    local name="${match[1]}"
                    local remote_data=$(_z_remote_exec "${name}" "env list --json" 2>/dev/null)
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
        _z_env_list
        echo ""

        # Query all remote machines
        if [[ -f "${Z_MACHINES_FILE}" ]]; then
            while IFS= read -r line; do
                if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
                    local name="${match[1]}"
                    echo "=== ${name} ==="
                    _z_env_list_remote "${name}" false
                    echo ""
                fi
            done < "${Z_MACHINES_FILE}"
        fi
    fi
}

# Remove an environment variable
_z_env_rm() {
    local name="$1"
    local vars_file="${Z_DIR}/env/vars.zsh"

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No variable name provided"
        echo "Usage: z env rm NAME"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -f "${vars_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Check if variable exists
    if ! grep -q "^export ${name}=" "${vars_file}" 2>/dev/null; then
        echo "Error: Variable '${name}' not found"
        echo "Run 'z env list' to see all variables"
        return 1
    fi

    # Remove from file
    _z_env_remove_var "${name}"

    # Unset in current shell
    unset "${name}"

    echo "Removed ${name}"
}

# Edit vars file in $EDITOR
_z_env_edit() {
    local vars_file="${Z_DIR}/env/vars.zsh"

    if [[ ! -f "${vars_file}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    ${EDITOR:-vim} "${vars_file}"
    echo "Remember to run: source ~/.zshrc"
}

# Copy to clipboard (cross-platform)
_z_copy_to_clipboard() {
    local text="$1"
    if command -v pbcopy &>/dev/null; then
        echo -n "${text}" | pbcopy
    elif command -v xclip &>/dev/null; then
        echo -n "${text}" | xclip -selection clipboard
    elif command -v xsel &>/dev/null; then
        echo -n "${text}" | xsel --clipboard --input
    else
        echo "Error: No clipboard utility found (pbcopy, xclip, or xsel)"
        return 1
    fi
}

# Copy a variable's value to clipboard
_z_env_copy() {
    local name=""
    local machine=""
    local vars_file="${Z_DIR}/env/vars.zsh"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--machine)
                machine="$2"
                shift 2
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No variable name provided"
        echo "Usage: z env copy NAME [-m MACHINE]"
        return 1
    fi

    local value=""
    local is_secret=false

    if [[ -z "${machine}" ]]; then
        # Copy from local
        if [[ ! -f "${vars_file}" ]]; then
            echo "Error: Z not initialized. Run 'z init' first."
            return 1
        fi

        # Check if variable exists locally
        if ! grep -q "^export ${name}=" "${vars_file}" 2>/dev/null; then
            echo "Error: Variable '${name}' not found"
            echo "Run 'z env list' to see all variables"
            return 1
        fi

        # Get local variable info
        local prev_line=""
        while IFS= read -r line; do
            if [[ "${line}" =~ ^#\ (.*)$ ]]; then
                prev_line="${match[1]}"
            elif [[ "${line}" =~ ^export\ ${name}=\"(.*)\"$ ]]; then
                value="${match[1]}"
                if [[ "${prev_line}" == \[secret\]* ]]; then
                    is_secret=true
                fi
                break
            fi
        done < "${vars_file}"

        if [[ "${is_secret}" == true ]]; then
            echo "Error: Cannot copy secret variable '${name}'"
            return 1
        fi
    else
        # Copy from remote machine
        local remote_data
        if ! remote_data=$(_z_remote_exec "${machine}" "env list --json" 2>&1); then
            echo "Error: Failed to connect to '${machine}'"
            return 1
        fi

        # Check if variable exists
        if ! echo "${remote_data}" | grep -q "\"name\": \"${name}\""; then
            echo "Error: Variable '${name}' not found on ${machine}"
            return 1
        fi

        # Get the full JSON object for this variable
        local var_json=$(echo "${remote_data}" | tr -d '\n' | sed 's/},/}\n/g' | grep "\"name\": \"${name}\"")

        if [[ "${var_json}" =~ '"secret": true' ]]; then
            echo "Error: Cannot copy secret variable '${name}'"
            echo "Secret values are not transmitted for security reasons"
            return 1
        fi

        # Extract value
        if [[ "${var_json}" =~ '"value": "([^"]*)"' ]]; then
            value="${match[1]}"
        fi
    fi

    # Copy to clipboard
    if _z_copy_to_clipboard "${value}"; then
        if [[ -n "${machine}" ]]; then
            echo "Copied ${name} from ${machine} to clipboard"
        else
            echo "Copied ${name} to clipboard"
        fi
    fi
}

# Push a local variable to a remote machine
_z_env_push() {
    local name=""
    local machine=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--machine)
                machine="$2"
                shift 2
                ;;
            *)
                if [[ -z "${name}" ]]; then
                    name="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "${name}" ]]; then
        echo "Error: No variable name provided"
        echo "Usage: z env push NAME -m MACHINE"
        return 1
    fi

    if [[ -z "${machine}" ]]; then
        echo "Error: No machine specified"
        echo "Usage: z env push NAME -m MACHINE"
        return 1
    fi

    local vars_file="${Z_DIR}/env/vars.zsh"

    # Check if variable exists locally
    if ! grep -q "^export ${name}=" "${vars_file}" 2>/dev/null; then
        echo "Error: Variable '${name}' not found locally"
        echo "Run 'z env list' to see all variables"
        return 1
    fi

    # Get local variable info
    local value=""
    local is_secret=false
    local description=""
    local prev_line=""

    while IFS= read -r line; do
        if [[ "${line}" =~ ^#\ (.*)$ ]]; then
            prev_line="${match[1]}"
        elif [[ "${line}" =~ ^export\ ${name}=\"(.*)\"$ ]]; then
            value="${match[1]}"
            if [[ "${prev_line}" == \[secret\]* ]]; then
                is_secret=true
                description="${prev_line#\[secret\]}"
                description="${description## }"
            else
                description="${prev_line}"
            fi
            break
        fi
    done < "${vars_file}"

    if [[ "${is_secret}" == true ]]; then
        echo "Error: Cannot push secret variable '${name}'"
        echo "Secret values should be set manually on each machine"
        return 1
    fi

    # Escape value for remote command
    local escaped_value="${value//\"/\\\"}"
    local escaped_value="${escaped_value//\$/\\\$}"

    # Build remote command
    local remote_cmd="env add \"${name}\" \"${escaped_value}\""
    [[ -n "${description}" ]] && remote_cmd="${remote_cmd} -d \"${description}\""

    # Execute on remote
    if ! _z_remote_exec "${machine}" "${remote_cmd}" 2>&1; then
        echo "Error: Failed to push to '${machine}'"
        return 1
    fi

    echo "Pushed ${name} to ${machine}"
}
