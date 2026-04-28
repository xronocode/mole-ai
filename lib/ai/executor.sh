#!/bin/bash
# FILE: lib/ai/executor.sh
# VERSION: 1.1.0
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
#   _get_tool_specific_cmd - return tool-specific cleanup command for known paths
#   _execute_tool_cmd - execute a tool-specific cleanup command
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - Extracted from bin/advisor.sh. Added MODULE_CONTRACT, MODULE_MAP, function CONTRACTs.
#   v1.1.0 - Added tool-specific cleanup commands. Fixed "Skipped (protected)" for permission denied.
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

# START_CONTRACT: _get_tool_specific_cmd
#   PURPOSE: Return tool-specific cleanup command for known cache/tool paths
#   INPUTS: { path: String - filesystem path to clean }
#   OUTPUTS: { String - cleanup command (empty string if no tool-specific command) }
#   SIDE_EFFECTS: none
#   LINKS: M-AI-EXECUTOR
# END_CONTRACT: _get_tool_specific_cmd
_get_tool_specific_cmd() {
    local path="$1"
    case "$path" in
        */.npm/_cacache | */.npm)
            echo "npm cache clean --force 2>/dev/null"
            ;;
        */Caches/Homebrew)
            echo "brew cleanup --prune=all 2>/dev/null"
            ;;
        */Caches/Homebrew/*)
            echo "brew cleanup --prune=all 2>/dev/null"
            ;;
        */Library/Containers/com.docker.docker*)
            echo "docker system prune -f 2>/dev/null"
            ;;
    esac
}

# START_CONTRACT: _execute_tool_cmd
#   PURPOSE: Execute a tool-specific cleanup command and report result
#   INPUTS: { cmd: String - command to run, path: String - path being cleaned }
#   OUTPUTS: { none - prints progress to stdout }
#   SIDE_EFFECTS: runs cleanup command
#   LINKS: M-AI-EXECUTOR
# END_CONTRACT: _execute_tool_cmd
_execute_tool_cmd() {
    local cmd="$1"
    local path="$2"
    local tool_exit=0
    eval "$cmd" > /dev/null 2>&1 || tool_exit=$?
    if [[ $tool_exit -eq 0 ]]; then
        echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Cleaned via tool command: ${cmd%% *}"
        return 0
    else
        echo -e "    ${YELLOW}${ICON_WARNING}${NC} Tool command failed (exit ${tool_exit}), falling back to rm: ${cmd%% *}"
        return 1
    fi
}

# START_CONTRACT: _format_skip_reason
#   PURPOSE: Return human-readable skip reason based on safe_remove exit code
#   INPUTS: { exit_code: int - exit code from safe_remove }
#   OUTPUTS: { String - formatted reason string }
#   SIDE_EFFECTS: none
#   LINKS: M-AI-EXECUTOR
# END_CONTRACT: _format_skip_reason
_format_skip_reason() {
    local rc="$1"
    case "$rc" in
        10) echo "SIP protected" ;;
        11) echo "auth required" ;;
        12) echo "read-only filesystem" ;;
        13) echo "permission denied" ;;
        *) echo "error" ;;
    esac
}

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
            find "$base" -maxdepth 1 -mindepth 1 2> /dev/null || true
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
    local skipped_perm=0
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
            local tool_cmd
            tool_cmd=$(_get_tool_specific_cmd "$p")

            if [[ "$p" == *"/*" ]]; then
                local base="${p%/*}"
                if [[ -d "$base" ]]; then
                    local size_kb=0
                    size_kb=$(get_path_size_kb "$base" 2> /dev/null || echo "0")

                    if [[ -n "$tool_cmd" ]]; then
                        if _execute_tool_cmd "$tool_cmd" "$base"; then
                            executed=$((executed + 1))
                            total_recovered=$((total_recovered + size_kb))
                            continue
                        fi
                    fi

                    local items
                    items=$(find "$base" -maxdepth 1 -mindepth 1 2> /dev/null || true)
                    local item_count=0
                    local item_failed=0
                    while IFS= read -r target; do
                        [[ -z "$target" ]] && continue
                        if [[ -e "$target" ]]; then
                            local rm_rc=0
                            safe_remove "$target" "true" || rm_rc=$?
                            if [[ $rm_rc -eq 0 ]]; then
                                item_count=$((item_count + 1))
                            else
                                local reason
                                reason=$(_format_skip_reason "$rm_rc")
                                echo -e "    ${YELLOW}${ICON_WARNING}${NC} Skipped (${reason}): ${target}"
                                item_failed=$((item_failed + 1))
                            fi
                        fi
                    done <<< "$items"
                    if [[ $item_count -gt 0 ]]; then
                        local human
                        human=$(bytes_to_human "$((size_kb * 1024))" 2> /dev/null || echo "?")
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
                    if [[ -n "$tool_cmd" ]]; then
                        if _execute_tool_cmd "$tool_cmd" "$p"; then
                            local size_kb=0
                            size_kb=$(get_path_size_kb "$p" 2> /dev/null || echo "0")
                            total_recovered=$((total_recovered + size_kb))
                            executed=$((executed + 1))
                            continue
                        fi
                    fi

                    local size_kb=0
                    size_kb=$(get_path_size_kb "$p" 2> /dev/null || echo "0")
                    local rm_rc=0
                    safe_remove "$p" "true" || rm_rc=$?
                    if [[ $rm_rc -eq 0 ]]; then
                        local human
                        human=$(bytes_to_human "$((size_kb * 1024))" 2> /dev/null || echo "?")
                        echo -e "    ${GREEN}${ICON_SUCCESS}${NC} Removed: ${p} (${human})"
                        total_recovered=$((total_recovered + size_kb))
                        executed=$((executed + 1))
                    else
                        local reason
                        reason=$(_format_skip_reason "$rm_rc")
                        echo -e "    ${RED}${ICON_ERROR}${NC} Skipped (${reason}): ${p}"
                        failed=$((failed + 1))
                        [[ $rm_rc -eq 13 ]] && skipped_perm=$((skipped_perm + 1))
                    fi
                else
                    echo -e "    ${GRAY}${ICON_EMPTY}${NC} Not found: ${p}"
                fi
            fi
        done
    done

    echo ""
    local total_human
    total_human=$(bytes_to_human_kb "$total_recovered" 2> /dev/null || echo "?")
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Done: ${executed} items removed, ${total_human} recovered"
    [[ $failed -gt 0 ]] && echo -e "  ${YELLOW}${ICON_WARNING}${NC} ${failed} items skipped"
    [[ $skipped_perm -gt 0 ]] && echo -e "  ${YELLOW}${ICON_WARNING}${NC} ${skipped_perm} items need elevated permissions or tool-specific cleanup"
    echo ""
}
