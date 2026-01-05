#!/usr/bin/env zsh
# Z app module - Binary installation manager

# Module dispatcher
_z_app() {
    local cmd="$1"
    shift 2>/dev/null

    case "${cmd}" in
        add|install)
            _z_app_add "$@"
            ;;
        list|ls)
            _z_app_list "$@"
            ;;
        rm|uninstall)
            _z_app_rm "$@"
            ;;
        help|--help|-h|"")
            _z_app_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z app help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_app_help() {
    cat <<'EOF'
z app - Binary installation manager

Usage: z app <command> [args]

Commands:
  add PATH          Install a binary from path
  list, ls          List installed binaries
  rm NAME           Remove a binary
  help              Show this help

Examples:
  z app add ./mybinary
  z app add ~/Downloads/sometool
  z app list
  z app rm mybinary
EOF
}

# Install a binary
_z_app_add() {
    local binary_path="$1"
    local bin_dir="${Z_DIR}/app/bin"
    local metadata_dir="${Z_DIR}/app/metadata"

    # Validate input
    if [[ -z "${binary_path}" ]]; then
        echo "Error: No binary path provided"
        echo "Usage: z app add <path-to-binary>"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -d "${bin_dir}" ]] || [[ ! -d "${metadata_dir}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Resolve to absolute path
    binary_path=$(realpath "${binary_path}" 2>/dev/null || readlink -f "${binary_path}" 2>/dev/null || echo "${binary_path}")

    # Check if binary exists
    if [[ ! -f "${binary_path}" ]]; then
        echo "Error: Binary not found: ${binary_path}"
        return 1
    fi

    # Check if binary is executable
    if [[ ! -x "${binary_path}" ]]; then
        echo "Error: File is not executable: ${binary_path}"
        echo "Try: chmod +x ${binary_path}"
        return 1
    fi

    # Extract binary name
    local binary_name=$(basename "${binary_path}")
    local dest_path="${bin_dir}/${binary_name}"
    local metadata_file="${metadata_dir}/${binary_name}.json"

    # Copy binary
    cp "${binary_path}" "${dest_path}"
    chmod +x "${dest_path}"

    # Get binary info
    local file_size=$(stat -f%z "${binary_path}" 2>/dev/null || stat -c%s "${binary_path}" 2>/dev/null)
    local install_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create metadata JSON
    cat > "${metadata_file}" <<EOF
{
  "name": "${binary_name}",
  "source_path": "${binary_path}",
  "install_date": "${install_date}",
  "size_bytes": ${file_size}
}
EOF

    echo "Installed ${binary_name}"
    echo "  Source: ${binary_path}"
    echo "  Size: $(numfmt --to=iec-i --suffix=B ${file_size} 2>/dev/null || echo "${file_size} bytes")"
    echo "  Location: ${dest_path}"
}

# List installed binaries
_z_app_list() {
    local bin_dir="${Z_DIR}/app/bin"
    local metadata_dir="${Z_DIR}/app/metadata"

    # Check if z is initialized
    if [[ ! -d "${metadata_dir}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    # Count binaries
    local count=$(ls -1 "${metadata_dir}"/*.json 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${count}" -eq 0 ]]; then
        echo "No binaries installed."
        echo "Install one with: z app add <path-to-binary>"
        return 0
    fi

    echo "Installed binaries (${count}):"
    echo ""
    printf "%-20s %-50s %-20s %s\n" "NAME" "SOURCE" "INSTALLED" "SIZE"
    printf "%-20s %-50s %-20s %s\n" "----" "------" "---------" "----"

    # Read and display each metadata file
    for metadata_file in "${metadata_dir}"/*.json; do
        if [[ -f "${metadata_file}" ]]; then
            # Parse JSON manually (simple approach without jq dependency)
            local name=$(grep '"name"' "${metadata_file}" | sed 's/.*: "\(.*\)".*/\1/')
            local source=$(grep '"source_path"' "${metadata_file}" | sed 's/.*: "\(.*\)".*/\1/')
            local date=$(grep '"install_date"' "${metadata_file}" | sed 's/.*: "\(.*\)".*/\1/')
            local size=$(grep '"size_bytes"' "${metadata_file}" | sed 's/.*: \(.*\)/\1/')

            # Format date to be more readable (just date part)
            local date_short=$(echo "${date}" | cut -d'T' -f1)

            # Format size
            local size_formatted=$(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size}B")

            # Truncate source path if too long
            if [[ ${#source} -gt 50 ]]; then
                source="...${source: -47}"
            fi

            printf "%-20s %-50s %-20s %s\n" "${name}" "${source}" "${date_short}" "${size_formatted}"
        fi
    done
}

# Remove a binary
_z_app_rm() {
    local binary_name="$1"
    local bin_dir="${Z_DIR}/app/bin"
    local metadata_dir="${Z_DIR}/app/metadata"

    # Validate input
    if [[ -z "${binary_name}" ]]; then
        echo "Error: No binary name provided"
        echo "Usage: z app rm <binary-name>"
        return 1
    fi

    # Check if z is initialized
    if [[ ! -d "${bin_dir}" ]] || [[ ! -d "${metadata_dir}" ]]; then
        echo "Error: Z not initialized. Run 'z init' first."
        return 1
    fi

    local binary_path="${bin_dir}/${binary_name}"
    local metadata_file="${metadata_dir}/${binary_name}.json"

    # Check if binary exists
    if [[ ! -f "${binary_path}" ]] && [[ ! -f "${metadata_file}" ]]; then
        echo "Error: Binary '${binary_name}' not found"
        echo "Run 'z app list' to see installed binaries"
        return 1
    fi

    # Remove binary and metadata
    [[ -f "${binary_path}" ]] && rm "${binary_path}"
    [[ -f "${metadata_file}" ]] && rm "${metadata_file}"

    echo "Removed ${binary_name}"
}
