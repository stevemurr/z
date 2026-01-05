#!/usr/bin/env zsh
# Z bench module - Shell performance benchmarking

# Module dispatcher
_z_bench() {
    local cmd="${1:-quick}"
    shift 2>/dev/null

    case "${cmd}" in
        quick|q)
            _z_bench_quick "$@"
            ;;
        avg|average)
            _z_bench_avg "$@"
            ;;
        profile|prof|p)
            _z_bench_profile "$@"
            ;;
        help|--help|-h)
            _z_bench_help
            ;;
        *)
            echo "Error: Unknown command '${cmd}'"
            echo "Run 'z bench help' for usage"
            return 1
            ;;
    esac
}

# Show help
_z_bench_help() {
    cat <<'EOF'
z bench - Shell performance benchmarking

Usage: z bench [command]

Commands:
  quick, q          Single startup time measurement (default)
  avg [N]           Average of N runs (default: 10)
  profile, p [N]    Show slowest components (default: 20 lines)
  help              Show this help

Examples:
  z bench            Quick single measurement
  z bench avg        Average of 10 runs
  z bench avg 20     Average of 20 runs
  z bench profile    Show top 20 slowest
  z bench profile 50 Show top 50 slowest
EOF
}

# Quick single measurement
_z_bench_quick() {
    local start_time end_time duration_ms

    # Use zsh's built-in high-res timer
    start_time=$(($(gdate +%s%N 2>/dev/null || date +%s000000000) / 1000000))
    zsh -i -c exit 2>/dev/null
    end_time=$(($(gdate +%s%N 2>/dev/null || date +%s000000000) / 1000000))

    duration_ms=$((end_time - start_time))

    echo "Shell startup: ${duration_ms}ms"
}

# Average of multiple runs
_z_bench_avg() {
    local runs="${1:-10}"
    local total=0
    local min=999999
    local max=0
    local i duration_ms start_time end_time

    echo "Running ${runs} iterations..."

    for ((i = 1; i <= runs; i++)); do
        start_time=$(($(gdate +%s%N 2>/dev/null || date +%s000000000) / 1000000))
        zsh -i -c exit 2>/dev/null
        end_time=$(($(gdate +%s%N 2>/dev/null || date +%s000000000) / 1000000))

        duration_ms=$((end_time - start_time))
        total=$((total + duration_ms))

        if ((duration_ms < min)); then
            min=$duration_ms
        fi
        if ((duration_ms > max)); then
            max=$duration_ms
        fi

        # Progress indicator
        printf "\r  %d/%d" "$i" "$runs"
    done

    local avg=$((total / runs))

    printf "\r"
    echo "Shell startup (${runs} runs):"
    echo "  avg: ${avg}ms"
    echo "  min: ${min}ms"
    echo "  max: ${max}ms"
}

# Profile with zprof
_z_bench_profile() {
    local lines="${1:-20}"
    local tmp_dir=$(mktemp -d)
    local real_zshrc="${ZDOTDIR:-$HOME}/.zshrc"

    # Create a temporary .zshrc that loads zprof BEFORE sourcing config
    cat > "${tmp_dir}/.zshrc" <<EOF
zmodload zsh/zprof
source "${real_zshrc}"
zprof | head -${lines}
EOF

    echo "Profiling shell startup..."
    echo ""

    # Run zsh with our profiling wrapper
    ZDOTDIR="${tmp_dir}" zsh -i -c exit 2>/dev/null

    # Cleanup
    rm -rf "${tmp_dir}"

    echo ""
    echo "---"
    echo "Top items are slowest. Look for opportunities to lazy-load."
}
