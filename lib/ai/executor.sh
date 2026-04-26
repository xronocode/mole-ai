#!/bin/bash
# FILE: lib/ai/executor.sh
# VERSION: 1.0.0
# START_MODULE_CONTRACT
#   PURPOSE: Execute confirmed AI advisor plan items via safe_remove
#   SCOPE: Glob expansion, path resolution, safe deletion execution
#   DEPENDS: lib/core/file_ops.sh, lib/core/common.sh, lib/ai/renderer.sh
#   LINKS: M-AI-EXECUTOR
# END_MODULE_CONTRACT
#
# START_MODULE_MAP
#   _expand_glob_paths - expand glob patterns to actual file paths
#   _execute_plan - execute selected plan items through safe_remove
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - Extracted from bin/advisor.sh. Added MODULE_CONTRACT, MODULE_MAP, function CONTRACTs.
# END_CHANGE_SUMMARY

set -euo pipefail

if [[ -n "${MOLE_AI_EXECUTOR_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_AI_EXECUTOR_LOADED=1

_MOLE_AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_AI_COMMON_LOADED:-}" ]] && source "$_MOLE_AI_DIR/../core/common.sh"
[[ -z "${MOLE_AI_FILEOPS_LOADED:-}" ]] && source "$_MOLE_AI_DIR/../core/file_ops.sh"
[[ -z "${MOLE_AI_RENDERER_LOADED:-}" ]] && source "$_MOLE_AI_DIR/renderer.sh"

# START_CONTRACT: _expand_glob_paths
#   PURPOSE: Expand a glob path pattern to actual filesystem paths
#   INPUTS: { pattern: String - path pattern, may end with /* for directory contents }
#   OUTPUTS: { String - one path per line on stdout }
#   SIDE_EFFECTS: none
#   LINKS: M-AI-EXECUTOR
# END_CONTRACT: _expand_glob_paths
_expand_glob_paths() {
    local pattern="$1"
    if [[ "$pattern" == *"/*" ]]; then
        local base="${pattern%/*}"
        if [[ -d "$base" ]]; then
            find "$base" -maxdepth 1 -mindepth 1 2>/dev/null || true
            return
        fi
    fi
    for expanded in $pattern; do
        [[ -e "$expanded" ]] && echo "$expanded"
    done
}

# START_CONTRACT: _execute_plan
#   PURPOSE: Execute all selected plan items using safe_remove pipeline
#   INPUTS: { none - reads _PLAN_* arrays from renderer.sh }
#   OUTPUTS: { none - prints progress to stdout }
#   SIDE_EFFECTS: deletes files/directories via safe_remove
#   LINKS: M-AI-EXECUTOR, M-CORE-FILE-OPS
# END_CONTRACT: _execute_plan
_execute_plan() {
    local count=${#_PLAN_TITLES[@]}
    local executed=0
    local failed=0
    local total_recovered=0
    local i

    echo ""
    echo -e "${PURPLE_BOLD}${ICON_ARROW} Executing Plan${NC}"
    echo ""

    for ((i = 0; i < count; i++)); do
        [[ "${_PLAN_SELECTED[$i]}" != "1" ]] && continue

        local risk_c
        risk_c=$(_risk_color "${_PLAN_RISKS[$i]}")
        echo -e "  ${ICON_LIST} ${_PLAN_TITLES[$i]} ${risk_c}[${_PLAN_RISKS[$i]}]${NC}"

        local IFS_OLD="$IFS"
        IFS='|'
        read -ra paths_arr <<< "${_PLAN_PATHS[$i]}"
        IFS="$IFS_OLD"

        for p in "${paths_arr[@]}"; do
            if [[ "$p" == *"/*" ]]; then
                local base="${p%/*}"
                if [[ -d "$base" ]]; then
                    local size_kb=0
                    size_kb=$(get_path_size_kb "$base" 2>/dev/null || echo "0")
                    local items
                    items=$(find "$base" -maxdepth 1 -mindepth 1 2>/dev/null || true)
                    local item_count=0
                    local item_failed=0
                    while IFS= read -r target; do
                        [[ -z "$target" ]] && continue
                        if [[ -e "$target" ]]; then
                            if safe_remove "$target" "true"; then
                                item_count=$((item_count + 1))
                            else
                                echo -e "    ${RED}${ICON_ERROR}${NC} Skipped: ${target}"
                                item_failed=$((item_failed + 1))
                            fi
                        fi
                    done <<< "$items"
                    if [[ $item_count -gt 0 ]]; then
                        local human
                        human=$(bytes_to_human "$((size_kb * 1024))" 2>/dev/null || echo "?")
                        echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Cleared ${item_count} items from ${base} (${human})"
                        total_recovered=$((total_recovered + size_kb))
                        executed=$((executed + 1))
                    fi
                    failed=$((failed + item_failed))
                else
                    echo -e "    ${GRAY}${ICON_EMPTY}${NC} Directory not found: ${base}"
                fi
            else
                if [[ -e "$p" ]]; then
                    local size_kb=0
                    size_kb=$(get_path_size_kb "$p" 2>/dev/null || echo "0")
                    if safe_remove "$p" "true"; then
                        local human
                        human=$(bytes_to_human "$((size_kb * 1024))" 2>/dev/null || echo "?")
                        echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Removed: ${p} (${human})"
                        total_recovered=$((total_recovered + size_kb))
                        executed=$((executed + 1))
                    else
                        echo -e "    ${RED}${ICON_ERROR}${NC} Skipped (protected): ${p}"
                        failed=$((failed + 1))
                    fi
                else
                    echo -e "    ${GRAY}${ICON_EMPTY}${NC} Not found: ${p}"
                fi
            fi
        done
    done

    echo ""
    local total_human
    total_human=$(bytes_to_human_kb "$total_recovered" 2>/dev/null || echo "?")
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Done: ${executed} items removed, ${total_human} recovered"
    [[ $failed -gt 0 ]] && echo -e "  ${YELLOW}${ICON_WARNING}${NC} ${failed} items skipped (protected or inaccessible)"
    echo ""
}
