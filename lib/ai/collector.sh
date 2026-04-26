#!/bin/bash
# FILE: lib/ai/collector.sh
# VERSION: 1.0.0
# START_MODULE_CONTRACT
#   PURPOSE: Gather system state information as structured text for AI analysis
#   SCOPE: Disk usage, memory, CPU, uptime, trash, cleanable items, installers, network, battery
#   DEPENDS: lib/core/base.sh
#   LINKS: M-AI-COLLECTOR
# END_MODULE_CONTRACT
#
# START_MODULE_MAP
#   collector_run_all - run all collection sections to stdout, auto-sources collector_ext.sh
#   _fast_du_sk - get directory size in KB via du -sk
#   _fast_du_sk_bg - get directory size with background timeout guard
#   _collect_section - output section header and call collector function
#   _collect_disk_usage - scan user dirs, system dirs, large containers
#   _collect_memory_info - memory stats from sysctl + vm_stat
#   _collect_cpu_info - CPU info and top processes
#   _collect_uptime_info - uptime and macOS version
#   _collect_cleanable_items - cache dirs, system-level cleanable, build artifacts
#   _collect_trash - trash size and item count
#   _collect_installer_files - DMG/PKG/ZIP files in Downloads
#   _collect_network_info - active connections and DNS
#   _collect_battery_info - battery level and status
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - Initial module. 9 base collection sections + auto-source collector_ext.sh.
# END_CHANGE_SUMMARY

if [[ -n "${MOLE_AI_COLLECTOR_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_AI_COLLECTOR_LOADED=1

_MOLE_AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_BASE_LOADED:-}" ]] && source "$_MOLE_AI_DIR/../core/base.sh"

_fast_du_sk() {
    local dir="$1"
    local size
    size=$(du -sk "$dir" 2>/dev/null | awk '{print $1}') || size="0"
    echo "${size:-0}"
}

_fast_du_sk_bg() {
    local dir="$1"
    local timeout_sec="${2:-15}"
    local tmp="/tmp/_mole_du_$$_${RANDOM}"
    du -sk "$dir" > "$tmp" 2>/dev/null &
    local du_pid=$!
    local elapsed=0
    while true; do
        if ! kill -0 "$du_pid" 2>/dev/null; then
            break
        fi
        if [[ $elapsed -ge $timeout_sec ]]; then
            kill "$du_pid" 2>/dev/null
            wait "$du_pid" 2>/dev/null
            rm -f "$tmp"
            echo ""
            return
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$du_pid" 2>/dev/null || true
    cat "$tmp" 2>/dev/null | awk '{print $1}'
    rm -f "$tmp"
}

_collect_section() {
    local title="$1"
    shift
    echo "=== $title ==="
    "$@" 2>/dev/null || echo "(unavailable)"
    echo ""
}

_collect_disk_usage() {
    echo "All volumes:"
    df -h 2>/dev/null | grep -E '^/dev/' || true
    echo ""

    echo "User directories:"
    local -a user_dirs=(
        "$HOME/Library/Caches"
        "$HOME/Library/Logs"
        "$HOME/Library/Developer"
        "$HOME/Library/Application Support:20"
        "$HOME/Library/Containers:20"
        "$HOME/Library/Mail"
        "$HOME/Library/Messages"
        "$HOME/Library/Group Containers"
        "$HOME/.Trash"
        "$HOME/Downloads"
        "$HOME/Documents"
        "$HOME/Desktop"
    )
    for entry in "${user_dirs[@]}"; do
        local dir="${entry%%:*}"
        local tout="${entry##*:}"
        [[ "$tout" == "$dir" ]] && tout=""
        if [[ -d "$dir" ]]; then
            local size
            if [[ -n "$tout" ]]; then
                size=$(_fast_du_sk_bg "$dir" "$tout")
            else
                size=$(_fast_du_sk "$dir")
            fi
            [[ -z "$size" || "$size" == "0" ]] && continue
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-50s %s\n" "$dir" "$human"
        fi
    done

    echo ""
    echo "System directories:"
    local -a sys_dirs=(
        "/Applications:30"
        "/Library/Caches"
        "/Library/Logs"
        "/Library/Application Support:20"
        "/opt/homebrew:20"
        "/opt/homebrew/Cellar:20"
        "/usr/local/Cellar"
        "/private/var/folders"
        "/private/var/log"
    )
    for entry in "${sys_dirs[@]}"; do
        local dir="${entry%%:*}"
        local tout="${entry##*:}"
        [[ "$tout" == "$dir" ]] && tout=""
        if [[ -d "$dir" ]]; then
            local size
            if [[ -n "$tout" ]]; then
                size=$(_fast_du_sk_bg "$dir" "$tout")
            else
                size=$(_fast_du_sk "$dir")
            fi
            [[ -z "$size" || "$size" == "0" ]] && continue
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-50s %s\n" "$dir" "$human"
        fi
    done

    echo ""
    echo "Large containers:"
    local -a container_paths=(
        "$HOME/Library/Containers/com.docker.docker:Docker:20"
        "$HOME/Library/Containers/com.apple.mail:Apple Mail:15"
        "$HOME/.docker:Docker CLI:15"
        "$HOME/.ollama:Ollama models:15"
        "$HOME/.cargo:Cargo/Rust:15"
        "$HOME/.rustup:Rustup:15"
        "$HOME/.go:Go:15"
        "$HOME/go:Go workspace:15"
        "$HOME/.cache:User cache root:15"
    )
    for entry in "${container_paths[@]}"; do
        local path="${entry%%:*}"
        local rest="${entry#*:}"
        local label="${rest%%:*}"
        local tout="${rest##*:}"
        [[ "$tout" == "$rest" ]] && tout=""
        for expanded in $path; do
            if [[ -d "$expanded" ]]; then
                local size
                if [[ -n "$tout" ]]; then
                    size=$(_fast_du_sk_bg "$expanded" "$tout")
                else
                    size=$(_fast_du_sk "$expanded")
                fi
                [[ -z "$size" || "$size" == "0" ]] && continue
                local human
                human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
                printf "  %-25s %8s  (%s)\n" "$label" "$human" "$expanded"
            fi
        done
    done
}

_collect_memory_info() {
    local total_bytes used_gb total_gb active wired compressed page_size
    total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    total_gb=$(LC_ALL=C awk "BEGIN {printf \"%.1f\", $total_bytes / (1024*1024*1024)}" 2>/dev/null || echo "?")

    local vm_output
    vm_output=$(vm_stat 2>/dev/null || echo "")
    page_size=4096
    active=$(echo "$vm_output" | awk '/Pages active:/ {print $NF}' | tr -d '.\n' 2>/dev/null || echo "0")
    wired=$(echo "$vm_output" | awk '/Pages wired down:/ {print $NF}' | tr -d '.\n' 2>/dev/null || echo "0")
    compressed=$(echo "$vm_output" | awk '/Pages occupied by compressor:/ {print $NF}' | tr -d '.\n' 2>/dev/null || echo "0")
    active=${active:-0}; wired=${wired:-0}; compressed=${compressed:-0}
    local used_bytes=$(( (active + wired + compressed) * page_size ))
    used_gb=$(LC_ALL=C awk "BEGIN {printf \"%.1f\", $used_bytes / (1024*1024*1024)}" 2>/dev/null || echo "?")

    local swap_used
    swap_used=$(sysctl -n vm.swapusage 2>/dev/null | awk '/used/ {print $3}' | tr -d 'M' || echo "0")

    local pressure
    pressure=$(memory_pressure 2>/dev/null | head -1 || echo "unknown")

    echo "Total: ${total_gb}GB"
    echo "Active+Wired+Compressed: ${used_gb}GB"
    echo "Swap used: ${swap_used}MB"
    echo "Pressure: $pressure"
}

_collect_cpu_info() {
    local chip cores
    chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")
    cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")

    local load
    load=$(uptime 2>/dev/null | sed 's/.*load averages: //' || echo "?")

    local top_procs
    top_procs=$(ps aux 2>/dev/null | sort -k3 -rn | head -6 || echo "(unavailable)")

    echo "Chip: $chip"
    echo "Cores: $cores"
    echo "Load averages: $load"
    echo "Top CPU processes:"
    echo "$top_procs" | while IFS= read -r line; do
        echo "  $line"
    done
}

_collect_uptime_info() {
    local boot_output boot_time
    boot_output=$(sysctl -n kern.boottime 2>/dev/null || echo "")
    boot_time=$(echo "$boot_output" | awk -F 'sec = |, usec' '{print $2}' 2>/dev/null || echo "")
    if [[ -n "$boot_time" && "$boot_time" =~ ^[0-9]+$ ]]; then
        local now
        now=$(get_epoch_seconds)
        local uptime_sec=$((now - boot_time))
        local days=$((uptime_sec / 86400))
        local hours=$(( (uptime_sec % 86400) / 3600 ))
        echo "Uptime: ${days}d ${hours}h"
    else
        echo "Uptime: unknown"
    fi

    local os_ver
    os_ver=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    local arch
    arch=$(detect_architecture)
    echo "macOS: $os_ver ($arch)"
}

_collect_cleanable_items() {
    echo "User cache/app data:"

    local -a check_paths=(
        "$HOME/Library/Caches:User caches"
        "$HOME/Library/Logs:User logs"
        "$HOME/Library/Mail/V*:Mail data"
        "$HOME/Library/Messages:Messages data"
        "$HOME/Library/Developer/Xcode:Xcode data"
        "$HOME/Library/Caches/com.openai.chat:ChatGPT cache"
        "$HOME/.npm:NPM cache"
        "$HOME/.cache/pip:Pip cache"
        "$HOME/.cache/huggingface:Hugging Face cache"
        "$HOME/.ollama:Ollama data"
        "$HOME/.local/share/claude:Claude Code data"
        "$HOME/.gradle/caches:Gradle cache"
        "$HOME/.m2/repository:Maven cache"
        "$HOME/.cargo/registry:Cargo registry"
        "$HOME/Library/Containers/com.docker.docker:Docker data"
        "$HOME/.docker:Docker CLI config"
    )

    for entry in "${check_paths[@]}"; do
        local path="${entry%%:*}"
        local label="${entry#*:}"
        for expanded in $path; do
            if [[ -d "$expanded" ]]; then
                local size
                size=$(_fast_du_sk "$expanded")
                local human
                human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
                printf "  %-40s %8s  (%s)\n" "$label" "$human" "$expanded"
            fi
        done
    done

    echo ""
    echo "System-level cleanable:"
    local -a sys_clean=(
        "/Library/Caches:System caches"
        "/Library/Logs:System logs"
        "/private/var/log:System var logs"
        "/opt/homebrew/Cellar:Homebrew cellar"
    )
    for entry in "${sys_clean[@]}"; do
        local path="${entry%%:*}"
        local label="${entry#*:}"
        if [[ -d "$path" ]]; then
            local size
            size=$(_fast_du_sk "$path")
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-40s %8s  (%s)\n" "$label" "$human" "$path"
        fi
    done

    if command -v brew >/dev/null 2>&1; then
        local brew_cache
        brew_cache=$(brew --cache 2>/dev/null || echo "")
        if [[ -n "$brew_cache" && -d "$brew_cache" ]]; then
            local size
            size=$(_fast_du_sk "$brew_cache")
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-40s %8s  (%s)\n" "Homebrew cache" "$human" "$brew_cache"
        fi
    fi

    echo ""
    echo "Project build artifacts:"

    local artifact_count=0
    local -a scan_dirs=("$HOME/Documents" "$HOME/Developer" "$HOME/projects" "$HOME/code" "$HOME/src")
    for scan_dir in "${scan_dirs[@]}"; do
        [[ -d "$scan_dir" ]] || continue
        while IFS= read -r -d '' artifact_dir; do
            local size
            size=$(_fast_du_sk "$artifact_dir")
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-40s %8s  (%s)\n" "$(basename "$artifact_dir")" "$human" "$artifact_dir"
            artifact_count=$((artifact_count + 1))
            [[ $artifact_count -ge 20 ]] && break
        done < <(find "$scan_dir" -maxdepth 4 \( -name "node_modules" -o -name ".venv" -o -name "venv" -o -name "target" -o -name "build" -o -name ".gradle" -o -name "__pycache__" \) -type d -prune 2>/dev/null | head -20)
        [[ $artifact_count -ge 20 ]] && break
    done
    [[ $artifact_count -eq 0 ]] && echo "  (none found in common directories)"
}

_collect_trash() {
    local trash_size
    trash_size=$(_fast_du_sk "$HOME/.Trash")
    local human
    human=$(bytes_to_human_kb "$trash_size" 2>/dev/null || echo "empty")
    local count
    count=$(find "$HOME/.Trash" -maxdepth 1 2>/dev/null | wc -l | tr -d ' \n' 2>/dev/null || echo "0")
    count="${count:-0}"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    local items=$((count > 0 ? count - 1 : 0))
    echo "Trash: $human ($items items)"
}

_collect_installer_files() {
    local total=0
    local found=""
    local -a exts=("dmg" "pkg" "zip" "ipa")
    for ext in "${exts[@]}"; do
        while IFS= read -r -d '' f; do
            local size
            size=$($STAT_BSD -f%z "$f" 2>/dev/null || echo "0")
            total=$((total + size))
            local human
            human=$(bytes_to_human "$size" 2>/dev/null || echo "?")
            found="${found}  $(basename "$f") ($human) — $f\n"
        done < <(find "$HOME/Downloads" -maxdepth 2 -name "*.${ext}" -type f -print0 2>/dev/null | head -20)
    done
    if [[ -n "$found" ]]; then
        echo -e "$found" | head -20
        local total_human
        total_human=$(bytes_to_human "$total" 2>/dev/null || echo "?")
        echo "Total installer files: $total_human"
    else
        echo "No installer files found in Downloads"
    fi
}

_collect_network_info() {
    local connections
    connections=$(netstat -an 2>/dev/null | awk '/ESTABLISHED/ {count++} END {print count+0}' || echo "?")
    echo "Active connections: $connections"

    local dns
    dns=$(scutil --dns 2>/dev/null | grep "nameserver" | head -5 || echo "unknown")
    echo "DNS servers:"
    echo "$dns" | while IFS= read -r line; do
        echo "  $line"
    done
}

_collect_battery_info() {
    if command -v pmset >/dev/null 2>&1; then
        local batt
        batt=$(pmset -g batt 2>/dev/null || echo "")
        if [[ -n "$batt" ]]; then
            echo "$batt" | tail -1
        else
            echo "(no battery)"
        fi
    else
        echo "(unavailable)"
    fi
}

collector_run_all() {
    set +e
    _collect_section "SYSTEM OVERVIEW" _collect_uptime_info
    _collect_section "DISK USAGE" _collect_disk_usage
    _collect_section "MEMORY" _collect_memory_info
    _collect_section "CPU" _collect_cpu_info
    _collect_section "TRASH" _collect_trash
    _collect_section "CLEANABLE ITEMS" _collect_cleanable_items
    _collect_section "INSTALLER FILES" _collect_installer_files
    _collect_section "NETWORK" _collect_network_info
    _collect_section "BATTERY" _collect_battery_info

    [[ -z "${MOLE_AI_COLLECTOR_EXT_LOADED:-}" ]] && source "$_MOLE_AI_DIR/collector_ext.sh"
    collector_ext_run_all

    return 0
}
