#!/usr/bin/env zsh
# Z - Unified shell tools plugin
# https://wiki.zshell.dev/community/zsh_plugin_standard

# Get plugin directory
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"
Z_PLUGIN_DIR="${0:h}"

# Source core library
source "${Z_PLUGIN_DIR}/lib/core.zsh"

# Source built-in modules
for module_file in "${Z_PLUGIN_DIR}"/modules/*.zsh; do
    [[ -f "${module_file}" ]] && source "${module_file}"
done

# Load installed (downloaded) modules
_z_load_installed_modules

# Add completions to fpath
fpath=("${Z_PLUGIN_DIR}/completions" $fpath)

# Source user data files (environment, paths, aliases)
_z_source_data

# Main dispatcher
z() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        # Core commands
        init)
            _z_init "$@"
            ;;
        modules|mod)
            if _z_module_enabled modules; then
                _z_modules "$@"
            else
                # Fall back to simple list if modules module is disabled
                _z_modules_list
            fi
            ;;
        enable)
            _z_enable "$@"
            ;;
        disable)
            _z_disable "$@"
            ;;
        help|--help|-h)
            _z_help "$@"
            ;;

        # Module dispatch (only if enabled)
        env)
            if _z_module_enabled env; then
                _z_env "$@"
            else
                echo "Module 'env' is not enabled. Run: z enable env"
                return 1
            fi
            ;;
        path)
            if _z_module_enabled path; then
                _z_path "$@"
            else
                echo "Module 'path' is not enabled. Run: z enable path"
                return 1
            fi
            ;;
        alias)
            if _z_module_enabled alias; then
                _z_alias "$@"
            else
                echo "Module 'alias' is not enabled. Run: z enable alias"
                return 1
            fi
            ;;
        app)
            if _z_module_enabled app; then
                _z_app "$@"
            else
                echo "Module 'app' is not enabled. Run: z enable app"
                return 1
            fi
            ;;
        bench)
            if _z_module_enabled bench; then
                _z_bench "$@"
            else
                echo "Module 'bench' is not enabled. Run: z enable bench"
                return 1
            fi
            ;;
        sys)
            if _z_module_enabled sys; then
                _z_sys "$@"
            else
                echo "Module 'sys' is not enabled. Run: z enable sys"
                return 1
            fi
            ;;

        # Default: show overview
        "")
            _z_overview
            ;;
        *)
            # Check for installed modules
            local func_name="_z_${cmd}"
            if type "${func_name}" &>/dev/null; then
                if _z_module_enabled "${cmd}"; then
                    "${func_name}" "$@"
                else
                    echo "Module '${cmd}' is not enabled. Run: z enable ${cmd}"
                    return 1
                fi
            else
                echo "Error: Unknown command '${cmd}'"
                echo "Run 'z help' for usage"
                return 1
            fi
            ;;
    esac
}
