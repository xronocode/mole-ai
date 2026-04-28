#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-config.XXXXXX")"
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

@test "ai_config_get returns default when config file missing" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_get endpoint 'http://fallback'
    ")"
    [ "$result" = "http://fallback" ]
}

@test "ai_config_get returns configured value" {
    mkdir -p "$HOME/.config/mole-ai"
    echo "endpoint=http://my-server:8080/v1" > "$HOME/.config/mole-ai/ai.conf"
    echo "model=my-model" >> "$HOME/.config/mole-ai/ai.conf"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_get endpoint
    ")"
    [ "$result" = "http://my-server:8080/v1" ]
}

@test "ai_config_is_configured returns true when endpoint and model set" {
    mkdir -p "$HOME/.config/mole-ai"
    printf 'endpoint=http://localhost:11434/v1\nmodel=qwen3:8b\n' > "$HOME/.config/mole-ai/ai.conf"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_is_configured && echo 'yes' || echo 'no'
    ")"
    [ "$result" = "yes" ]
}

@test "ai_config_is_configured returns true using defaults when config missing" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_is_configured
    "
    [ $status -eq 0 ]
}

@test "ai_config_set writes key to config file" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_set 'endpoint' 'http://test:1234/v1'
        ai_config_set 'model' 'test-model'
        cat \"\$MOLE_AI_CONFIG_FILE\"
    ")"

    echo "$result" | grep -q 'endpoint=http://test:1234/v1'
    echo "$result" | grep -q 'model=test-model'
}

@test "ai_config_set updates existing key" {
    mkdir -p "$HOME/.config/mole-ai"
    printf 'endpoint=http://old/v1\nmodel=old-model\n' > "$HOME/.config/mole-ai/ai.conf"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_set 'endpoint' 'http://new/v1'
        ai_config_get endpoint
    ")"
    [ "$result" = "http://new/v1" ]
}

@test "ai_config_get_endpoint returns default when not set" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_get_endpoint
    ")"
    [ "$result" = "http://localhost:11434/v1" ]
}

@test "ai_config_get_model returns default when not set" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_get_model
    ")"
    [ "$result" = "qwen3:8b" ]
}

@test "ai_config_get_api_key returns empty when not set" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_get_api_key
    ")"
    [ -z "$result" ]
}

@test "ai_config_show prints not configured when no file" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_show
    ")"
    [[ "$result" == *"not configured"* ]]
}

@test "ai_config_show prints config when file exists" {
    mkdir -p "$HOME/.config/mole-ai"
    printf 'endpoint=http://my/v1\nmodel=my-model\n' > "$HOME/.config/mole-ai/ai.conf"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_show
    ")"
    [[ "$result" == *"my-model"* ]]
    [[ "$result" == *"http://my/v1"* ]]
}

@test "api key is masked in show output" {
    mkdir -p "$HOME/.config/mole-ai"
    printf 'endpoint=http://my/v1\nmodel=m\napi_key=sk-1234567890abcdef\n' > "$HOME/.config/mole-ai/ai.conf"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        ai_config_show
    ")"
    [[ "$result" == *"sk-123456...cdef"* ]]
    [[ "$result" != *"sk-1234567890abcdef"* ]]
}
