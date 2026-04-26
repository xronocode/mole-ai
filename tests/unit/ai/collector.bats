#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-collector.XXXXXX")"
    export HOME
    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "collector_run_all outputs SYSTEM OVERVIEW section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== SYSTEM OVERVIEW ==="* ]]
}

@test "collector_run_all outputs DISK USAGE section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== DISK USAGE ==="* ]]
}

@test "collector_run_all outputs MEMORY section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== MEMORY ==="* ]]
}

@test "collector_run_all outputs CPU section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== CPU ==="* ]]
}

@test "collector_run_all outputs TRASH section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== TRASH ==="* ]]
}

@test "collector_run_all outputs CLEANABLE ITEMS section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== CLEANABLE ITEMS ==="* ]]
}

@test "collector_run_all outputs INSTALLER FILES section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== INSTALLER FILES ==="* ]]
}

@test "collector_run_all outputs NETWORK section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== NETWORK ==="* ]]
}

@test "collector_run_all outputs BATTERY section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== BATTERY ==="* ]]
}

@test "collector_run_all outputs DOCKER section via ext" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== DOCKER ==="* ]]
}

@test "collector_run_all outputs HOMEBREW section via ext" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== HOMEBREW ==="* ]]
}

@test "collector_run_all outputs XCODE section via ext" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        collector_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== XCODE ==="* ]]
}

@test "_fast_du_sk returns numeric value for known directory" {
    mkdir -p "$HOME/du_test"
    echo "content" > "$HOME/du_test/file.txt"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _fast_du_sk '$HOME/du_test'
    ")"

    [[ "$result" =~ ^[0-9]+$ ]]
    [ "$result" -gt 0 ]
}

@test "_fast_du_sk returns 0 for non-existent directory" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _fast_du_sk '/nonexistent_dir_xyz_$$'
    ")"

    [ "$result" = "0" ]
}

@test "_fast_du_sk_bg returns empty string on timeout" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _fast_du_sk_bg '/Applications' 0
    " 2>/dev/null || true)"

    [ -z "$result" ]
}

@test "_fast_du_sk_bg returns numeric value for quick directory" {
    mkdir -p "$HOME/du_bg_test"
    echo "data" > "$HOME/du_bg_test/f.txt"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _fast_du_sk_bg '$HOME/du_bg_test' 5
    ")"

    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "_collect_section outputs section header and content" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _collect_section 'TEST SECTION' echo 'hello world'
    ")"

    [[ "$result" == *"=== TEST SECTION ==="* ]]
    [[ "$result" == *"hello world"* ]]
}

@test "_collect_trash outputs trash info" {
    mkdir -p "$HOME/.Trash"
    echo "trash" > "$HOME/.Trash/old_file.txt"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _collect_trash
    ")"

    [[ "$result" == *"Trash:"* ]]
}

@test "_collect_memory_info outputs memory data" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _collect_memory_info
    ")"

    [[ "$result" == *"Total:"* ]]
    [[ "$result" == *"Swap used:"* ]]
}

@test "_collect_cpu_info outputs CPU data" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _collect_cpu_info
    ")"

    [[ "$result" == *"Cores:"* ]]
    [[ "$result" == *"Load averages:"* ]]
}

@test "_collect_uptime_info outputs uptime and macOS version" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        _collect_uptime_info
    ")"

    [[ "$result" == *"Uptime:"* ]]
    [[ "$result" == *"macOS:"* ]]
}
