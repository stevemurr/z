#!/usr/bin/env zsh
# Z core library - shared utilities

# Data directory
Z_DIR="${HOME}/.z"
Z_CONFIG="${Z_DIR}/config.zsh"
Z_MODULES_DIR="${Z_DIR}/modules"
Z_SYS_DIR="${Z_DIR}/sys"
Z_MACHINES_FILE="${Z_SYS_DIR}/machines.json"

# Module registry URL
Z_REGISTRY_URL="${Z_REGISTRY_URL:-https://raw.githubusercontent.com/stevemurr/z/main/registry}"
Z_REGISTRY_CACHE="${Z_DIR}/registry-cache.json"

# Built-in modules (shipped with z)
typeset -ga Z_BUILTIN_MODULES
Z_BUILTIN_MODULES=(env path alias app bench sys modules)

# Available modules (built-in + installed)
typeset -ga Z_AVAILABLE_MODULES
Z_AVAILABLE_MODULES=(env path alias app bench sys modules)

# Get z data directory
_z_dir() {
    echo "${Z_DIR}"
}

# Read enabled modules from config
_z_get_enabled_modules() {
    if [[ -f "${Z_CONFIG}" ]]; then
        source "${Z_CONFIG}"
        echo "${Z_ENABLED_MODULES[@]}"
    fi
}

# Check if a specific module is enabled
_z_module_enabled() {
    local module="$1"
    if [[ ! -f "${Z_CONFIG}" ]]; then
        return 1
    fi
    source "${Z_CONFIG}"
    [[ " ${Z_ENABLED_MODULES[*]} " == *" ${module} "* ]]
}

# Source all enabled module data files
_z_source_data() {
    [[ -f "${Z_DIR}/env/vars.zsh" ]] && source "${Z_DIR}/env/vars.zsh"
    [[ -f "${Z_DIR}/path/paths.zsh" ]] && source "${Z_DIR}/path/paths.zsh"
    [[ -f "${Z_DIR}/alias/aliases.zsh" ]] && source "${Z_DIR}/alias/aliases.zsh"
    # app module adds its bin to PATH
    [[ -d "${Z_DIR}/app/bin" ]] && export PATH="${Z_DIR}/app/bin:${PATH}"
}

# Load installed (downloaded) modules
_z_load_installed_modules() {
    if [[ -d "${Z_MODULES_DIR}" ]]; then
        for module_dir in "${Z_MODULES_DIR}"/*/; do
            if [[ -d "${module_dir}" ]]; then
                local module_name=$(basename "${module_dir}")
                local module_file="${module_dir}${module_name}.zsh"
                local module_json="${module_dir}module.json"

                # Check if module has required files
                if [[ -f "${module_json}" ]]; then
                    # Get main file from module.json or use default
                    local install_file=$(grep '"install"' "${module_json}" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
                    [[ -z "${install_file}" ]] && install_file="${module_name}.zsh"

                    local full_path="${module_dir}${install_file}"
                    if [[ -f "${full_path}" ]]; then
                        source "${full_path}"
                        # Add to available modules if not already there
                        if [[ ! " ${Z_AVAILABLE_MODULES[*]} " == *" ${module_name} "* ]]; then
                            Z_AVAILABLE_MODULES+=("${module_name}")
                        fi
                    fi
                fi
            fi
        done
    fi
}

# Get list of installed modules
_z_get_installed_modules() {
    local modules=()
    if [[ -d "${Z_MODULES_DIR}" ]]; then
        for module_dir in "${Z_MODULES_DIR}"/*/; do
            if [[ -d "${module_dir}" ]]; then
                modules+=($(basename "${module_dir}"))
            fi
        done
    fi
    echo "${modules[@]}"
}

# Check if a module is installed (downloaded)
_z_module_installed() {
    local module="$1"
    [[ -d "${Z_MODULES_DIR}/${module}" ]] && [[ -f "${Z_MODULES_DIR}/${module}/module.json" ]]
}

# Get machine info from machines.json
_z_get_machine() {
    local name="$1"
    if [[ ! -f "${Z_MACHINES_FILE}" ]]; then
        return 1
    fi
    # Simple JSON parsing with grep/sed
    grep -A5 "\"name\": \"${name}\"" "${Z_MACHINES_FILE}" 2>/dev/null
}

# Get this machine's name
_z_this_machine() {
    if [[ -f "${Z_MACHINES_FILE}" ]]; then
        grep '"this_machine"' "${Z_MACHINES_FILE}" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/'
    fi
}

# Run a z command on a remote machine via SSH
_z_remote_exec() {
    local machine="$1"
    shift
    local cmd="$@"

    if [[ ! -f "${Z_MACHINES_FILE}" ]]; then
        echo "Error: No machines configured. Run 'z sys init' first." >&2
        return 1
    fi

    # Get machine info
    local host=$(grep -A3 "\"name\": \"${machine}\"" "${Z_MACHINES_FILE}" | grep '"host"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    local user=$(grep -A4 "\"name\": \"${machine}\"" "${Z_MACHINES_FILE}" | grep '"user"' | sed 's/.*: *"\([^"]*\)".*/\1/')

    if [[ -z "${host}" ]]; then
        echo "Error: Machine '${machine}' not found" >&2
        return 1
    fi

    # Build SSH command
    local ssh_target="${host}"
    [[ -n "${user}" ]] && ssh_target="${user}@${host}"

    # Execute remote command
    ssh -o ConnectTimeout=5 -o BatchMode=yes "${ssh_target}" "z ${cmd}" 2>/dev/null
}

# Initialize z
_z_init() {
    echo "Initializing z..."
    echo ""

    # Create main directory
    if [[ ! -d "${Z_DIR}" ]]; then
        mkdir -p "${Z_DIR}"
        echo "Created ${Z_DIR}"
    else
        echo "${Z_DIR} already exists"
    fi

    # Create module directories
    for module in env path alias; do
        if [[ ! -d "${Z_DIR}/${module}" ]]; then
            mkdir -p "${Z_DIR}/${module}"
            echo "Created ${Z_DIR}/${module}"
        fi
    done

    # Create app directories
    if [[ ! -d "${Z_DIR}/app/bin" ]]; then
        mkdir -p "${Z_DIR}/app/bin" "${Z_DIR}/app/metadata"
        echo "Created ${Z_DIR}/app"
    fi

    # Create modules directory (for downloaded modules)
    if [[ ! -d "${Z_MODULES_DIR}" ]]; then
        mkdir -p "${Z_MODULES_DIR}"
        echo "Created ${Z_MODULES_DIR}"
    fi

    # Create sys directory
    if [[ ! -d "${Z_SYS_DIR}" ]]; then
        mkdir -p "${Z_SYS_DIR}"
        echo "Created ${Z_SYS_DIR}"
    fi

    # Create config with all modules enabled by default
    if [[ ! -f "${Z_CONFIG}" ]]; then
        cat > "${Z_CONFIG}" <<'EOF'
# Z configuration
# Enabled modules
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(env path alias app bench sys modules)
EOF
        echo "Created ${Z_CONFIG}"
        echo "All modules enabled by default"
    else
        echo "${Z_CONFIG} already exists"
    fi

    # Create empty data files
    [[ ! -f "${Z_DIR}/env/vars.zsh" ]] && echo "# Managed by z env" > "${Z_DIR}/env/vars.zsh"
    [[ ! -f "${Z_DIR}/path/paths.zsh" ]] && echo "# Managed by z path" > "${Z_DIR}/path/paths.zsh"
    [[ ! -f "${Z_DIR}/alias/aliases.zsh" ]] && echo "# Managed by z alias" > "${Z_DIR}/alias/aliases.zsh"

    echo ""
    echo "Z initialization complete!"
    echo "Run 'z modules' to see available modules"
    echo "Run 'z sys init' to set up multi-machine support"
}

# List modules (called by z modules list or just z modules)
_z_modules_list() {
    echo "Z Modules:"
    echo ""
    printf "  %-12s %-38s %-10s %s\n" "MODULE" "DESCRIPTION" "TYPE" "STATUS"
    printf "  %-12s %-38s %-10s %s\n" "------" "-----------" "----" "------"

    local -A descriptions
    descriptions=(
        [env]="Environment variable manager"
        [path]="PATH entry manager"
        [alias]="Shell alias manager"
        [app]="Binary installation manager"
        [bench]="Shell performance benchmarking"
        [sys]="Multi-machine management"
        [modules]="Module registry"
    )

    local mod_status mod_type
    for module in ${Z_BUILTIN_MODULES[@]}; do
        if _z_module_enabled "${module}"; then
            mod_status="enabled"
        else
            mod_status="disabled"
        fi
        printf "  %-12s %-38s %-10s %s\n" "${module}" "${descriptions[$module]}" "built-in" "${mod_status}"
    done

    # Show installed modules
    local installed=($(_z_get_installed_modules))
    if [[ ${#installed[@]} -gt 0 ]]; then
        for module in ${installed[@]}; do
            local desc=""
            local module_json="${Z_MODULES_DIR}/${module}/module.json"
            if [[ -f "${module_json}" ]]; then
                desc=$(grep '"description"' "${module_json}" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
            fi
            [[ -z "${desc}" ]] && desc="(no description)"
            if [[ ${#desc} -gt 38 ]]; then
                desc="${desc:0:35}..."
            fi
            if _z_module_enabled "${module}"; then
                mod_status="enabled"
            else
                mod_status="disabled"
            fi
            printf "  %-12s %-38s %-10s %s\n" "${module}" "${desc}" "installed" "${mod_status}"
        done
    fi
}

# Enable a module
_z_enable() {
    local module="$1"

    if [[ -z "${module}" ]]; then
        echo "Usage: z enable <module>"
        echo "Run 'z modules' to see available modules"
        return 1
    fi

    # Check if valid module
    if [[ ! " ${Z_AVAILABLE_MODULES[*]} " == *" ${module} "* ]]; then
        echo "Error: Unknown module '${module}'"
        echo "Available: ${Z_AVAILABLE_MODULES[*]}"
        return 1
    fi

    # Check if already enabled
    if _z_module_enabled "${module}"; then
        echo "Module '${module}' is already enabled"
        return 0
    fi

    # Read current config
    source "${Z_CONFIG}"

    # Add module
    Z_ENABLED_MODULES+=("${module}")

    # Write updated config
    cat > "${Z_CONFIG}" <<EOF
# Z configuration
# Enabled modules
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(${Z_ENABLED_MODULES[*]})
EOF

    echo "Enabled module: ${module}"
}

# Disable a module
_z_disable() {
    local module="$1"

    if [[ -z "${module}" ]]; then
        echo "Usage: z disable <module>"
        echo "Run 'z modules' to see available modules"
        return 1
    fi

    # Check if valid module
    if [[ ! " ${Z_AVAILABLE_MODULES[*]} " == *" ${module} "* ]]; then
        echo "Error: Unknown module '${module}'"
        echo "Available: ${Z_AVAILABLE_MODULES[*]}"
        return 1
    fi

    # Check if enabled
    if ! _z_module_enabled "${module}"; then
        echo "Module '${module}' is already disabled"
        return 0
    fi

    # Read current config
    source "${Z_CONFIG}"

    # Remove module
    Z_ENABLED_MODULES=("${(@)Z_ENABLED_MODULES:#${module}}")

    # Write updated config
    cat > "${Z_CONFIG}" <<EOF
# Z configuration
# Enabled modules
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(${Z_ENABLED_MODULES[*]})
EOF

    echo "Disabled module: ${module}"
    echo "Note: Module data is preserved in ${Z_DIR}/${module}/"
}

# Show overview
_z_overview() {
    cat <<'EOF'
z - Unified shell tools

Modules:
  env       Environment variables    z env add KEY VALUE [-s] [-d "desc"]
  path      PATH entries             z path add NAME PATH [-d "desc"]
  alias     Shell aliases            z alias add NAME CMD [-d "desc"]
  app       Binary manager           z app add ./binary
  bench     Performance benchmarks   z bench avg | z bench profile
  sys       Multi-machine            z sys list | z env list -m <machine>
  modules   Module registry          z modules search | z modules add <name>

Commands:
  z init              Initialize z
  z modules           List modules and status
  z modules search    Search module registry
  z modules add       Install a module
  z enable <mod>      Enable a module
  z disable <mod>     Disable a module
  z help [module]     Show help

Run 'z <module>' for module-specific help.
EOF
}

# Show help
_z_help() {
    local module="$1"

    if [[ -z "${module}" ]]; then
        _z_overview
        return
    fi

    # Show module-specific help
    case "${module}" in
        env)
            _z_env help
            ;;
        path)
            _z_path help
            ;;
        alias)
            _z_alias help
            ;;
        app)
            _z_app help
            ;;
        bench)
            _z_bench help
            ;;
        sys)
            _z_sys help
            ;;
        modules)
            _z_modules help
            ;;
        *)
            # Check if it's an installed module
            if _z_module_installed "${module}"; then
                local func_name="_z_${module}"
                if type "${func_name}" &>/dev/null; then
                    "${func_name}" help
                else
                    echo "Module '${module}' does not have a help function"
                fi
            else
                echo "Unknown module: ${module}"
                echo "Available: ${Z_AVAILABLE_MODULES[*]}"
                return 1
            fi
            ;;
    esac
}

# Update z plugin and modules
_z_update() {
    echo "Updating z..."
    echo ""

    # Update core plugin via git
    echo "Core plugin:"
    if [[ -d "${Z_PLUGIN_DIR}/.git" ]]; then
        local result
        result=$(cd "${Z_PLUGIN_DIR}" && git pull 2>&1)
        if [[ $? -eq 0 ]]; then
            echo "  ${result}"
        else
            echo "  Failed: ${result}" >&2
        fi
    else
        echo "  Skipped (not a git repository)"
    fi

    # Update installed modules
    local installed=($(_z_get_installed_modules))
    if [[ ${#installed[@]} -gt 0 ]]; then
        echo ""
        echo "Installed modules:"
        _z_modules update
    fi

    echo ""
    echo "Done. Restart your shell to apply changes."
}
