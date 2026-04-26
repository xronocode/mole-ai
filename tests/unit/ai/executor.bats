#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-executor.XXXXXX")"
    export HOME
    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "_expand_glob_paths expands directory/* to contained items" {
    local test_dir="$HOME/expand_test"
    mkdir -p "$test_dir"
    touch "$test_dir/file1.txt" "$test_dir/file2.txt"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _expand_glob_paths '$test_dir/*'
    ")"

    local count
    count=$(echo "$result" | wc -l | tr -d ' ')
    [ "$count" -ge 2 ]
    echo "$result" | grep -q "file1.txt"
    echo "$result" | grep -q "file2.txt"
}

@test "_expand_glob_paths returns exact path for non-glob" {
    mkdir -p "$HOME/single_test"
    touch "$HOME/single_test/item.dat"

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _expand_glob_paths '$HOME/single_test/item.dat'
    ")"

    [[ "$result" == *"item.dat"* ]]
}

@test "_expand_glob_paths returns nothing for non-existent glob" {
    local glob_target="$HOME/nonexistent_xyz_glob/*"
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        export TARGET='$glob_target'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _expand_glob_paths \"\$TARGET\"
    "

    [ -z "$output" ]
}

@test "_expand_glob_paths returns nothing for non-existent base directory" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _expand_glob_paths '/this/does/not/exist_xyz/*'
    "

    [ -z "$output" ]
}

@test "_execute_plan skips non-existent paths gracefully" {
    local ghost="/tmp/mole_test_ghost_$$_missing"
    local json="{\"plan\":[{\"title\":\"Ghost file\",\"reason\":\"does not exist\",\"risk\":\"SAFE\",\"paths\":[\"$ghost\"],\"estimated_size\":\"0\",\"command\":\"custom\"}]}"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _load_plan '$json'
        _PLAN_SELECTED[0]=1
        _execute_plan
    "

    [ $status -eq 0 ]
    [[ "$output" == *"Not found"* ]] || [[ "$output" == *"Executing Plan"* ]]
}

@test "_execute_plan skips unselected items" {
    mkdir -p "$HOME/exec_skip_test"
    echo "data" > "$HOME/exec_skip_test/keep_me.txt"

    local target="$HOME/exec_skip_test/keep_me.txt"
    local json="{\"plan\":[{\"title\":\"Should skip\",\"reason\":\"not selected\",\"risk\":\"SAFE\",\"paths\":[\"$target\"],\"estimated_size\":\"4B\",\"command\":\"custom\"}]}"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _load_plan '$json'
        _PLAN_SELECTED[0]=0
        _execute_plan
    "

    [ $status -eq 0 ]
    [ -f "$target" ]
}

@test "_execute_plan deletes selected single file" {
    mkdir -p "$HOME/exec_test"
    echo "temporary" > "$HOME/exec_test/temp_file.log"

    local target="$HOME/exec_test/temp_file.log"
    local json="{\"plan\":[{\"title\":\"Delete temp\",\"reason\":\"safe\",\"risk\":\"SAFE\",\"paths\":[\"$target\"],\"estimated_size\":\"10B\",\"command\":\"custom\"}]}"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _load_plan '$json'
        _PLAN_SELECTED[0]=1
        _execute_plan
    "

    [ $status -eq 0 ]
    [ ! -f "$target" ]
}

@test "_execute_plan clears directory contents with glob pattern" {
    mkdir -p "$HOME/exec_glob_test"
    echo "a" > "$HOME/exec_glob_test/a.tmp"
    echo "b" > "$HOME/exec_glob_test/b.tmp"

    local glob_path="$HOME/exec_glob_test/*"
    local json="{\"plan\":[{\"title\":\"Clear temp dir\",\"reason\":\"safe\",\"risk\":\"SAFE\",\"paths\":[\"$glob_path\"],\"estimated_size\":\"10B\",\"command\":\"custom\"}]}"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/core/file_ops.sh'
        source '$PROJECT_ROOT/lib/core/ui.sh'
        source '$PROJECT_ROOT/lib/ai/renderer.sh'
        source '$PROJECT_ROOT/lib/ai/executor.sh'
        _load_plan '$json'
        _PLAN_SELECTED[0]=1
        _execute_plan
    "

    [ $status -eq 0 ]
    [ -d "$HOME/exec_glob_test" ]
    [ ! -f "$HOME/exec_glob_test/a.tmp" ]
    [ ! -f "$HOME/exec_glob_test/b.tmp" ]
}
