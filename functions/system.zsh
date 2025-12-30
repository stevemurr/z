#!/usr/bin/env zsh
# System management and cleanup functions

# Homebrew interface (macOS)
fbrew() {
    brew search | fzf \
        --preview 'brew info {}' \
        --preview-window=right:60% \
        --bind 'enter:execute(brew install {})'
}

# GUI Apps only (faster)
fappgui() {
    {
        find /Applications -name "*.app" -maxdepth 3 2>/dev/null
        find /System/Applications -name "*.app" -maxdepth 2 2>/dev/null  
        find ~/Applications -name "*.app" -maxdepth 2 2>/dev/null
    } | sed 's|.*/||; s|\.app$||' | sort | fzf \
        --preview 'app_path=$(find /Applications /System/Applications ~/Applications -name "{}.app" -maxdepth 3 2>/dev/null | head -1)
                   if [ -n "$app_path" ]; then
                       echo "📱 {}"
                       echo "Path: $app_path"
                       echo ""
                       version=$(defaults read "$app_path/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Unknown")
                       echo "Version: $version"
                       
                       bundle_id=$(defaults read "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "Unknown")
                       echo "Bundle ID: $bundle_id"
                       
                       size=$(du -sh "$app_path" 2>/dev/null | cut -f1 || echo "Unknown")
                       echo "Size: $size"
                   fi' \
        --preview-window=right:50% \
        --header 'GUI Apps Only | Enter: Launch | Ctrl-O: Reveal' \
        --bind 'enter:execute(open -a "{}")' \
        --bind 'ctrl-o:execute(app_path=$(find /Applications /System/Applications ~/Applications -name "{}.app" -maxdepth 3 2>/dev/null | head -1); open -R "$app_path")'
}

# Clean up common space wasters
fcleanup() {
    {
        echo "=== DOWNLOADS FOLDER ==="
        du -sh ~/Downloads/* 2>/dev/null | sort -hr | head -10
        echo ""
        echo "=== TRASH/CACHE ==="
        du -sh ~/.Trash/* 2>/dev/null | sort -hr | head -10
        du -sh ~/Library/Caches/* 2>/dev/null | sort -hr | head -10
        echo ""
        echo "=== OLD LOGS ==="
        find ~/Library/Logs -name "*.log" -size +10M 2>/dev/null | xargs du -sh 2>/dev/null | sort -hr
        echo ""
        echo "=== DOCKER (if installed) ==="
        docker system df 2>/dev/null || echo "Docker not installed"
    } | fzf \
        --preview 'path=$(echo {} | awk "{print \$2}"); 
                   if [ -f "$path" ]; then 
                       echo "File: $path" && file "$path"
                   elif [ -d "$path" ]; then 
                       echo "Directory: $path" && ls -la "$path" | head -10
                   fi' \
        --header 'Cleanup candidates | Enter: Examine | Ctrl-D: Delete safely' \
        --bind 'ctrl-d:execute(rm -rf {})'
}

# Ultimate disk space analyzer
fdiskfull() {
    {
        echo "=== LARGEST DIRECTORIES ==="
        du -sh */ 2>/dev/null | sort -hr | head -20
        echo ""
        echo "=== LARGEST FILES ==="
        find . -type f -exec du -sh {} + 2>/dev/null | sort -hr | head -20
        echo ""
        echo "=== HIDDEN DIRECTORIES ==="
        du -sh .* 2>/dev/null | grep -v "^\s*[0-9]*[KMGT]*\s*\.$" | sort -hr | head -10
    } | fzf \
        --preview 'case {} in
            *DIRECTORIES*|*FILES*|*HIDDEN*) echo "Section header" ;;
            *) path=$(echo {} | awk "{print \$2}"); 
               if [ -d "$path" ]; then 
                   echo "=== Directory: $path ===" && ls -la "$path" | head -15
               elif [ -f "$path" ]; then 
                   echo "=== File: $path ===" && file "$path" && if file "$path" | grep -q text; then echo -e "\nContent preview:" && head -10 "$path"; fi
               fi ;;
        esac' \
        --preview-window=right:60% \
        --header 'Space Analysis | Enter: Investigate | Ctrl-D: Delete'
}