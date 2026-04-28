#!/bin/bash
# Mole-AI - AI Advisor Command
# Analyzes system state using a connected LLM, presents interactive
# recommendations menu, and executes confirmed deletions via safe ops.

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/core/file_ops.sh"
source "$SCRIPT_DIR/lib/core/log.sh"
source "$SCRIPT_DIR/lib/ai/config.sh"
source "$SCRIPT_DIR/lib/ai/client.sh"
source "$SCRIPT_DIR/lib/ai/collector.sh"
source "$SCRIPT_DIR/lib/ai/prompt.sh"
source "$SCRIPT_DIR/lib/ai/renderer.sh"
source "$SCRIPT_DIR/lib/ai/executor.sh"

set +e

MOLE_CURRENT_COMMAND="advisor"
export MOLE_CURRENT_COMMAND

_ADVISOR_STEP_NUM=0

_step() {
    local label="$1"
    local detail="${2:-}"
    _ADVISOR_STEP_NUM=$((_ADVISOR_STEP_NUM + 1))
    printf '\r\033[2K'
    if [[ -n "$detail" ]]; then
        echo -e "  ${GRAY}${_ADVISOR_STEP_NUM}.${NC} ${CYAN}${label}${NC} ${GRAY}${detail}${NC}"
    else
        echo -e "  ${GRAY}${_ADVISOR_STEP_NUM}.${NC} ${CYAN}${label}${NC}"
    fi
}

_step_ok() {
    local label="$1"
    local detail="${2:-}"
    printf '\r\033[2K'
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} ${label} ${GRAY}${detail}${NC}"
}

_step_fail() {
    local label="$1"
    local detail="${2:-}"
    printf '\r\033[2K'
    echo -e "  ${RED}${ICON_ERROR}${NC} ${label} ${GRAY}${detail}${NC}"
}

cleanup_advisor() {
    stop_inline_spinner 2> /dev/null || true
    show_cursor 2> /dev/null || true
    cleanup_temp_files
}

handle_interrupt() {
    cleanup_advisor
    exit 130
}

trap cleanup_advisor EXIT
trap handle_interrupt INT TERM

_show_usage() {
    cat << EOF
${GREEN}Usage:${NC}
  ${CYAN}mo advisor${NC}              Open AI advisor menu (interactive)
  ${CYAN}mo advisor --analyze${NC}    Run analysis directly (skip menu)
  ${CYAN}mo advisor --setup${NC}      Configure AI endpoint and model
  ${CYAN}mo advisor --show-config${NC} Show current AI configuration
  ${CYAN}mo advisor --no-stream${NC}  Wait for full response (no streaming)
  ${CYAN}mo advisor --dry-run${NC}    Collect data only (no AI call)
  ${CYAN}mo advisor --auto-safe${NC}  Auto-select SAFE items, skip menu
  ${CYAN}mo advisor --help${NC}       Show this help message

${GREEN}Interactive menu:${NC}
  ${CYAN}Setup${NC}        — Configure AI endpoint (Ollama, vLLM, OpenRouter, etc.)
  ${CYAN}Analyze${NC}      — Collect system data, send to AI, get recommendations
  ${CYAN}Last Report${NC}  — View cached report from previous analysis

${GREEN}Workflow:${NC}
  1. AI analyzes your system
  2. Recommendations appear as an interactive list
  3. ${CYAN}Space${NC} to toggle items, ${CYAN}A${NC} to toggle all, ${CYAN}F${NC} to filter by risk
  4. ${CYAN}Enter${NC} to confirm, then type ${GREEN}yes${NC} to execute

${GREEN}Configuration:${NC}
  Settings are stored in ${GRAY}~/.config/mole-ai/ai.conf${NC}
  Reports cached in ${GRAY}~/.config/mole-ai/advisor/${NC}
EOF
}

_strip_reasoning() {
    local text="$1"
    echo "$text" | sed -n '/^##\|^\*\*\|^\| Path\|^\### Section\|^```json/,$p'
}

_call_ai_with_retry() {
    local sys_prompt="$1"
    local user_data="$2"
    local no_stream_flag="$3"
    local max_retries=2
    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        local resp_tmp
        resp_tmp=$(mktemp_file)
        local ai_exit=0

        if $no_stream_flag; then
            ai_client_chat "$sys_prompt" "$user_data" > "$resp_tmp" 2>&1
            ai_exit=$?
        else
            ai_client_stream_chat "$sys_prompt" "$user_data" > "$resp_tmp" 2>&1
            ai_exit=$?
        fi

        if [[ $ai_exit -eq 0 ]]; then
            cat "$resp_tmp"
            rm -f "$resp_tmp"
            return 0
        fi

        rm -f "$resp_tmp"

        if [[ $attempt -lt $max_retries ]]; then
            _step_fail "Attempt $attempt failed, retrying..." "(exit $ai_exit)"
            sleep 2
        fi
        attempt=$((attempt + 1))
    done

    return 1
}

_ADVISOR_CACHE_DIR="${MOLE_CONFIG_DIR:-$HOME/.config/mole-ai}/advisor"

_cache_report() {
    local report_md="$1"
    local json_block="$2"
    mkdir -p "$_ADVISOR_CACHE_DIR"
    echo "$report_md" > "$_ADVISOR_CACHE_DIR/last_report.md"
    echo "$json_block" > "$_ADVISOR_CACHE_DIR/last_plan.json"
    date '+%Y-%m-%d %H:%M' > "$_ADVISOR_CACHE_DIR/last_timestamp"
}

_has_cached_report() {
    [[ -f "$_ADVISOR_CACHE_DIR/last_report.md" && -f "$_ADVISOR_CACHE_DIR/last_plan.json" ]]
}

_get_cache_timestamp() {
    if [[ -f "$_ADVISOR_CACHE_DIR/last_timestamp" ]]; then
        cat "$_ADVISOR_CACHE_DIR/last_timestamp"
    else
        echo "unknown"
    fi
}

_show_advisor_submenu() {
    local selected=1
    local configured=false
    ai_config_is_configured 2> /dev/null && configured=true
    local has_cache=false
    _has_cached_report && has_cache=true

    hide_cursor
    trap 'show_cursor; return 1' INT TERM

    while true; do
        printf '\033[H'
        printf '\r\033[2K\n'
        echo -e "${PURPLE_BOLD}${ICON_ARROW} AI Advisor${NC}"
        printf '\r\033[2K\n'

        if $configured; then
            echo -e "  ${GRAY}Model:${NC} $(ai_config_get_model)"
            echo -e "  ${GRAY}Endpoint:${NC} $(ai_config_get_endpoint)"
        else
            echo -e "  ${YELLOW}${ICON_WARNING} Not configured — setup required first${NC}"
        fi

        if $has_cache; then
            echo -e "  ${GRAY}Last report:${NC} $(_get_cache_timestamp)"
        fi

        echo -e "  ${GRAY}Read-only analysis. You control all deletions.${NC}"

        printf '\r\033[2K\n'

        printf '\r\033[2K  %s\n' "$(show_menu_option 1 "Setup        Configure AI endpoint and model" "$([[ $selected -eq 1 ]] && echo true || echo false)")"
        if $configured; then
            printf '\r\033[2K  %s\n' "$(show_menu_option 2 "Analyze      Run AI system analysis" "$([[ $selected -eq 2 ]] && echo true || echo false)")"
        else
            printf '\r\033[2K  %s\n' "$(show_menu_option 2 "${GRAY}Analyze      (requires setup)${NC}" "$([[ $selected -eq 2 ]] && echo true || echo false)")"
        fi
        if $has_cache; then
            printf '\r\033[2K  %s\n' "$(show_menu_option 3 "Last Report  View recent analysis" "$([[ $selected -eq 3 ]] && echo true || echo false)")"
        else
            printf '\r\033[2K  %s\n' "$(show_menu_option 3 "${GRAY}Last Report  (no reports yet)${NC}" "$([[ $selected -eq 3 ]] && echo true || echo false)")"
        fi
        printf '\r\033[2K  %s\n' "$(show_menu_option 4 "Back         Return to main menu" "$([[ $selected -eq 4 ]] && echo true || echo false)")"

        printf '\r\033[2K\n'
        printf '\r\033[2K  %s↑↓ Navigate  |  Enter Select  |  Esc Back%s\n' "${GRAY}" "${NC}"
        printf '\033[J'

        local key
        key=$(read_key) || continue

        case "$key" in
            UP)
                ((selected > 1)) && ((selected--))
                ;;
            DOWN)
                ((selected < 4)) && ((selected++))
                ;;
            ENTER)
                show_cursor
                case $selected in
                    1)
                        clear
                        ai_config_setup
                        configured=false
                        ai_config_is_configured 2> /dev/null && configured=true
                        echo ""
                        echo -e "  ${GRAY}Press any key to continue...${NC}"
                        IFS= read -r -s -n1 -t 30 || true
                        ;;
                    2)
                        if $configured; then
                            clear
                            _run_analysis
                            _has_cached_report && has_cache=true
                            echo ""
                            echo -e "  ${GRAY}Press any key to continue...${NC}"
                            IFS= read -r -s -n1 -t 60 || true
                        fi
                        ;;
                    3)
                        if $has_cache; then
                            clear
                            _show_cached_report
                            echo ""
                            echo -e "  ${GRAY}Press any key to continue...${NC}"
                            IFS= read -r -s -n1 -t 60 || true
                        fi
                        ;;
                    4)
                        return 0
                        ;;
                esac
                hide_cursor
                ;;
            QUIT)
                show_cursor
                return 0
                ;;
        esac

        drain_pending_input
    done
}

_show_cached_report() {
    local report_md
    report_md=$(cat "$_ADVISOR_CACHE_DIR/last_report.md")
    local json_block
    json_block=$(cat "$_ADVISOR_CACHE_DIR/last_plan.json")
    local ts
    ts=$(_get_cache_timestamp)

    echo -e "${PURPLE_BOLD}${ICON_ARROW} Last Report${NC} ${GRAY}($ts)${NC}"
    echo ""
    _render_report "$report_md"
    echo ""

    if ! _load_plan "$json_block"; then
        echo -e "  ${YELLOW}${ICON_WARNING} Plan data could not be parsed.${NC}"
        return
    fi

    local count=${#_PLAN_TITLES[@]}
    if [[ $count -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS} No recommendations were made.${NC}"
        return
    fi

    echo -e "  ${PURPLE}${ICON_ARROW} Recommendations from last analysis:${NC}"
    echo ""
    local i
    for ((i = 0; i < count; i++)); do
        local risk_c
        risk_c=$(_risk_color "${_PLAN_RISKS[$i]}")
        echo -e "  ${ICON_LIST} ${_PLAN_TITLES[$i]} ${risk_c}[${_PLAN_RISKS[$i]}]${NC} — ${_PLAN_SIZES[$i]}"
    done
    echo ""
    echo -e "  ${GRAY}Run Analyze again for fresh recommendations with execution.${NC}"
}

_ADVISOR_TOTAL_SECTIONS=12
_ADVISOR_CURRENT_STAGE=""

_show_pipeline() {
    local active_stage="$1"
    local detail="${2:-}"

    if [[ -n "$_ADVISOR_CURRENT_STAGE" ]]; then
        printf '\r\033[2K\n' >&2
    fi

    local -a stages=("Collect" "Analyze" "Report" "Select" "Execute")
    local line=""
    local i active_idx

    active_idx=0
    for ((i = 0; i < ${#stages[@]}; i++)); do
        [[ "${stages[$i]}" == "$active_stage" ]] && active_idx=$i && break
    done

    for ((i = 0; i < ${#stages[@]}; i++)); do
        local s="${stages[$i]}"
        if [[ "$s" == "$active_stage" ]]; then
            line="${line}${CYAN}${ICON_SOLID} ${s}${NC}"
        elif [[ $i -lt $active_idx ]]; then
            line="${line}${GREEN}${ICON_SUCCESS}${NC}${GRAY} ${s}${NC}"
        else
            line="${line}${GRAY}${ICON_EMPTY} ${s}${NC}"
        fi
        [[ $i -lt $((${#stages[@]} - 1)) ]] && line="${line} ${GRAY}──${NC} "
    done

    printf '\r\033[2K  %s\n' "$line" >&2
    printf '\r\033[2K  %s' "$detail" >&2

    _ADVISOR_CURRENT_STAGE="$active_stage"
}

_pipeline_detail() {
    printf '\r\033[2K  %s' "$1" >&2
}

_pipeline_advance() {
    printf '\n' >&2
}

_stream_ai_with_progress() {
    local sys_prompt="$1"
    local user_data="$2"
    local resp_tmp="$3"

    local prompt_tmp="/tmp/mole_adv_prompt_$$.txt"
    local data_tmp="/tmp/mole_adv_data_$$.txt"
    printf '%s' "$sys_prompt" > "$prompt_tmp"
    printf '%s' "$user_data" > "$data_tmp"

    local attempt=1
    local max_retries=2

    while [[ $attempt -le $max_retries ]]; do
        rm -f "$resp_tmp"

        bash -c '
            SCRIPT_DIR="'"$SCRIPT_DIR"'"
            source "$SCRIPT_DIR/lib/core/common.sh" 2>/dev/null
            source "$SCRIPT_DIR/lib/ai/config.sh" 2>/dev/null
            source "$SCRIPT_DIR/lib/ai/client.sh" 2>/dev/null
            sys_prompt=$(cat "$1")
            user_data=$(cat "$2")
            ai_client_stream_chat "$sys_prompt" "$user_data"
        ' _ "$prompt_tmp" "$data_tmp" > "$resp_tmp" 2> /dev/null &
        local ai_pid=$!

        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local si=0

        while kill -0 "$ai_pid" 2> /dev/null; do
            local sc="${spinner_chars:$((si % 10)):1}"
            si=$((si + 1))

            local chars=0
            if [[ -f "$resp_tmp" ]]; then
                chars=$(wc -c < "$resp_tmp" 2> /dev/null | tr -d '[:space:]' || echo "0")
            fi

            if [[ "$chars" -gt 0 ]]; then
                local human_size
                if [[ "$chars" -gt 1048576 ]]; then
                    human_size="$((chars / 1048576))MB"
                elif [[ "$chars" -gt 1024 ]]; then
                    human_size="$((chars / 1024))KB"
                else
                    human_size="${chars}B"
                fi
                _pipeline_detail "${CYAN}${sc}${NC} Thinking... ${GRAY}${human_size}${NC}"
            else
                _pipeline_detail "${CYAN}${sc}${NC} Waiting for model response..."
            fi

            sleep 0.3
        done

        local ai_exit=0
        wait "$ai_pid" 2> /dev/null || ai_exit=$?

        local final_size=0
        if [[ -f "$resp_tmp" ]]; then
            final_size=$(wc -c < "$resp_tmp" 2> /dev/null | tr -d '[:space:]' || echo "0")
        fi

        if [[ $ai_exit -eq 0 && "$final_size" -gt 100 ]]; then
            _pipeline_detail "${GREEN}${ICON_SUCCESS}${NC} Response received (${final_size} bytes)"
            _pipeline_advance
            rm -f "$prompt_tmp" "$data_tmp"
            return 0
        fi

        if [[ $attempt -lt $max_retries ]]; then
            _pipeline_detail "${YELLOW}${ICON_WARNING}${NC} Attempt ${attempt} failed (exit=${ai_exit}, size=${final_size}), retrying..."
            sleep 2
        else
            _pipeline_detail "${RED}${ICON_ERROR}${NC} Failed after ${max_retries} attempts (exit=${ai_exit}, size=${final_size})"
            _pipeline_advance
        fi
        attempt=$((attempt + 1))
    done

    rm -f "$prompt_tmp" "$data_tmp"
    return 1
}

_collect_with_progress() {
    local data_tmp="/tmp/mole_advisor_data_$$.txt"
    local collect_log="/tmp/mole_advisor_collect_log_$$.txt"
    rm -f "$data_tmp"

    bash -c "source '$SCRIPT_DIR/lib/core/common.sh'; source '$SCRIPT_DIR/lib/ai/collector.sh'; collector_run_all" > "$data_tmp" 2> "$collect_log" &
    local collect_pid=$!

    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local si=0

    _show_pipeline "Collect" "${CYAN}⠋${NC} Starting scan..."

    while kill -0 "$collect_pid" 2> /dev/null; do
        local section_count=0
        if [[ -f "$data_tmp" ]]; then
            section_count=$(grep -c '^=== ' "$data_tmp" 2> /dev/null | tr -d '[:space:]' || echo "0")
            section_count="${section_count%%[!0-9]*}"
            [[ -z "$section_count" ]] && section_count=0
        fi

        local sc="${spinner_chars:$((si % 10)):1}"
        si=$((si + 1))

        local pct=$((section_count * 100 / _ADVISOR_TOTAL_SECTIONS))
        [[ $pct -gt 100 ]] && pct=100

        local bar=""
        local j
        for ((j = 0; j < section_count; j++)); do bar="${bar}${GREEN}${ICON_SOLID}${NC}"; done
        for ((j = section_count; j < _ADVISOR_TOTAL_SECTIONS; j++)); do bar="${bar}${GRAY}${ICON_EMPTY}${NC}"; done

        _pipeline_detail "${CYAN}${sc}${NC} Scanning... ${bar} ${section_count}/${_ADVISOR_TOTAL_SECTIONS} (${pct}%)"

        sleep 0.3
    done

    wait "$collect_pid" 2> /dev/null || true

    local section_count=0
    if [[ -f "$data_tmp" ]]; then
        section_count=$(grep -c '^=== ' "$data_tmp" 2> /dev/null | tr -d '[:space:]' || echo "0")
        section_count="${section_count%%[!0-9]*}"
        [[ -z "$section_count" ]] && section_count=0
    fi

    _pipeline_detail "${GREEN}${ICON_SUCCESS}${NC} Collected ${section_count} sections"
    _pipeline_advance
    cat "$data_tmp"
    rm -f "$data_tmp" "$collect_log"
}

_run_analysis() {
    if ! ai_config_is_configured; then
        echo -e "${YELLOW}${ICON_WARNING} AI advisor is not configured.${NC}"
        echo "Select Setup from the menu first."
        return 1
    fi

    clear

    echo -e "  ${PURPLE_BOLD}${ICON_ARROW} Mole-AI Advisor${NC}"
    echo -e "  ${GRAY}Read-only analysis. You decide what to delete.${NC}"
    echo ""
    echo -e "  ${GRAY}Model:${NC} $(ai_config_get_model)  ${GRAY}Endpoint:${NC} $(ai_config_get_endpoint)"
    echo ""

    system_data=$(_collect_with_progress)

    local sys_prompt
    sys_prompt=$(ai_system_prompt) || true

    _show_pipeline "Analyze" "${GRAY}Sending to model...${NC}"

    local resp_tmp="/tmp/mole_advisor_resp_$$.txt"
    if ! _stream_ai_with_progress "$sys_prompt" "$system_data" "$resp_tmp"; then
        echo ""
        echo -e "  ${RED}AI request failed. Check configuration via Setup.${NC}"
        rm -f "$resp_tmp"
        echo -e "  ${GRAY}Press any key to continue...${NC}"
        return 1
    fi

    local response
    response=$(cat "$resp_tmp")
    rm -f "$resp_tmp"

    _show_pipeline "Report" "${GRAY}Building report...${NC}"

    local json_block
    json_block=$(_extract_json_plan "$response")
    if [[ -z "$json_block" ]]; then
        _show_pipeline "Report" "${RED}${ICON_ERROR}${NC} No structured plan found"
        echo ""
        echo "$response"
        echo ""
        echo -e "  ${GRAY}Tip: try a different model via Setup.${NC}"
        return 1
    fi

    local report_md
    report_md=$(echo "$response" | sed '/^```json$/,$d' | sed '/^```$/d')
    report_md=$(_strip_reasoning "$report_md")
    _cache_report "$report_md" "$json_block"

    _show_pipeline "Report" "${GREEN}${ICON_SUCCESS}${NC} Report ready"
    _pipeline_advance

    sleep 0.5
    clear

    echo -e "${PURPLE_BOLD}${ICON_ARROW} System Report${NC}"
    echo ""
    _render_report "$report_md"
    echo ""

    if ! _load_plan "$json_block"; then
        echo -e "  ${RED}${ICON_ERROR} Parse error${NC}"
        return 1
    fi

    local count=${#_PLAN_TITLES[@]}
    if [[ $count -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS} System looks clean! No recommendations.${NC}"
        return 0
    fi

    echo -e "  ${GRAY}Press any key to select actions...${NC}"
    IFS= read -r -s -n1 -t 30 || true

    _show_pipeline "Select" ""
    sleep 0.3
    clear

    if ! _interactive_select; then
        echo ""
        echo -e "${GRAY}Cancelled.${NC}"
        return 0
    fi

    if ! _show_confirmation; then
        echo ""
        echo -e "${GRAY}Cancelled.${NC}"
        return 0
    fi

    _show_pipeline "Execute" ""
    sleep 0.3
    _execute_plan
}

main() {
    local do_setup=false
    local show_config=false
    local no_stream=false
    local dry_run=false
    local show_help=false
    local auto_safe=false
    local run_analyze=false

    for arg in "$@"; do
        case "$arg" in
            --setup) do_setup=true ;;
            --show-config) show_config=true ;;
            --no-stream) no_stream=true ;;
            --dry-run | -n) dry_run=true ;;
            --auto-safe) auto_safe=true ;;
            --analyze) run_analyze=true ;;
            --help | -h) show_help=true ;;
            *)
                echo "Unknown option: $arg"
                echo "Run: mo advisor --help"
                exit 1
                ;;
        esac
    done

    $show_help && _show_usage && exit 0
    $show_config && ai_config_show && exit 0
    $do_setup && ai_config_setup && exit 0

    if $run_analyze; then
        _run_analysis
        exit $?
    fi

    if $auto_safe || $dry_run; then
        if ! ai_config_is_configured; then
            echo -e "${YELLOW}${ICON_WARNING} AI advisor is not configured.${NC}"
            echo "Run: ${GREEN}mo advisor --setup${NC}"
            exit 1
        fi
    fi

    if $dry_run; then
        echo -e "${PURPLE_BOLD}${ICON_ARROW} Mole-AI Advisor — Dry Run${NC}"
        echo ""
        _step "Collecting system data..."
        local data_tmp="/tmp/mole_advisor_data_$$.txt"
        local collect_log="/tmp/mole_advisor_collect_log_$$.txt"
        bash -c "source '$SCRIPT_DIR/lib/core/common.sh'; source '$SCRIPT_DIR/lib/ai/collector.sh'; collector_run_all" > "$data_tmp" 2> "$collect_log" || true
        system_data=$(cat "$data_tmp")
        local section_count
        section_count=$(grep -c '^=== ' "$data_tmp" 2> /dev/null || echo "0")
        _step_ok "System data collected" "(${#system_data} bytes, ${section_count} sections)"
        rm -f "$data_tmp" "$collect_log"
        echo ""
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN — data that would be sent to AI:${NC}"
        echo ""
        echo "$system_data"
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS} Dry run complete, no AI request made.${NC}"
        exit 0
    fi

    if $auto_safe; then
        _run_analysis
        exit $?
    fi

    if [[ -t 0 && -t 1 ]]; then
        clear
        _show_advisor_submenu
        clear
        exit 0
    fi

    echo "Run: mo advisor --help"
    exit 1
}

(
    set +e
    main "$@"
)
