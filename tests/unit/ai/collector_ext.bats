#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-collector-ext.XXXXXX")"
    export HOME
    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "_collect_docker_info reports not installed when docker absent" {
    result="$(HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        _collect_docker_info
    ")"

    [[ "$result" == *"not installed"* ]]
}

@test "_collect_docker_info reports not running when docker installed but not running" {
    local fake_bin="$HOME/fake_docker_bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/docker" << 'SCRIPT'
#!/bin/bash
if [[ "$*" == "info" ]]; then
    exit 1
fi
SCRIPT
    chmod +x "$fake_bin/docker"

    result="$(HOME="$HOME" PATH="$fake_bin:$PATH" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        _collect_docker_info
    ")"

    [[ "$result" == *"not running"* ]]
    rm -rf "$fake_bin"
}

@test "_collect_homebrew_info reports cellar breakdown when brew present" {
    local fake_bin="$HOME/fake_brew_bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/brew" << 'SCRIPT'
#!/bin/bash
case "$1" in
    --prefix) echo "$HOME/fake_homebrew" ;;
    --cache) echo "$HOME/fake_cache_homebrew" ;;
    outdated) echo "" ;;
    *) echo "" ;;
esac
SCRIPT
    chmod +x "$fake_bin/brew"

    mkdir -p "$HOME/fake_homebrew/Cellar/pkg1/1.0"
    echo "data" > "$HOME/fake_homebrew/Cellar/pkg1/1.0/file.txt"
    mkdir -p "$HOME/fake_cache_homebrew"
    echo "c" > "$HOME/fake_cache_homebrew/cache.tar.gz"

    result="$(HOME="$HOME" PATH="$fake_bin:$PATH" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        _collect_homebrew_info
    ")"

    [[ "$result" == *"Homebrew cache:"* ]]
    [[ "$result" == *"Homebrew Cellar"* ]]
    rm -rf "$fake_bin" "$HOME/fake_homebrew" "$HOME/fake_cache_homebrew"
}

@test "_collect_homebrew_info reports not installed when brew absent" {
    result="$(HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        _collect_homebrew_info
    ")"

    [[ "$result" == *"not installed"* ]]
}

@test "_collect_xcode_info reports no Developer directory when absent" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        _collect_xcode_info
    ")"

    [[ "$result" == *"no Developer directory"* ]]
}

@test "_collect_xcode_info reports simulator list when Developer exists" {
    mkdir -p "$HOME/Library/Developer/Xcode/UserData"
    mkdir -p "$HOME/Library/Developer/CoreSimulator"
    mkdir -p "$HOME/Library/Developer/Xcode/Archives"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        _collect_xcode_info
    ")"

    [[ "$result" == *"Xcode Developer data"* ]]
    [[ "$result" == *"CoreSimulator"* ]]
    [[ "$result" == *"iOS Simulators"* ]]
    [[ "$result" == *"Xcode Archives"* ]]
}

@test "collector_ext_run_all outputs DOCKER section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        collector_ext_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== DOCKER ==="* ]]
}

@test "collector_ext_run_all outputs HOMEBREW section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        collector_ext_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== HOMEBREW ==="* ]]
}

@test "collector_ext_run_all outputs XCODE section" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/collector.sh'
        source '$PROJECT_ROOT/lib/ai/collector_ext.sh'
        collector_ext_run_all 2>/dev/null
    ")"
    [[ "$result" == *"=== XCODE ==="* ]]
}
