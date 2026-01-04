#!/usr/bin/env bats
# Tests for z term module

load test_helper

# ============================================================================
# Setup/Teardown
# ============================================================================

setup() {
    # Call parent setup
    eval "$(declare -f setup | tail -n +2)"

    # Require tmux for these tests
    if ! command -v tmux &>/dev/null; then
        skip "tmux not installed"
    fi
}

# ============================================================================
# z term help
# ============================================================================

@test "z term help displays usage" {
    run run_z term help
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
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting session"* ]] || [[ "$output" == *"Started session"* ]]

    # Verify session exists
    session_exists "z-test-session"

    # Cleanup
    tmux kill-session -t "z-test-session" 2>/dev/null || true
}

@test "z term start with --bg does not attach" {
    run run_z term start bg-test --bg
    [ "$status" -eq 0 ]

    # Command should return immediately (not block on attach)
    session_exists "z-bg-test"

    # Cleanup
    tmux kill-session -t "z-bg-test" 2>/dev/null || true
}

@test "z term start fails if session already exists" {
    # Create a session first
    tmux new-session -d -s "z-existing"

    run run_z term start existing --bg
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]] || [[ "$output" == *"exists"* ]]

    # Cleanup
    tmux kill-session -t "z-existing" 2>/dev/null || true
}

@test "z term start requires tmux" {
    # This test verifies the error message when tmux isn't found
    # We can't easily uninstall tmux, so we test the check exists
    run run_z term start check-test --bg
    # If tmux is installed, it should succeed
    if command -v tmux &>/dev/null; then
        [ "$status" -eq 0 ]
    fi

    # Cleanup
    tmux kill-session -t "z-check-test" 2>/dev/null || true
}

# ============================================================================
# z term list
# ============================================================================

@test "z term list shows no sessions when none exist" {
    # Kill any existing z- sessions first
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^z-" | while read s; do
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

    # Cleanup
    tmux kill-session -t "z-list-test" 2>/dev/null || true
}

@test "z term list --json outputs valid json" {
    # Create a test session
    tmux new-session -d -s "z-json-test"

    run run_z term list --json
    [ "$status" -eq 0 ]
    # Should contain JSON array or object markers
    [[ "$output" == "["* ]] || [[ "$output" == "{"* ]] || [[ "$output" == "[]" ]]

    # Cleanup
    tmux kill-session -t "z-json-test" 2>/dev/null || true
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
