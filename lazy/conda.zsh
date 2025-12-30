#!/usr/bin/env zsh
# Lazy load conda - only initialize when needed

# Get conda base path dynamically
_get_conda_base() {
    if command -v brew &> /dev/null; then
        local miniconda_prefix="$(brew --prefix miniconda 2>/dev/null)"
        if [[ -n "${miniconda_prefix}" && -d "${miniconda_prefix}/base" ]]; then
            echo "${miniconda_prefix}/base"
            return
        fi
    fi
    # Fallback to common locations
    for path in "$HOME/miniconda3" "$HOME/anaconda3" "/opt/conda"; do
        [[ -d "${path}" ]] && echo "${path}" && return
    done
}

# Create conda command placeholder
conda() {
    # Remove this function definition
    unfunction conda

    # Get conda base path
    local conda_base="$(_get_conda_base)"
    if [[ -z "${conda_base}" ]]; then
        echo "Error: conda installation not found" >&2
        return 1
    fi

    # Initialize conda
    __conda_setup="$("${conda_base}/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "${conda_base}/etc/profile.d/conda.sh" ]; then
            . "${conda_base}/etc/profile.d/conda.sh"
        else
            export PATH="${conda_base}/bin:$PATH"
        fi
    fi
    unset __conda_setup

    # Execute the conda command that was called
    conda "$@"
}

# Also create placeholders for common conda commands
activate() {
    conda activate "$@"
}

deactivate() {
    conda deactivate "$@"
}