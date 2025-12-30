#!/usr/bin/env zsh
# Z modules module - Module registry management

# Module dispatcher
_z_modules() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        list|ls|"")
            _z_modules_list
            ;;
        search)
            _z_modules_search "$@"
            ;;
        add|install)
            _z_modules_add "$@"
            ;;
        rm|remove|uninstall)
            _z_modules_rm "$@"
            ;;
        update)
            _z_modules_update "$@"
            ;;
        help|--help|-h)
            _z_modules_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z modules help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_modules_help() {
    cat <<'EOF'
z modules - Module registry management

Usage: z modules <command> [args]

Commands:
  list              List installed modules (default)
  search <query>    Search the module registry
  add <name>        Download and install a module
  rm <name>         Remove an installed module
  update [name]     Update modules (all or specific)
  help              Show this help

Examples:
  z modules                    List all modules
  z modules search fzf         Search for fzf-related modules
  z modules add fzf            Install the fzf module
  z modules rm fzf             Remove the fzf module
  z modules update             Update all installed modules
  z modules update fzf         Update just the fzf module

Registry: Modules are downloaded from GitHub.
Override with: export Z_REGISTRY_URL="https://..."
EOF
}

# Search the registry
_z_modules_search() {
    local query="$1"

    if [[ -z "${query}" ]]; then
        echo "Usage: z modules search <query>"
        return 1
    fi

    echo "Searching registry for '${query}'..."
    echo ""

    # Fetch registry (with caching)
    local registry_data
    if ! registry_data=$(_z_fetch_registry); then
        echo "Error: Failed to fetch registry"
        return 1
    fi

    # Parse and search modules
    local found=0
    local in_module=false
    local name="" description="" version=""

    echo "$registry_data" | while IFS= read -r line; do
        if [[ "${line}" =~ '"name": "([^"]+)"' ]]; then
            name="${match[1]}"
        elif [[ "${line}" =~ '"description": "([^"]+)"' ]]; then
            description="${match[1]}"
        elif [[ "${line}" =~ '"version": "([^"]+)"' ]]; then
            version="${match[1]}"
        elif [[ "${line}" =~ '^\s*\}' && -n "${name}" ]]; then
            # Check if matches query
            if [[ "${name}" == *"${query}"* ]] || [[ "${description}" == *"${query}"* ]]; then
                local installed=""
                if _z_module_installed "${name}"; then
                    installed=" (installed)"
                fi
                echo "  ${name} (v${version})${installed}"
                echo "    ${description}"
                echo ""
                ((found++))
            fi
            name="" description="" version=""
        fi
    done

    if [[ ${found} -eq 0 ]]; then
        echo "No modules found matching '${query}'"
        return 1
    fi
}

# Fetch registry with caching
_z_fetch_registry() {
    local cache_age=3600  # 1 hour

    # Check cache
    if [[ -f "${Z_REGISTRY_CACHE}" ]]; then
        local cache_time=$(stat -f%m "${Z_REGISTRY_CACHE}" 2>/dev/null || stat -c%Y "${Z_REGISTRY_CACHE}" 2>/dev/null)
        local now=$(date +%s)
        if (( now - cache_time < cache_age )); then
            cat "${Z_REGISTRY_CACHE}"
            return 0
        fi
    fi

    # Fetch from remote
    local url="${Z_REGISTRY_URL}/registry.json"
    local data
    if data=$(curl -fsSL "${url}" 2>/dev/null); then
        echo "${data}" > "${Z_REGISTRY_CACHE}"
        echo "${data}"
        return 0
    else
        # Return cached version if fetch fails
        if [[ -f "${Z_REGISTRY_CACHE}" ]]; then
            cat "${Z_REGISTRY_CACHE}"
            return 0
        fi
        return 1
    fi
}

# Add/install a module
_z_modules_add() {
    local name="$1"

    if [[ -z "${name}" ]]; then
        echo "Usage: z modules add <module-name>"
        return 1
    fi

    # Check if already installed
    if _z_module_installed "${name}"; then
        echo "Module '${name}' is already installed."
        printf "Reinstall? [y/N] "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        rm -rf "${Z_MODULES_DIR}/${name}"
    fi

    echo "Installing module '${name}'..."

    # Create modules directory
    [[ ! -d "${Z_MODULES_DIR}" ]] && mkdir -p "${Z_MODULES_DIR}"

    # Fetch module.json first to get metadata
    local module_url="${Z_REGISTRY_URL}/modules/${name}"
    local module_json
    if ! module_json=$(curl -fsSL "${module_url}/module.json" 2>/dev/null); then
        echo "Error: Module '${name}' not found in registry"
        return 1
    fi

    # Create module directory
    local module_dir="${Z_MODULES_DIR}/${name}"
    mkdir -p "${module_dir}"

    # Save module.json
    echo "${module_json}" > "${module_dir}/module.json"

    # Get install file from module.json
    local install_file=$(echo "${module_json}" | grep '"install"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    [[ -z "${install_file}" ]] && install_file="${name}.zsh"

    # Download main file
    if ! curl -fsSL "${module_url}/${install_file}" -o "${module_dir}/${install_file}" 2>/dev/null; then
        echo "Error: Failed to download module file"
        rm -rf "${module_dir}"
        return 1
    fi

    # Check for additional files in module.json
    local files=$(echo "${module_json}" | grep '"files"' -A10 | grep -o '"[^"]*\.zsh"' | tr -d '"')
    for file in ${files}; do
        if [[ "${file}" != "${install_file}" ]]; then
            curl -fsSL "${module_url}/${file}" -o "${module_dir}/${file}" 2>/dev/null
        fi
    done

    # Get version
    local version=$(echo "${module_json}" | grep '"version"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    local description=$(echo "${module_json}" | grep '"description"' | sed 's/.*: *"\([^"]*\)".*/\1/')

    echo "Installed ${name} v${version}"
    echo "  ${description}"

    # Enable the module
    if ! _z_module_enabled "${name}"; then
        # Add to enabled modules
        source "${Z_CONFIG}"
        Z_ENABLED_MODULES+=("${name}")
        cat > "${Z_CONFIG}" <<EOF
# Z configuration
# Enabled modules
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(${Z_ENABLED_MODULES[*]})
EOF
        echo "  Module enabled"
    fi

    # Source the module immediately
    source "${module_dir}/${install_file}"
    Z_AVAILABLE_MODULES+=("${name}")

    echo ""
    echo "Run 'z ${name}' to use the module"
}

# Remove a module
_z_modules_rm() {
    local name="$1"

    if [[ -z "${name}" ]]; then
        echo "Usage: z modules rm <module-name>"
        return 1
    fi

    # Check if it's a built-in module
    if [[ " ${Z_BUILTIN_MODULES[*]} " == *" ${name} "* ]]; then
        echo "Error: Cannot remove built-in module '${name}'"
        echo "You can disable it with: z disable ${name}"
        return 1
    fi

    # Check if installed
    if ! _z_module_installed "${name}"; then
        echo "Error: Module '${name}' is not installed"
        return 1
    fi

    # Remove from enabled modules
    if _z_module_enabled "${name}"; then
        source "${Z_CONFIG}"
        Z_ENABLED_MODULES=("${(@)Z_ENABLED_MODULES:#${name}}")
        cat > "${Z_CONFIG}" <<EOF
# Z configuration
# Enabled modules
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(${Z_ENABLED_MODULES[*]})
EOF
    fi

    # Remove module directory
    rm -rf "${Z_MODULES_DIR}/${name}"

    echo "Removed module: ${name}"
}

# Update modules
_z_modules_update() {
    local name="$1"

    if [[ -n "${name}" ]]; then
        # Update specific module
        if ! _z_module_installed "${name}"; then
            echo "Error: Module '${name}' is not installed"
            return 1
        fi
        echo "Updating ${name}..."
        _z_modules_add "${name}"
    else
        # Update all installed modules
        local installed=($(_z_get_installed_modules))
        if [[ ${#installed[@]} -eq 0 ]]; then
            echo "No installed modules to update"
            return 0
        fi

        echo "Updating ${#installed[@]} module(s)..."
        echo ""

        for module in ${installed[@]}; do
            echo "Updating ${module}..."
            _z_modules_add "${module}"
            echo ""
        done

        echo "All modules updated"
    fi
}
