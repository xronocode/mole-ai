#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-renderer.XXXXXX")"
    export HOME
    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "_risk_color returns correct color for each level" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        echo \"\$( _risk_color SAFE)|\$( _risk_color CAUTION)|\$( _risk_color RISKY)|\$( _risk_color OTHER)\"
    ")"
    local green safe yellow caution red risky nc other
    green=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$GREEN\"")
    yellow=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$YELLOW\"")
    red=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$RED\"")
    nc=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$NC\"")

    local IFS='|'
    read -ra colors <<< "$result"
    [ "${colors[0]}" = "$green" ]
    [ "${colors[1]}" = "$yellow" ]
    [ "${colors[2]}" = "$red" ]
    [ "${colors[3]}" = "$nc" ]
}

@test "_risk_icon returns correct icon for each level" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        echo \"\$( _risk_icon SAFE)|\$( _risk_icon CAUTION)|\$( _risk_icon RISKY)\"
    ")"
    local success warning error
    success=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$ICON_SUCCESS\"")
    warning=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$ICON_WARNING\"")
    error=$(HOME="$HOME" bash --noprofile --norc -c "source '$PROJECT_ROOT/lib/core/common.sh'; printf '%s' \"\$ICON_ERROR\"")

    local IFS='|'
    read -ra icons <<< "$result"
    [ "${icons[0]}" = "$success" ]
    [ "${icons[1]}" = "$warning" ]
    [ "${icons[2]}" = "$error" ]
}

@test "_extract_json_plan extracts JSON from markdown with code fence" {
    local response
    response=$(cat << 'ENDRESP'
Some text before
```json
{"plan": [{"title": "Clear cache", "reason": "test", "risk": "SAFE", "paths": ["/tmp/test"], "estimated_size": "100MB", "command": "custom"}]}
```
Some text after
ENDRESP
)

    result="$(echo "$response" | HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _extract_json_plan \"\$(cat)\"
    ")"

    echo "$result" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert 'plan' in data
assert len(data['plan']) == 1
assert data['plan'][0]['title'] == 'Clear cache'
"
}

@test "_extract_json_plan returns empty when no JSON block present" {
    local response='Just plain text without any JSON block here.'

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _extract_json_plan '$response'
    ")"

    [ -z "$result" ]
}

@test "_extract_json_plan extracts JSON via bracket matching fallback" {
    local response='Here is the plan: {"plan": [{"title": "Test", "reason": "r", "risk": "SAFE", "paths": [], "estimated_size": "0", "command": "custom"}]} end.'

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _extract_json_plan '$response'
    ")"

    echo "$result" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert 'plan' in data
" || return 1
}

@test "_parse_plan_items produces pipe-delimited lines" {
    local json='{"plan": [
        {"title": "Item A", "reason": "safe cleanup", "risk": "SAFE", "paths": ["/tmp/a", "/tmp/b"], "estimated_size": "1GB", "command": "custom"},
        {"title": "Item B", "reason": "be careful", "risk": "CAUTION", "paths": ["/tmp/c"], "estimated_size": "500MB", "command": "custom"}
    ]}'

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _parse_plan_items '$json'
    ")"

    local line1 line2
    line1=$(echo "$result" | head -1)
    line2=$(echo "$result" | sed -n '2p')

    [[ "$line1" == "1|Item A|safe cleanup|SAFE|/tmp/a|/tmp/b|1GB|custom" ]]
    [[ "$line2" == "2|Item B|be careful|CAUTION|/tmp/c|500MB|custom" ]]
}

@test "_load_plan populates arrays correctly" {
    local json='{"plan": [
        {"title": "Clear NPM", "reason": "regenerable", "risk": "SAFE", "paths": ["/home/.npm"], "estimated_size": "2GB", "command": "custom"}
    ]}'

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _load_plan '$json'
        echo \"titles=\${#_PLAN_TITLES[@]}\"
        echo \"title_0=\${_PLAN_TITLES[0]}\"
        echo \"risk_0=\${_PLAN_RISKS[0]}\"
        echo \"size_0=\${_PLAN_SIZES[0]}\"
        echo \"paths_0=\${_PLAN_PATHS[0]}\"
        echo \"selected_0=\${_PLAN_SELECTED[0]}\"
    ")"

    [[ "$result" == *"titles=1"* ]]
    [[ "$result" == *"title_0=Clear NPM"* ]]
    [[ "$result" == *"risk_0=SAFE"* ]]
    [[ "$result" == *"size_0=2GB"* ]]
    [[ "$result" == *"paths_0=/home/.npm"* ]]
    [[ "$result" == *"selected_0=0"* ]]
}

@test "_load_plan resets arrays on each call" {
    local json1='{"plan": [{"title": "A", "reason": "r", "risk": "SAFE", "paths": ["/a"], "estimated_size": "1", "command": "custom"}]}'
    local json2='{"plan": [{"title": "B", "reason": "r2", "risk": "RISKY", "paths": ["/b"], "estimated_size": "2", "command": "custom"}]}'

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _load_plan '$json1'
        _load_plan '$json2'
        echo \"count=\${#_PLAN_TITLES[@]}\"
        echo \"title=\${_PLAN_TITLES[0]}\"
    ")"

    [[ "$result" == *"count=1"* ]]
    [[ "$result" == *"title=B"* ]]
}

@test "_cycle_risk_filter cycles through SAFE CAUTION RISKY empty" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'

        _PLAN_TITLES=('A' 'B')
        _PLAN_RISKS=('SAFE' 'RISKY')
        _PLAN_SELECTED=(0 0)

        _cycle_risk_filter; echo \"\$_PLAN_RISK_FILTER\"
        _cycle_risk_filter; echo \"\$_PLAN_RISK_FILTER\"
        _cycle_risk_filter; echo \"\$_PLAN_RISK_FILTER\"
        _cycle_risk_filter; echo \"\$_PLAN_RISK_FILTER\"
    ")"

    local l1 l2 l3 l4
    l1=$(echo "$result" | sed -n '1p')
    l2=$(echo "$result" | sed -n '2p')
    l3=$(echo "$result" | sed -n '3p')
    l4=$(echo "$result" | sed -n '4p')
    [ "$l1" = "SAFE" ]
    [ "$l2" = "CAUTION" ]
    [ "$l3" = "RISKY" ]
    [ "$l4" = "" ]
}

@test "_update_visible_indices filters items by risk level" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'

        _PLAN_TITLES=('Safe item' 'Risky item' 'Caution item')
        _PLAN_RISKS=('SAFE' 'RISKY' 'CAUTION')
        _PLAN_SELECTED=(0 0 0)

        _PLAN_RISK_FILTER='SAFE'
        _update_visible_indices
        echo \"vis_count=\${#_PLAN_VISIBLE[@]}\"
        echo \"vis_0=\${_PLAN_VISIBLE[0]}\"
    ")"

    [[ "$result" == *"vis_count=1"* ]]
    [[ "$result" == *"vis_0=0"* ]]
}

@test "_update_visible_indices shows all items when filter is empty" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'

        _PLAN_TITLES=('A' 'B' 'C')
        _PLAN_RISKS=('SAFE' 'RISKY' 'CAUTION')
        _PLAN_SELECTED=(0 0 0)

        _PLAN_RISK_FILTER=''
        _update_visible_indices
        echo \"vis_count=\${#_PLAN_VISIBLE[@]}\"
    ")"

    [[ "$result" == *"vis_count=3"* ]]
}

@test "_render_report formats Disk Usage heading" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _render_report '## Disk Usage Summary'
    ")"
    [[ "$result" == *"Disk Usage Summary"* ]]
}

@test "_render_report formats Not Recommended heading" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _render_report '## Not Recommended for Deletion'
    ")"
    [[ "$result" == *"Not Recommended"* ]]
}

@test "_render_report formats table rows" {
    local md='| Path | Size | Category |
|------|------|----------|
| /tmp/cache | 1GB | Cache |'

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _render_report '$md'
    ")"

    [[ "$result" == *"/tmp/cache"* ]]
    [[ "$result" == *"1GB"* ]]
}

@test "_render_report formats list items" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _render_report '- **NPM cache** is safe to clean'
    ")"
    [[ "$result" == *"NPM cache"* ]]
}

@test "_render_report handles empty input" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        _render_report ''
    ")"
    [ -z "$result" ]
}
