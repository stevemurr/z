#!/usr/bin/env zsh
# Z core library - shared utilities

# Data directory (allow override for testing)
Z_DIR="${Z_DIR:-${HOME}/.z}"
Z_CONFIG="${Z_CONFIG:-${Z_DIR}/config.zsh}"
Z_MODULES_DIR="${Z_MODULES_DIR:-${Z_DIR}/modules}"
Z_SYS_DIR="${Z_SYS_DIR:-${Z_DIR}/sys}"
Z_MACHINES_FILE="${Z_MACHINES_FILE:-${Z_SYS_DIR}/machines.json}"

# Module registry URL
Z_REGISTRY_URL="${Z_REGISTRY_URL:-https://raw.githubusercontent.com/stevemurr/z/main/registry}"
Z_REGISTRY_CACHE="${Z_REGISTRY_CACHE:-${Z_DIR}/registry-cache.json}"

# Built-in modules (shipped with z)
typeset -ga Z_BUILTIN_MODULES
Z_BUILTIN_MODULES=(env path alias app bench sys modules term)

# Available modules (built-in + installed)
typeset -ga Z_AVAILABLE_MODULES
Z_AVAILABLE_MODULES=(env path alias app bench sys modules term)

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
    # Check if directory exists and has subdirectories
    [[ ! -d "${Z_MODULES_DIR}" ]] && return
    [[ -z "$(ls -A "${Z_MODULES_DIR}" 2>/dev/null)" ]] && return

    for module_dir in "${Z_MODULES_DIR}"/*/; do
        [[ ! -d "${module_dir}" ]] && continue

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
    done
}

# Get list of installed modules
_z_get_installed_modules() {
    local modules=()
    if [[ -d "${Z_MODULES_DIR}" ]] && [[ -n "$(ls -A "${Z_MODULES_DIR}" 2>/dev/null)" ]]; then
        for module_dir in "${Z_MODULES_DIR}"/*/; do
            [[ -d "${module_dir}" ]] && modules+=($(basename "${module_dir}"))
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
        [term]="Remote terminal sessions"
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
  term      Remote terminals         z term start | z term attach <name>

Commands:
  z init              Initialize z
  z modules           List modules and status
  z modules search    Search module registry
  z modules add       Install a module
  z enable <mod>      Enable a module
  z disable <mod>     Disable a module
  z test [module]     Run tests
  z help [module]     Show help

Run 'z <module>' for module-specific help.
EOF
}

# Run tests
_z_test() {
    local module="$1"
    local verbose=false
    local test_dir="${Z_PLUGIN_DIR}/../../tests"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                module="$1"
                shift
                ;;
        esac
    done

    # Check if bats is installed
    if ! command -v bats &>/dev/null; then
        echo "Error: bats-core is not installed"
        echo ""
        echo "Install bats-core:"
        echo "  macOS:  brew install bats-core"
        echo "  Ubuntu: sudo apt install bats"
        echo "  Manual: git clone https://github.com/bats-core/bats-core && cd bats-core && sudo ./install.sh /usr/local"
        return 1
    fi

    # Check if tests directory exists
    if [[ ! -d "${test_dir}" ]]; then
        echo "Error: Tests directory not found at ${test_dir}"
        return 1
    fi

    local bats_args=()
    [[ "${verbose}" == true ]] && bats_args+=("--verbose-run")

    if [[ -n "${module}" ]]; then
        # Run specific module tests
        local test_file="${test_dir}/${module}.bats"
        if [[ ! -f "${test_file}" ]]; then
            echo "Error: No tests found for module '${module}'"
            echo "Expected: ${test_file}"
            return 1
        fi
        echo "Running tests for module: ${module}"
        bats "${bats_args[@]}" "${test_file}"
    else
        # Run all tests
        echo "Running all tests..."
        bats "${bats_args[@]}" "${test_dir}"/*.bats
    fi
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
        term)
            _z_term help
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
