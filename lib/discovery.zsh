#!/usr/bin/env zsh
# Z discovery library - Find z instances on Tailscale network

Z_DISCOVERY_CACHE="${Z_DIR}/beacon/discovered.json"
Z_DISCOVERY_TTL="${Z_DISCOVERY_TTL:-60}"

# Discover all z instances on the tailnet
# Usage: _z_discover [force]
_z_discover() {
    local force="${1:-false}"

    # Ensure cache directory exists
    local cache_dir=$(dirname "${Z_DISCOVERY_CACHE}")
    [[ ! -d "${cache_dir}" ]] && mkdir -p "${cache_dir}"

    # Check cache freshness unless forced
    if [[ "${force}" != "true" ]] && _z_discovery_cache_valid; then
        cat "${Z_DISCOVERY_CACHE}"
        return 0
    fi

    # Check if Tailscale is available
    if ! command -v tailscale &>/dev/null; then
        echo '{"timestamp":0,"machines":[]}'
        return 0
    fi

    # Get all Tailscale peers
    local peers=$(_z_get_tailscale_peers)
    if [[ -z "${peers}" ]]; then
        echo '{"timestamp":0,"machines":[]}'
        return 0
    fi

    local port="${Z_BEACON_PORT:-7681}"
    local machines="[]"
    local now=$(date +%s)

    # Probe each peer for z-beacon (in parallel using background jobs)
    local temp_dir=$(mktemp -d)
    local job_count=0

    echo "${peers}" | while IFS=$'\t' read -r peer_ip peer_name; do
        [[ -z "${peer_ip}" ]] && continue

        # Skip our own IP
        local my_ip=$(tailscale ip -4 2>/dev/null)
        [[ "${peer_ip}" == "${my_ip}" ]] && continue

        # Probe in background
        (
            local response=$(curl -s --connect-timeout 2 --max-time 3 \
                "http://${peer_ip}:${port}/z-beacon" 2>/dev/null)

            if [[ -n "${response}" ]] && echo "${response}" | grep -q '"name"'; then
                echo "${response}" > "${temp_dir}/${peer_ip}.json"
            fi
        ) &

        ((job_count++))

        # Limit concurrent probes
        if [[ ${job_count} -ge 10 ]]; then
            wait
            job_count=0
        fi
    done

    # Wait for all probes to complete
    wait

    # Collect results
    local discovered_machines="["
    local first=true

    for result_file in "${temp_dir}"/*.json(N); do
        [[ ! -f "${result_file}" ]] && continue

        local content=$(cat "${result_file}")
        if [[ "${first}" == "true" ]]; then
            discovered_machines="${discovered_machines}${content}"
            first=false
        else
            discovered_machines="${discovered_machines},${content}"
        fi
    done

    discovered_machines="${discovered_machines}]"

    # Clean up temp directory
    rm -rf "${temp_dir}"

    # Write cache
    local cache_content="{
  \"timestamp\": ${now},
  \"machines\": ${discovered_machines}
}"
    echo "${cache_content}" > "${Z_DISCOVERY_CACHE}"

    echo "${cache_content}"
}

# Get Tailscale peers (IPs and hostnames)
_z_get_tailscale_peers() {
    local status_json=$(tailscale status --json 2>/dev/null)
    [[ -z "${status_json}" ]] && return 1

    # Parse peer IPs and names from JSON
    # Format: IP<tab>hostname
    echo "${status_json}" | grep -E '"(TailscaleIPs|HostName)"' | \
        awk '
            /"TailscaleIPs"/ {
                # Get first IP (IPv4)
                getline
                gsub(/[^0-9.]/, "")
                ip = $0
            }
            /"HostName"/ {
                gsub(/.*"HostName": *"/, "")
                gsub(/".*/, "")
                if (ip != "" && $0 != "") {
                    print ip "\t" $0
                    ip = ""
                }
            }
        ' 2>/dev/null
}

# Check if discovery cache is still valid
_z_discovery_cache_valid() {
    [[ ! -f "${Z_DISCOVERY_CACHE}" ]] && return 1

    # Get cache file modification time
    local cache_time
    if [[ "$OSTYPE" == darwin* ]]; then
        cache_time=$(stat -f %m "${Z_DISCOVERY_CACHE}" 2>/dev/null)
    else
        cache_time=$(stat -c %Y "${Z_DISCOVERY_CACHE}" 2>/dev/null)
    fi

    [[ -z "${cache_time}" ]] && return 1

    local now=$(date +%s)
    local age=$((now - cache_time))

    [[ ${age} -lt ${Z_DISCOVERY_TTL} ]]
}

# Get discovered machines as a simple list
# Returns: name<tab>tailscale_ip per line
_z_get_discovered_machines() {
    local cache=$(_z_discover)

    echo "${cache}" | grep -E '"(name|tailscale_ip)"' | \
        paste - - | \
        sed 's/.*"name": *"\([^"]*\)".*"tailscale_ip": *"\([^"]*\)".*/\1\t\2/' 2>/dev/null
}
