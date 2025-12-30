#!/usr/bin/env zsh
# Utility functions for notes, media, etc.

# Note manager with instant search
fnotes() {
    local notes_dir="$HOME/notes"
    find "$notes_dir" -name "*.md" | fzf \
        --preview 'bat --color=always --style=numbers {}' \
        --preview-window=right:60% \
        --header 'Enter: Edit | Ctrl-N: New note | Ctrl-D: Delete' \
        --bind "enter:execute(nvim {})" \
        --bind "ctrl-n:execute(nvim $notes_dir/$(date +%Y%m%d_%H%M%S).md)" \
        --bind 'ctrl-d:execute(rm -i {})'
}

# Search inside all notes
fgrep_notes() {
    rg --color=always --line-number --no-heading . ~/notes/ | fzf \
        --ansi \
        --delimiter : \
        --preview 'bat --color=always {1} --highlight-line {2}' \
        --preview-window=right:60% \
        --bind 'enter:execute(nvim {1} +{2})'
}

# Music library browser
fmusic() {
    find ~/Music -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | fzf \
        --preview 'mediainfo {} 2>/dev/null | head -20' \
        --preview-window=right:40% \
        --bind 'enter:execute(mpv {})' \
        --bind 'space:execute(mpv {} &)'
}

# Video browser
fvideo() {
    find . -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" \) | fzf \
        --preview 'ffprobe -v quiet -print_format json -show_format {} | jq -r ".format | \"Duration: \(.duration)s\nSize: \(.size) bytes\nBitrate: \(.bit_rate)\""' \
        --bind 'enter:execute(mpv {})'
}