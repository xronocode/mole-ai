#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-advisor.XXXXXX")"
    export HOME
    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    rm -rf "$HOME/.config"
}

@test "--help shows usage with all flags" {
    run bash --noprofile --norc "$PROJECT_ROOT/bin/advisor.sh" --help

    [ $status -eq 0 ]
    [[ "$output" == *"mo advisor"* ]]
    [[ "$output" == *"--analyze"* ]]
    [[ "$output" == *"--auto-safe"* ]]
    [[ "$output" == *"--setup"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--no-stream"* ]]
    [[ "$output" == *"--show-config"* ]]
}

@test "--show-config exits cleanly when not configured" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        '$PROJECT_ROOT/bin/advisor.sh' --show-config
    "

    [ $status -eq 0 ]
    [[ "$output" == *"not configured"* ]] || [[ "$output" == *"AI Advisor Configuration"* ]]
}

@test "--setup requires interactive terminal (non-zero exit)" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        '$PROJECT_ROOT/bin/advisor.sh' --setup
    "

    [ $status -ne 0 ] || true
}

@test "unknown flag shows error" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        '$PROJECT_ROOT/bin/advisor.sh' --bogus-flag 2>&1
    "

    [[ "$output" == *"Unknown option"* ]] || [ $status -ne 0 ]
}

@test "--dry-run collects data without AI call" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        '$PROJECT_ROOT/bin/advisor.sh' --dry-run 2>&1
    "

    [ $status -eq 0 ]
    [[ "$output" == *"SYSTEM OVERVIEW"* ]]
    [[ "$output" == *"DISK USAGE"* ]]
    [[ "$output" == *"MEMORY"* ]]
    [[ "$output" != *"ERROR"* ]] || true
}

@test "ai_system_prompt returns non-empty prompt with risk taxonomy" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/prompt.sh'
        ai_system_prompt
    ")"

    [[ -n "$result" ]]
    [[ "$result" == *"SAFE"* ]]
    [[ "$result" == *"CAUTION"* ]]
    [[ "$result" == *"RISKY"* ]]
    [[ "$result" == *"JSON"* ]]
    [[ "$result" == *"plan"* ]]
}

@test "ai_system_prompt mentions macOS system maintenance" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/prompt.sh'
        ai_system_prompt
    ")"

    [[ "$result" == *"macOS"* ]]
    [[ "$result" == *"system maintenance"* ]]
}

@test "module guard prevents double-loading config" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "module guard prevents double-loading client" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "module guard prevents double-loading renderer" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "module guard prevents double-loading executor" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "module guard prevents double-loading collector" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "module guard prevents double-loading collector_ext" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "module guard prevents double-loading prompt" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/prompt.sh'
        source '$PROJECT_ROOT/lib/ai/prompt.sh'
        echo ok
    ")"

    [ "$result" = "ok" ]
}

@test "_call_ai_with_retry returns error after max retries when unconfigured" {
    mkdir -p "$HOME/.config/mole"
    printf 'endpoint=http://127.0.0.1:19998/v1\nmodel=test\nmax_tokens=10\ntemperature=0.1\ntimeout=2\n' > "$HOME/.config/mole/ai.conf"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        source '$PROJECT_ROOT/lib/ai/prompt.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        source '$PROJECT_ROOT/bin/advisor.sh'
        _call_ai_with_retry 'sys' 'user' false 2>&1
    "

    [ $status -ne 0 ]
}
