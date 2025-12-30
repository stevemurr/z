#!/usr/bin/env zsh
# Docker management functions

# Docker container manager
fdocker() {
    docker ps -a | fzf \
        --header-lines=1 \
        --preview 'docker logs {1} 2>/dev/null | tail -100' \
        --preview-window=down:60% \
        --bind 'enter:execute(docker exec -it {1} /bin/bash)' \
        --bind 'ctrl-s:execute(docker start {1})' \
        --bind 'ctrl-k:execute(docker kill {1})' \
        --bind 'ctrl-r:execute(docker restart {1})'
}

# Docker image browser
fdockerimg() {
    docker images | fzf \
        --header-lines=1 \
        --preview 'docker history {3}' \
        --bind 'enter:execute(docker run -it {3} /bin/bash)'
}