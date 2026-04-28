#!/bin/bash
# FILE: lib/ai/renderer.sh
# VERSION: 1.0.0
# START_MODULE_CONTRACT
#   PURPOSE: Render AI advisor report and interactive plan selection UI
#   SCOPE: Markdown report rendering, plan parsing, interactive menu, confirmation
#   DEPENDS: lib/core/ui.sh, lib/core/common.sh
#   LINKS: M-AI-RENDERER
# END_MODULE_CONTRACT
#
# START_MODULE_MAP
#   _risk_color - color code for risk level
#   _risk_icon - icon for risk level
#   _render_report - render markdown report to terminal
#   _extract_json_plan - extract JSON plan from AI response
#   _parse_plan_items - parse JSON plan into TSV lines
#   _load_plan - load plan items into arrays
#   _show_plan_menu - display interactive selection menu
#   _interactive_select - interactive plan selection loop
#   _show_confirmation - show execution confirmation prompt
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - Extracted from bin/advisor.sh. Added risk filter (F key), scrolling, _update_visible_indices, _cycle_risk_filter.
# END_CHANGE_SUMMARY

set -euo pipefail

if [[ -n "${MOLE_AI_RENDERER_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_AI_RENDERER_LOADED=1

_MOLE_AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_AI_COMMON_LOADED:-}" ]] && source "$_MOLE_AI_DIR/../core/common.sh"
[[ -z "${MOLE_AI_UI_LOADED:-}" ]] && source "$_MOLE_AI_DIR/../core/ui.sh"

_risk_color() {
    case "$1" in
        SAFE) printf '%s' "$GREEN" ;;
        CAUTION) printf '%s' "$YELLOW" ;;
        RISKY) printf '%s' "$RED" ;;
        *) printf '%s' "$NC" ;;
    esac
}

_risk_icon() {
    case "$1" in
        SAFE) printf '%s' "$ICON_SUCCESS" ;;
        CAUTION) printf '%s' "$ICON_WARNING" ;;
        RISKY) printf '%s' "$ICON_ERROR" ;;
        *) printf '%s' " " ;;
    esac
}

# START_CONTRACT: _render_report
#   PURPOSE: Render markdown report from AI response to formatted terminal output
#   INPUTS: { md: String - markdown text }
#   OUTPUTS: { none - prints to stdout }
#   SIDE_EFFECTS: none
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _render_report
_render_report() {
    local md="$1"
    [[ -z "$md" ]] && return

    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^##\ +Not\ Recommended ]]; then
            echo ""
            echo -e "  ${RED}${ICON_ERROR} Not Recommended for Deletion${NC}"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^##\ +Low\ Risk ]]; then
            echo ""
            echo -e "  ${GREEN}${ICON_SUCCESS} Low Risk (Recommended)${NC}"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^##\ +Medium || "$line" =~ ^##\ +High\ Risk ]]; then
            echo ""
            echo -e "  ${YELLOW}${ICON_WARNING} Medium/High Risk (Your Decision)${NC}"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^##\ +Disk\ Usage || "$line" =~ ^###\ +Section\ +1 ]]; then
            echo ""
            echo -e "  ${CYAN}${ICON_ARROW} Disk Usage Summary${NC}"
            echo ""
            continue
        fi
        if [[ "$line" =~ ^\|.+\|.+\| ]]; then
            if [[ "$line" =~ ^\|[\ -]+(\|[\ -]+)+$ ]]; then
                continue
            fi
            local col1="" col2="" col3=""
            IFS='|' read -r _ col1 col2 col3 _ <<< "$line"
            col1="${col1#"${col1%%[![:space:]]*}"}"
            col2="${col2#"${col2%%[![:space:]]*}"}"
            col3="${col3#"${col3%%[![:space:]]*}"}"
            col1="${col1%"${col1##*[![:space:]]}"}"
            col2="${col2%"${col2##*[![:space:]]}"}"
            col3="${col3%"${col3##*[![:space:]]}"}"
            printf "    %-42s %-10s %s\n" "$col1" "$col2" "${col3:-}"
            continue
        fi
        if [[ "$line" =~ ^-\ +(.+)$ ]]; then
            local item="${BASH_REMATCH[1]}"
            item="${item#\*\*}"
            item="${item%\*\*}"
            item="${item//\*\*/}"
            echo -e "    ${ICON_LIST} ${item}"
            continue
        fi
        if [[ "$line" =~ ^None ]]; then
            echo -e "    ${GRAY}None — no concerns.${NC}"
            continue
        fi
        line="${line#\# }"
        line="${line#\#\# }"
        line="${line#\#\#\# }"
        [[ -n "$line" ]] && echo -e "  ${GRAY}${line}${NC}"
    done <<< "$md"
}

# START_CONTRACT: _extract_json_plan
#   PURPOSE: Extract JSON plan block from AI response text
#   INPUTS: { response: String - full AI response }
#   OUTPUTS: { String - extracted JSON block }
#   SIDE_EFFECTS: none
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _extract_json_plan
_extract_json_plan() {
    local response="$1"
    local json_block
    json_block=$(echo "$response" | sed -n '/^```json$/,/^```$/p' | sed '1d;$d')
    if [[ -z "$json_block" ]]; then
        json_block=$(echo "$response" | python3 -c "
import sys, json, re
text = sys.stdin.read()
match = re.search(r'\`\`\`json\s*(\{.*?\})\s*\`\`\`', text, re.DOTALL)
if match:
    print(match.group(1))
else:
    start = text.find('{')
    if start >= 0:
        depth = 0
        for i in range(start, len(text)):
            if text[i] == '{': depth += 1
            elif text[i] == '}': depth -= 1
            if depth == 0:
                print(text[start:i+1])
                break
" 2>/dev/null || true)
    fi
    echo "$json_block"
}

# START_CONTRACT: _parse_plan_items
#   PURPOSE: Parse JSON plan into pipe-delimited lines for bash consumption
#   INPUTS: { json: String - JSON plan object (via stdin) }
#   OUTPUTS: { String - pipe-delimited lines: num|title|reason|risk|paths|est|cmd }
#   SIDE_EFFECTS: none
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _parse_plan_items
_parse_plan_items() {
    local json="$1"
    python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    plan = data.get('plan', [])
    for i, item in enumerate(plan):
        title = item.get('title', 'Unknown')
        reason = item.get('reason', '')
        risk = item.get('risk', 'CAUTION')
        paths = '|'.join(item.get('paths', []))
        est = item.get('estimated_size', '?')
        cmd = item.get('command', 'custom')
        print(f'{i+1}|{title}|{reason}|{risk}|{paths}|{est}|{cmd}')
except Exception as e:
    print(f'ERROR|Parse error: {e}|||||', file=sys.stderr)
" <<< "$json" 2>/dev/null
}

declare -a _PLAN_TITLES=()
declare -a _PLAN_REASONS=()
declare -a _PLAN_RISKS=()
declare -a _PLAN_PATHS=()
declare -a _PLAN_SIZES=()
declare -a _PLAN_CMDS=()
declare -a _PLAN_SELECTED=()
declare -a _PLAN_VISIBLE=()

_PLAN_RISK_FILTER=""
_PLAN_SCROLL_OFFSET=0
_PLAN_PAGE_SIZE=15

# START_CONTRACT: _update_visible_indices
#   PURPOSE: Recalculate which items are visible based on current risk filter
#   INPUTS: { none - reads _PLAN_* arrays and _PLAN_RISK_FILTER }
#   OUTPUTS: { none - updates _PLAN_VISIBLE array }
#   SIDE_EFFECTS: modifies _PLAN_VISIBLE
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _update_visible_indices
_update_visible_indices() {
    _PLAN_VISIBLE=()
    local count=${#_PLAN_TITLES[@]}
    local i
    for ((i = 0; i < count; i++)); do
        if [[ -n "$_PLAN_RISK_FILTER" ]]; then
            if [[ "${_PLAN_RISKS[$i]}" == "$_PLAN_RISK_FILTER" ]]; then
                _PLAN_VISIBLE+=("$i")
            fi
        else
            _PLAN_VISIBLE+=("$i")
        fi
    done
    _PLAN_SCROLL_OFFSET=0
}

# START_CONTRACT: _cycle_risk_filter
#   PURPOSE: Cycle through risk filter states: "" -> SAFE -> CAUTION -> RISKY -> ""
#   INPUTS: { none }
#   OUTPUTS: { none - updates _PLAN_RISK_FILTER }
#   SIDE_EFFECTS: modifies _PLAN_RISK_FILTER and recalculates visible indices
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _cycle_risk_filter
_cycle_risk_filter() {
    case "$_PLAN_RISK_FILTER" in
        "") _PLAN_RISK_FILTER="SAFE" ;;
        SAFE) _PLAN_RISK_FILTER="CAUTION" ;;
        CAUTION) _PLAN_RISK_FILTER="RISKY" ;;
        RISKY) _PLAN_RISK_FILTER="" ;;
    esac
    _update_visible_indices
}

# START_CONTRACT: _load_plan
#   PURPOSE: Load parsed plan items into parallel arrays
#   INPUTS: { json: String - JSON plan object }
#   OUTPUTS: { Int - 0 on success, 1 on parse error }
#   SIDE_EFFECTS: populates _PLAN_* arrays
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _load_plan
_load_plan() {
    local json="$1"
    _PLAN_TITLES=()
    _PLAN_REASONS=()
    _PLAN_RISKS=()
    _PLAN_PATHS=()
    _PLAN_SIZES=()
    _PLAN_CMDS=()
    _PLAN_SELECTED=()
    _PLAN_VISIBLE=()
    _PLAN_RISK_FILTER=""
    _PLAN_SCROLL_OFFSET=0

    while IFS='|' read -r num title reason risk paths est cmd; do
        [[ "$num" == ERROR* ]] && return 1
        _PLAN_TITLES+=("$title")
        _PLAN_REASONS+=("$reason")
        _PLAN_RISKS+=("$risk")
        _PLAN_PATHS+=("$paths")
        _PLAN_SIZES+=("$est")
        _PLAN_CMDS+=("$cmd")
        _PLAN_SELECTED+=(0)
    done < <(_parse_plan_items "$json")
}

# START_CONTRACT: _show_plan_menu
#   PURPOSE: Display interactive plan selection menu with checkboxes
#   INPUTS: { selected_idx: Int - currently highlighted item index }
#   OUTPUTS: { none - prints to stdout }
#   SIDE_EFFECTS: reads _PLAN_* arrays
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _show_plan_menu
_show_plan_menu() {
    local selected_idx="${1:-0}"
    local vis_count=${#_PLAN_VISIBLE[@]}
    local count=${#_PLAN_TITLES[@]}

    printf '\033[H'
    printf '\r\033[2K\n'
    local filter_label=""
    if [[ -n "$_PLAN_RISK_FILTER" ]]; then
        local fc
        fc=$(_risk_color "$_PLAN_RISK_FILTER")
        filter_label=" ${GRAY}[${fc}${_PLAN_RISK_FILTER}${NC} only]"
    fi
    echo -e "${PURPLE_BOLD}${ICON_ARROW} AI Recommendations — Select items to execute${NC}${filter_label}"
    printf '\r\033[2K\n'

    local start=$_PLAN_SCROLL_OFFSET
    local end=$((start + _PLAN_PAGE_SIZE))
    [[ $end -gt $vis_count ]] && end=$vis_count

    local v draw_line
    for ((v = start; v < end; v++)); do
        local i=${_PLAN_VISIBLE[$v]}
        local chk
        if [[ "${_PLAN_SELECTED[$i]}" == "1" ]]; then
            chk="${GREEN}[x]${NC}"
        else
            chk="${GRAY}[ ]${NC}"
        fi

        local risk_c
        risk_c=$(_risk_color "${_PLAN_RISKS[$i]}")

        local line_num=$((i + 1))
        local highlight=""
        local highlight_end=""
        if [[ $i -eq $selected_idx ]]; then
            highlight="${CYAN}"
            highlight_end="${NC}"
        fi

        printf '\r\033[2K  %s %s%s%-3s %-38s%s %s%-8s%s  %s\n' \
            "$chk" \
            "$highlight" "" "$line_num." "${_PLAN_TITLES[$i]}" "$highlight_end" \
            "$risk_c" "${_PLAN_RISKS[$i]}" "$NC" \
            "${_PLAN_SIZES[$i]}"
        printf '\r\033[2K        %s\n' "${GRAY}${_PLAN_REASONS[$i]}${NC}"
    done

    if [[ $vis_count -gt $_PLAN_PAGE_SIZE ]]; then
        local pct=$(( (end * 100) / vis_count ))
        printf '\r\033[2K  %sShowing %d-%d of %d (%d%%)%s\n' \
            "${GRAY}" "$((start + 1))" "$end" "$vis_count" "$pct" "${NC}"
    fi

    local sel_count=0
    local idx
    for ((idx = 0; idx < count; idx++)); do
        [[ "${_PLAN_SELECTED[$idx]}" == "1" ]] && sel_count=$((sel_count + 1))
    done

    printf '\r\033[2K\n'
    if [[ $sel_count -gt 0 ]]; then
        printf '\r\033[2K  %s\033[1m%d selected\033[0m%s  |  ↑↓ Navigate  |  Space Toggle  |  A Toggle All  |  F Filter  |  Enter Confirm  |  Esc Cancel\n' \
            "${GREEN}" "$sel_count" "${NC}"
    else
        printf '\r\033[2K  %s↑↓ Navigate  |  Space Toggle  |  A Toggle All  |  F Filter Risk  |  Enter Confirm  |  Esc Cancel%s\n' \
            "${GRAY}" "${NC}"
    fi
    printf '\033[J'
}

# START_CONTRACT: _interactive_select
#   PURPOSE: Interactive keyboard-driven plan selection loop
#   INPUTS: { none - reads _PLAN_* arrays }
#   OUTPUTS: { Int - 0 on confirm, 1 on cancel }
#   SIDE_EFFECTS: modifies _PLAN_SELECTED array, hides/shows cursor
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _interactive_select
_interactive_select() {
    local count=${#_PLAN_TITLES[@]}
    [[ $count -eq 0 ]] && return 1

    _update_visible_indices
    local vis_count=${#_PLAN_VISIBLE[@]}
    [[ $vis_count -eq 0 ]] && return 1

    local current=${_PLAN_VISIBLE[0]}
    local vis_idx=0
    hide_cursor

    while true; do
        vis_count=${#_PLAN_VISIBLE[@]}
        [[ $vis_count -eq 0 ]] && { show_cursor; return 1; }

        _show_plan_menu "$current"

        local key
        key=$(read_key) || continue

        case "$key" in
            UP)
                if [[ $vis_idx -gt 0 ]]; then
                    vis_idx=$((vis_idx - 1))
                    current=${_PLAN_VISIBLE[$vis_idx]}
                    if [[ $vis_idx -lt $_PLAN_SCROLL_OFFSET ]]; then
                        _PLAN_SCROLL_OFFSET=$((vis_idx))
                    fi
                fi
                ;;
            DOWN)
                if [[ $vis_idx -lt $((vis_count - 1)) ]]; then
                    vis_idx=$((vis_idx + 1))
                    current=${_PLAN_VISIBLE[$vis_idx]}
                    local page_end=$(( _PLAN_SCROLL_OFFSET + _PLAN_PAGE_SIZE ))
                    if [[ $vis_idx -ge $page_end ]]; then
                        _PLAN_SCROLL_OFFSET=$((vis_idx - _PLAN_PAGE_SIZE + 1))
                    fi
                fi
                ;;
            SPACE)
                if [[ "${_PLAN_SELECTED[$current]}" == "1" ]]; then
                    _PLAN_SELECTED[$current]=0
                else
                    _PLAN_SELECTED[$current]=1
                fi
                ;;
            "CHAR:a" | "CHAR:A")
                local any_selected=0 idx
                for ((idx = 0; idx < count; idx++)); do
                    [[ "${_PLAN_SELECTED[$idx]}" == "1" ]] && any_selected=1 && break
                done
                local new_val=1
                [[ $any_selected -eq 1 ]] && new_val=0
                for ((idx = 0; idx < count; idx++)); do
                    _PLAN_SELECTED[$idx]=$new_val
                done
                ;;
            "CHAR:f" | "CHAR:F")
                _cycle_risk_filter
                vis_idx=0
                vis_count=${#_PLAN_VISIBLE[@]}
                if [[ $vis_count -gt 0 ]]; then
                    current=${_PLAN_VISIBLE[0]}
                else
                    current=-1
                fi
                ;;
            ENTER)
                show_cursor
                return 0
                ;;
            QUIT)
                show_cursor
                return 1
                ;;
        esac

        drain_pending_input
    done
}

# START_CONTRACT: _show_confirmation
#   PURPOSE: Show final confirmation prompt before execution
#   INPUTS: { none - reads _PLAN_* arrays }
#   OUTPUTS: { Int - 0 on confirmed, 1 on cancelled }
#   SIDE_EFFECTS: clears screen, reads user input
#   LINKS: M-AI-RENDERER
# END_CONTRACT: _show_confirmation
_show_confirmation() {
    local count=${#_PLAN_TITLES[@]}
    local selected_count=0
    local i
    for ((i = 0; i < count; i++)); do
        [[ "${_PLAN_SELECTED[$i]}" == "1" ]] && selected_count=$((selected_count + 1))
    done

    [[ $selected_count -eq 0 ]] && return 1

    clear
    echo -e "${YELLOW}${ICON_CONFIRM} Confirm Execution${NC}"
    echo ""
    echo -e "  ${RED}\033[1mWARNING:${NC} ${RED}The following ${selected_count} actions will permanently delete data.${NC}"
    echo ""

    for ((i = 0; i < count; i++)); do
        [[ "${_PLAN_SELECTED[$i]}" != "1" ]] && continue
        local risk_c
        risk_c=$(_risk_color "${_PLAN_RISKS[$i]}")
        echo -e "  ${GREEN}[x]${NC} ${_PLAN_TITLES[$i]} ${risk_c}[${_PLAN_RISKS[$i]}]${NC} — ${_PLAN_SIZES[$i]}"
        local IFS_OLD="$IFS"
        IFS='|'
        read -ra paths_arr <<< "${_PLAN_PATHS[$i]}"
        IFS="$IFS_OLD"
        for p in "${paths_arr[@]}"; do
            echo -e "      ${GRAY}${ICON_SUBLIST} $p${NC}"
        done
    done

    echo ""
    echo -e "  ${YELLOW}This cannot be undone. Deleted files will NOT go to Trash.${NC}"
    echo ""
    echo -ne "  ${PURPLE}${ICON_ARROW}${NC} Type ${GREEN}yes${NC} to confirm, anything else to cancel: "

    local confirm
    IFS= read -r confirm || confirm=""
    drain_pending_input
    if [[ "$confirm" == "yes" || "$confirm" == "YES" || "$confirm" == "y" || "$confirm" == "Y" ]]; then
        return 0
    fi
    return 1
}
