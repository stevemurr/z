#!/usr/bin/env zsh
# Process and network management functions

# Process manager with preview
fproc() {
    ps aux | fzf \
        --header-lines=1 \
        --preview 'echo "Process Details:" && ps -p {2} -o pid,ppid,user,start,time,command && echo -e "\nOpen Files:" && lsof -p {2} 2>/dev/null | head -20' \
        --preview-window=right:60% \
        --bind 'enter:execute(kill -9 {2})' \
        --bind 'ctrl-s:execute(kill -STOP {2})' \
        --bind 'ctrl-c:execute(kill -CONT {2})'
}

# Network connections viewer (Mac version)
fnet() {
    netstat -an | fzf \
        --header-lines=2 \
        --preview 'lsof -i :{} 2>/dev/null || echo "No process info available"' \
        --preview-window=down:30%
}

# Even better - use lsof directly for network connections
fnetlsof() {
    lsof -i | fzf \
        --header-lines=1 \
        --preview 'ps -p {2} -o pid,ppid,user,start,time,command 2>/dev/null' \
        --preview-window=right:50% \
        --bind 'enter:execute(kill -9 {2})' \
        --bind 'ctrl-s:execute(kill -STOP {2})'
}

# Port-specific lookup
fport() {
    lsof -i :${1:-80} | fzf \
        --header-lines=1 \
        --preview 'netstat -an | grep :{}'
}

# More detailed network info
fnetwork() {
    {
        echo "=== Active Connections ==="
        netstat -an | grep ESTABLISHED
        echo ""
        echo "=== Listening Ports ==="
        netstat -an | grep LISTEN
        echo ""
        echo "=== All Network Processes ==="
        lsof -i
    } | fzf \
        --preview 'if echo {} | grep -q ":"; then port=$(echo {} | awk "{print \$4}" | cut -d: -f2); lsof -i :$port; else echo "Network connection: {}"; fi' \
        --preview-window=right:60%
}

# See what's hogging your ports
fwho() {
    echo "Enter port number:" 
    read port
    lsof -i :$port | fzf \
        --header-lines=1 \
        --preview 'ps -ef | grep {2}' \
        --bind 'enter:execute(kill {2})'
}

# Network interface stats
finterface() {
    netstat -i | fzf \
        --header-lines=1 \
        --preview 'ifconfig {1}'
}