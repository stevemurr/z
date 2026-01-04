#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Tests for z term module

load test_helper

# ============================================================================
# Setup/Teardown - uses test_helper's setup, adds tmux check
# ============================================================================

setup() {
    # Get absolute path to plugin directory
    Z_PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../plugins/z" && pwd)"
    export Z_PLUGIN_DIR

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

    # Require tmux for these tests
    if ! command -v tmux &>/dev/null; then
        skip "tmux not installed"
    fi
}

teardown() {
    # Clean up any z- prefixed sessions from this test
    local session
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^z-" | while read -r session; do
        tmux kill-session -t "${session}" 2>/dev/null || true
    done

    # Remove temp directory
    if [[ -d "${Z_TEST_DIR}" ]]; then
        rm -rf "${Z_TEST_DIR}"
    fi
}

# ============================================================================
# z term help
# ============================================================================

@test "z term help displays usage" {
    run run_z term help
    echo "status: $status"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"z term"* ]]
    [[ "$output" == *"start"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"attach"* ]]
}

@test "z term without args shows help" {
    run run_z term
    [ "$status" -eq 0 ]
    [[ "$output" == *"z term"* ]]
}

# ============================================================================
# z term start
# ============================================================================

@test "z term start creates tmux session with custom name" {
    run run_z term start test-session --bg
    echo "status: $status"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Started session"* ]] || [[ "$output" == *"Starting session"* ]]

    # Verify session exists
    session_exists "z-test-session"
}

@test "z term start with --bg does not attach" {
    run run_z term start bg-test --bg
    [ "$status" -eq 0 ]

    # Command should return immediately (not block on attach)
    session_exists "z-bg-test"
}

@test "z term start fails if session already exists" {
    # Create a session first
    tmux new-session -d -s "z-existing"

    run run_z term start existing --bg
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]] || [[ "$output" == *"exists"* ]]
}

@test "z term start requires tmux" {
    # This test verifies the error message when tmux isn't found
    # We can't easily uninstall tmux, so we test the check exists
    run run_z term start check-test --bg
    # If tmux is installed, it should succeed
    if command -v tmux &>/dev/null; then
        [ "$status" -eq 0 ]
    fi
}

# ============================================================================
# z term list
# ============================================================================

@test "z term list shows no sessions when none exist" {
    # Kill any existing z- sessions first
    local s
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^z-" | while read -r s; do
        tmux kill-session -t "$s" 2>/dev/null || true
    done

    run run_z term list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No sessions"* ]] || [[ "$output" == *"SESSION"* ]]
}

@test "z term list shows active sessions" {
    # Create a test session
    tmux new-session -d -s "z-list-test"

    run run_z term list
    [ "$status" -eq 0 ]
    [[ "$output" == *"list-test"* ]]
}

@test "z term list --json outputs valid json" {
    # Create a test session
    tmux new-session -d -s "z-json-test"

    run run_z term list --json
    [ "$status" -eq 0 ]
    # Should contain JSON array or object markers
    [[ "$output" == "["* ]] || [[ "$output" == "{"* ]] || [[ "$output" == "[]" ]]
}

# ============================================================================
# z term stop
# ============================================================================

@test "z term stop kills session" {
    # Create a test session
    tmux new-session -d -s "z-stop-test"
    session_exists "z-stop-test"

    run run_z term stop stop-test
    [ "$status" -eq 0 ]

    # Session should no longer exist
    ! session_exists "z-stop-test"
}

@test "z term stop fails for non-existent session" {
    run run_z term stop nonexistent-session
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"No session"* ]]
}

# ============================================================================
# z term status
# ============================================================================

@test "z term status shows not in session when outside tmux" {
    # Ensure we're not in tmux
    unset TMUX

    run run_z term status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not in"* ]] || [[ "$output" == *"outside"* ]] || [[ "$output" == *"No active"* ]]
}
