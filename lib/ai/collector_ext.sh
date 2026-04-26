#!/bin/bash
# FILE: lib/ai/collector_ext.sh
# VERSION: 1.0.0
# START_MODULE_CONTRACT
#   PURPOSE: Extended system data collectors (Docker, Homebrew, Xcode)
#   SCOPE: Docker images/containers/volumes, Homebrew cache/outdated, Xcode simulators/archives
#   DEPENDS: lib/ai/collector.sh (for _fast_du_sk)
#   LINKS: M-AI-COLLECTOR-EXT
# END_MODULE_CONTRACT
#
# START_MODULE_MAP
#   _collect_docker_info - Docker disk usage, images, containers, volumes
#   _collect_homebrew_info - Homebrew cache, outdated packages, cellar breakdown
#   _collect_xcode_info - Xcode simulators, derived data, archives, device support
#   collector_ext_run_all - run all extended collectors
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - New module. Docker, Homebrew, Xcode collectors for extended system analysis.
# END_CHANGE_SUMMARY

set -euo pipefail

if [[ -n "${MOLE_AI_COLLECTOR_EXT_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_AI_COLLECTOR_EXT_LOADED=1

_MOLE_AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_AI_COLLECTOR_LOADED:-}" ]] && source "$_MOLE_AI_DIR/collector.sh"

# START_CONTRACT: _collect_docker_info
#   PURPOSE: Collect Docker disk usage, images, containers, and volumes
#   INPUTS: { none }
#   OUTPUTS: { String - formatted docker info to stdout }
#   SIDE_EFFECTS: runs docker commands (safe, read-only)
#   LINKS: M-AI-COLLECTOR-EXT
# END_CONTRACT: _collect_docker_info
_collect_docker_info() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker: not installed"
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Docker: installed but not running"
        return
    fi

    echo "Docker disk usage:"
    local du_output
    du_output=$(docker system df 2>/dev/null || echo "(unavailable)")
    echo "$du_output" | while IFS= read -r line; do
        echo "  $line"
    done

    echo ""
    echo "Docker images (by size):"
    docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null \
        | sort -t$'\t' -k2 -rh | head -15 | while IFS= read -r line; do
        echo "  $line"
    done || echo "  (none)"

    echo ""
    echo "Docker containers:"
    local running stopped
    running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
    stopped=$(docker ps -f "status=exited" -q 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
    echo "  Running: $running, Stopped: $stopped"

    echo ""
    echo "Docker volumes (by size):"
    docker volume ls -q 2>/dev/null | head -20 | while IFS= read -r vol; do
        [[ -z "$vol" ]] && continue
        local vol_path
        vol_path=$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null || echo "")
        if [[ -n "$vol_path" && -d "$vol_path" ]]; then
            local size
            size=$(_fast_du_sk "$vol_path" 2>/dev/null || echo "0")
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-40s %s\n" "$vol" "$human"
        else
            printf "  %-40s %s\n" "$vol" "(inaccessible)"
        fi
    done || echo "  (none)"
}

# START_CONTRACT: _collect_homebrew_info
#   PURPOSE: Collect Homebrew cache size, outdated packages, cellar breakdown
#   INPUTS: { none }
#   OUTPUTS: { String - formatted homebrew info to stdout }
#   SIDE_EFFECTS: runs brew commands (safe, read-only)
#   LINKS: M-AI-COLLECTOR-EXT
# END_CONTRACT: _collect_homebrew_info
_collect_homebrew_info() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew: not installed"
        return
    fi

    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")

    echo "Homebrew cache:"
    local brew_cache
    brew_cache=$(brew --cache 2>/dev/null || echo "")
    if [[ -n "$brew_cache" && -d "$brew_cache" ]]; then
        local size
        size=$(_fast_du_sk "$brew_cache")
        local human
        human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
        printf "  %-40s %s\n" "$brew_cache" "$human"
    else
        echo "  (cache not found)"
    fi

    echo ""
    echo "Homebrew Cellar (top packages by size):"
    if [[ -d "$brew_prefix/Cellar" ]]; then
        local cellar_size
        cellar_size=$(_fast_du_sk_bg "$brew_prefix/Cellar" 15)
        local cellar_human
        cellar_human=$(bytes_to_human_kb "$cellar_size" 2>/dev/null || echo "?")
        echo "  Total Cellar: $cellar_human"

        du -sk "$brew_prefix/Cellar"/* 2>/dev/null | sort -rn | head -15 | while IFS=$'\t' read -r sz path; do
            local pkg
            pkg=$(basename "$path")
            local human
            human=$(bytes_to_human_kb "$sz" 2>/dev/null || echo "?")
            printf "    %-30s %s\n" "$pkg" "$human"
        done
    else
        echo "  (Cellar not found)"
    fi

    echo ""
    echo "Outdated packages:"
    local outdated
    outdated=$(brew outdated --quiet 2>/dev/null || echo "")
    if [[ -n "$outdated" ]]; then
        local outdated_count
        outdated_count=$(echo "$outdated" | wc -l | tr -d ' \n')
        echo "  $outdated_count packages outdated:"
        echo "$outdated" | head -20 | while IFS= read -r line; do
            echo "    $line"
        done
    else
        echo "  All packages up to date"
    fi
}

# START_CONTRACT: _collect_xcode_info
#   PURPOSE: Collect Xcode simulator, derived data, archives, and device support sizes
#   INPUTS: { none }
#   OUTPUTS: { String - formatted Xcode info to stdout }
#   SIDE_EFFECTS: runs xcrun simctl commands (safe, read-only)
#   LINKS: M-AI-COLLECTOR-EXT
# END_CONTRACT: _collect_xcode_info
_collect_xcode_info() {
    local dev_dir
    dev_dir="$HOME/Library/Developer"

    if [[ ! -d "$dev_dir" ]]; then
        echo "Xcode: no Developer directory"
        return
    fi

    echo "Xcode Developer data:"
    local total_dev_size=0

    local -a xcode_paths=(
        "$dev_dir/Xcode/UserData:UserData"
        "$dev_dir/Xcode/DerivedData:DerivedData"
        "$dev_dir/CoreSimulator:CoreSimulator"
        "$dev_dir/Xcode/Archives:Archives"
        "$dev_dir/Xcode/iOS Device Logs:iOS Device Logs"
        "$dev_dir/Xcode/watchOS Device Logs:watchOS Device Logs"
        "$dev_dir/Xcode/watchOS DeviceSupport:watchOS DeviceSupport"
    )

    for entry in "${xcode_paths[@]}"; do
        local path="${entry%%:*}"
        local label="${entry#*:}"
        if [[ -d "$path" ]]; then
            local size
            size=$(_fast_du_sk_bg "$path" 10)
            [[ -z "$size" ]] && size=0
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-35s %s\n" "$label" "$human"
            [[ "$size" =~ ^[0-9]+$ ]] && total_dev_size=$((total_dev_size + size))
        fi
    done

    local total_human
    total_human=$(bytes_to_human_kb "$total_dev_size" 2>/dev/null || echo "?")
    echo ""
    echo "  Total Xcode data: $total_human"

    echo ""
    echo "iOS Simulators:"
    if command -v xcrun >/dev/null 2>&1; then
        xcrun simctl list devices 2>/dev/null | grep -E '(Booted|Shutdown)' | head -15 | while IFS= read -r line; do
            echo "  $line"
        done || echo "  (none)"
    else
        echo "  (xcrun not found)"
    fi

    echo ""
    echo "Xcode Archives:"
    if [[ -d "$dev_dir/Xcode/Archives" ]]; then
        find "$dev_dir/Xcode/Archives" -name "*.xcarchive" -maxdepth 3 -type d 2>/dev/null | while IFS= read -r archive; do
            local size
            size=$(_fast_du_sk_bg "$archive" 10)
            local human
            human=$(bytes_to_human_kb "$size" 2>/dev/null || echo "?")
            printf "  %-45s %s\n" "$(basename "$archive")" "$human"
        done || echo "  (none)"
    else
        echo "  (no archives)"
    fi
}

collector_ext_run_all() {
    set +e
    _collect_section "DOCKER" _collect_docker_info
    _collect_section "HOMEBREW" _collect_homebrew_info
    _collect_section "XCODE" _collect_xcode_info
    return 0
}
