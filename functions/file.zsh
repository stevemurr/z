#!/usr/bin/env zsh
# File management functions
# Full-featured file browser with actions
#
fm() {
    local file
    file=$(find . -type f | fzf \
        --preview 'if file {} | grep -q "text\|empty"; then bat --color=always --style=numbers {}; else file {}; fi' \
        --preview-window=right:60% \
        --header 'Enter: Edit | Ctrl-O: Open | Ctrl-D: Delete | Ctrl-Y: Copy path' \
        --bind 'enter:execute(nvim {})' \
        --bind 'ctrl-o:execute(xdg-open {})' \
        --bind 'ctrl-d:execute(rm -i {})' \
        --bind 'ctrl-y:execute(echo {} | xclip -selection clipboard)+abort')
}

fman() {
    while true; do
        local selection
        selection=$(find . -maxdepth 1 -type d -o -type f | sed 's|^\./||' | sort | fzf \
            --preview 'file_path={}
                      if [ -d "$file_path" ]; then 
                          echo "📁 DIRECTORY"
                          echo "============"
                          ls -la "$file_path" | head -20
                      else
                          # Get file info
                          file_output=$(file "$file_path")
                          file_size=$(ls -lh "$file_path" | awk "{print \$5}")
                          
                          # Check if its a text file or common code file
                          if echo "$file_output" | grep -iE "text|ascii|utf-8|json|xml" >/dev/null || \
                             echo "$file_path" | grep -iE "\.(txt|md|py|js|ts|html|css|json|xml|yml|yaml|sh|conf|log|csv|sql|php|rb|go|rs|java|cpp|c|h|swift|kt|dart|r|scala|clj|hs|lua|pl|ps1|bat|cmd|ini|cfg|env|gitignore|dockerfile|makefile|readme)$" >/dev/null; then
                              
                              echo "📝 TEXT FILE ($file_size)"
                              echo "========================"
                              if command -v bat >/dev/null; then
                                  bat --color=always --style=numbers --line-range=:50 "$file_path" 2>/dev/null
                              else
                                  head -50 "$file_path"
                              fi
                          else
                              # Non-text file - just show info, use Quick Look to view
                              echo "📄 FILE ($file_size)"
                              echo "=================="
                              file "$file_path"
                              echo ""
                              
                              # Show file type specific info
                              if echo "$file_output" | grep -iE "image|bitmap|JPEG|PNG|GIF|WebP" >/dev/null; then
                                  echo "🖼️  Image file - Press SPACE for Quick Look preview"
                                  if command -v sips >/dev/null; then
                                      sips -g pixelWidth -g pixelHeight "$file_path" 2>/dev/null | grep -E "pixelWidth|pixelHeight" | awk "{print \$2}" | tr "\n" "x" | sed "s/x$/ pixels/"
                                      echo ""
                                  fi
                                  
                              elif echo "$file_output" | grep -iE "video|mp4|mov|avi|mkv|webm" >/dev/null; then
                                  echo "🎬 Video file - Press SPACE for Quick Look preview"
                                  
                              elif echo "$file_output" | grep -iE "audio|mp3|wav|flac|m4a|aac|ogg" >/dev/null; then
                                  echo "🎵 Audio file - Press SPACE for Quick Look preview"
                                  
                              elif echo "$file_output" | grep -i "pdf" >/dev/null; then
                                  echo "📄 PDF document - Press SPACE for Quick Look preview"
                                  if command -v pdfinfo >/dev/null; then
                                      pdfinfo "$file_path" 2>/dev/null | grep -E "Pages:|Title:|Author:" | head -3
                                  fi
                                  
                              elif echo "$file_output" | grep -iE "zip|tar|gzip|bzip|7-zip|rar" >/dev/null; then
                                  echo "📦 Archive file - Press SPACE for Quick Look preview"
                                  
                              elif echo "$file_output" | grep -iE "executable|binary" >/dev/null; then
                                  echo "⚙️  Executable file"
                                  
                              else
                                  echo "❓ Unknown file type - Press SPACE for Quick Look preview"
                              fi
                              
                              echo ""
                              echo "Last modified: $(stat -f "%Sm" "$file_path")"
                          fi
                      fi' \
            --header 'Enter: Open/CD | Space: Quick Look | Ctrl-O: Finder | Ctrl-H: Home | Ctrl-P: Parent | Ctrl-C: Exit' \
            --bind 'ctrl-h:reload(find ~ -maxdepth 1 -type d -o -type f | sed "s|^$HOME/||" | sort)' \
            --bind 'ctrl-p:reload(find .. -maxdepth 1 -type d -o -type f | sed "s|^\.\./||" | sort)' \
            --bind 'space:execute-silent(qlmanage -p {} >/dev/null 2>&1)' \
            --bind 'ctrl-o:execute(open -R {})' \
            --preview-window=right:60%)
        
        [ -z "$selection" ] && break
        
        if [ -d "$selection" ]; then
            cd "$selection"
        else
            # Smart file opening
            file_output=$(file "$selection")
            
            # Open text files in editor, everything else with default app
            if echo "$file_output" | grep -iE "text|ascii|utf-8|json|xml" >/dev/null || \
               echo "$selection" | grep -iE "\.(txt|md|py|js|ts|html|css|json|xml|yml|yaml|sh|conf|log|csv|sql|php|rb|go|rs|java|cpp|c|h|swift|kt|dart|r|scala|clj|hs|lua|pl|ps1|bat|cmd|ini|cfg|env|gitignore|dockerfile|makefile|readme)$" >/dev/null; then
                nvim "$selection"
            else
                open "$selection"
            fi
        fi
    done
}

