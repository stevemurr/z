#!/usr/bin/env bash
# shellcheck disable=SC2034
# Test helper for z bats tests

# Load bats helpers if available
if [[ -d "${BATS_TEST_DIRNAME}/test_helper/bats-support" ]]; then
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
fi

# Get the z plugin directory
export Z_PLUGIN_DIR="${BATS_TEST_DIRNAME}/../plugins/z"

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

    # Create minimal config
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
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^z-test-" | while read -r session; do
        tmux kill-session -t "${session}" 2>/dev/null || true
    done

    # Remove temp directory
    [[ -d "${Z_TEST_DIR}" ]] && rm -rf "${Z_TEST_DIR}"
}

# Helper: run a z command
run_z() {
    local cmd="$*"
    zsh -c "
        export Z_DIR='${Z_DIR}'
        export Z_CONFIG='${Z_CONFIG}'
        export Z_TERM_DIR='${Z_TERM_DIR}'
        source '${Z_PLUGIN_DIR}/z.plugin.zsh'
        z ${cmd}
    "
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
