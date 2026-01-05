#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
# Test helper for z bats tests

# Load bats helpers if available
if [[ -d "${BATS_TEST_DIRNAME}/test_helper/bats-support" ]]; then
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
fi

# Get the z plugin directory (absolute path)
export Z_PLUGIN_DIR
Z_PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../plugins/z" && pwd)"

# Create a temporary z directory for each test
setup() {
    # Create temp directory for test isolation
    local tmpdir
    tmpdir=$(mktemp -d)
    export Z_TEST_DIR="${tmpdir}"
    export Z_DIR="${Z_TEST_DIR}/.z"
    export Z_CONFIG="${Z_DIR}/config.zsh"
    export Z_TERM_DIR="${Z_DIR}/term"

    mkdir -p "${Z_DIR}" "${Z_TERM_DIR}"

    # Create minimal config with term enabled
    cat > "${Z_CONFIG}" <<'EOF'
typeset -ga Z_ENABLED_MODULES
Z_ENABLED_MODULES=(env path alias app bench sys modules term)
EOF

    # Track tmux sessions we create for cleanup
    export Z_TEST_SESSIONS=()
}

# Cleanup after each test
teardown() {
    # Kill any test tmux sessions
    local session
    for session in "${Z_TEST_SESSIONS[@]}"; do
        tmux kill-session -t "${session}" 2>/dev/null || true
    done

    # Clean up any z- prefixed sessions from this test
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^z-" | while read -r session; do
        tmux kill-session -t "${session}" 2>/dev/null || true
    done

    # Remove temp directory
    if [[ -d "${Z_TEST_DIR}" ]]; then
        rm -rf "${Z_TEST_DIR}"
    fi
}

# Helper: run a z command
# This runs z in a zsh subprocess with the test environment
run_z() {
    local z_plugin_dir="${Z_PLUGIN_DIR}"
    local z_dir="${Z_DIR}"
    local z_config="${Z_CONFIG}"
    local z_term_dir="${Z_TERM_DIR}"

    zsh -c "
        export Z_DIR='${z_dir}'
        export Z_CONFIG='${z_config}'
        export Z_TERM_DIR='${z_term_dir}'
        export Z_PLUGIN_DIR='${z_plugin_dir}'
        source '${z_plugin_dir}/z.plugin.zsh'
        z $*
    " 2>&1
}

# Helper: create a test tmux session
create_test_session() {
    local name="${1:-test-$$}"
    local full_name="z-test-${name}"
    tmux new-session -d -s "${full_name}" 2>/dev/null
    Z_TEST_SESSIONS+=("${full_name}")
    echo "${full_name}"
}

# Helper: check if tmux session exists
session_exists() {
    local name="$1"
    tmux has-session -t "${name}" 2>/dev/null
}

# Helper: check if tmux is available
require_tmux() {
    if ! command -v tmux &>/dev/null; then
        skip "tmux not installed"
    fi
}
