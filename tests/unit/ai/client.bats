#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-client.XXXXXX")"
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
    mkdir -p "$HOME/.config/mole"
}

_mock_api_server() {
    local port="$1"
    local response_file="$2"
    local pid_file="$HOME/mock_api_$$.pid"

    while IFS= read -r line; do
        if [[ "$line" == GET* ]]; then
            break
        fi
    done | {
        sleep 0.1
        cat "$response_file"
    } &>/dev/null &
    echo $! > "$pid_file"
}

_start_mock_httpd() {
    local port="$1"
    local response_body="$2"
    local http_code="${3:-200}"

    local response_file="$HOME/mock_response_$$.txt"
    local body_len=${#response_body}
    cat > "$response_file" <<HTTP
HTTP/1.1 $http_code OK
Content-Type: application/json
Content-Length: $body_len

$response_body
HTTP

    socat TCP-LISTEN:$port,fork,reuseaddr EXEC:"cat $response_file" &>/dev/null &
    echo $!
}

@test "_build_messages_json produces valid JSON array" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        _build_messages_json 'You are helpful' 'Hello world'
    ")"

    echo "$result" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert len(data) == 2
assert data[0]['role'] == 'system'
assert data[1]['role'] == 'user'
assert data[0]['content'] == 'You are helpful'
assert data[1]['content'] == 'Hello world'
" || return 1
}

@test "_build_messages_json escapes quotes and newlines" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        _build_messages_json 'line1\nline2' 'say \"hello\"'
    ")"

    echo "$result" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert 'line1' in data[0]['content']
assert 'hello' in data[1]['content']
" || return 1
}

@test "_json_escape_string escapes backslashes" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        _json_escape_string 'path\to\file'
    ")"
    [[ "$result" == *'path\\to\\file'* ]]
}

@test "_json_escape_string escapes control characters" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        _json_escape_string $'hello\x1b[31mworld\ttab'
    ")"
    [[ "$result" == *'\u001b'* ]]
    [[ "$result" == *'\\t'* || "$result" == *'\t'* ]]
}

@test "_json_escape_string produces valid JSON via python3" {
    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        _json_escape_string $'line1\nline2\x1b[0m\"quoted\"'
    ")"
    echo "\"$result\"" | python3 -c "import sys,json; json.loads(sys.stdin.read())"
}

@test "ai_client_chat returns content from mocked 200 response" {
    local port=19876
    printf 'endpoint=http://127.0.0.1:%d/v1\nmodel=test-model\nmax_tokens=100\ntemperature=0.1\ntimeout=5\n' "$port" > "$HOME/.config/mole/ai.conf"

    python3 -c "
import http.server, json, threading, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        self.rfile.read(length)
        body = json.dumps({'id':'test','choices':[{'message':{'content':'Clean your caches'}}]})
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, *a): pass

srv = http.server.HTTPServer(('127.0.0.1', $port), Handler)
t = threading.Thread(target=srv.serve_forever); t.daemon=True; t.start()
import time; time.sleep(30)
" &
    local mock_pid=$!
    sleep 0.5

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        ai_client_chat 'system prompt' 'user data'
    ")"
    local rc=$?

    kill "$mock_pid" 2>/dev/null || true
    wait "$mock_pid" 2>/dev/null || true

    [ $rc -eq 0 ]
    [[ "$result" == *"Clean your caches"* ]]
}

@test "ai_client_chat falls back to reasoning_content when content is empty" {
    local port=19877
    printf 'endpoint=http://127.0.0.1:%d/v1\nmodel=test-model\nmax_tokens=100\ntemperature=0.1\ntimeout=5\n' "$port" > "$HOME/.config/mole/ai.conf"

    python3 -c "
import http.server, json, threading

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        self.rfile.read(length)
        body = json.dumps({'id':'test','choices':[{'message':{'content':'','reasoning_content':'Reasoned analysis here'}}]})
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, *a): pass

srv = http.server.HTTPServer(('127.0.0.1', $port), Handler)
t = threading.Thread(target=srv.serve_forever); t.daemon=True; t.start()
import time; time.sleep(30)
" &
    local mock_pid=$!
    sleep 0.5

    result="$(HOME="$HOME" bash --noprofile --norc -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        ai_client_chat 'system prompt' 'user data'
    ")"
    local rc=$?

    kill "$mock_pid" 2>/dev/null || true
    wait "$mock_pid" 2>/dev/null || true

    [ $rc -eq 0 ]
    [[ "$result" == *"Reasoned analysis here"* ]]
}

@test "ai_client_chat returns error on HTTP 401" {
    local port=19878
    printf 'endpoint=http://127.0.0.1:%d/v1\nmodel=test-model\napi_key=bad-key\nmax_tokens=100\ntemperature=0.1\ntimeout=5\n' "$port" > "$HOME/.config/mole/ai.conf"

    python3 -c "
import http.server, json, threading

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(401)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"error\":\"unauthorized\"}')
    def log_message(self, *a): pass

srv = http.server.HTTPServer(('127.0.0.1', $port), Handler)
t = threading.Thread(target=srv.serve_forever); t.daemon=True; t.start()
import time; time.sleep(30)
" &
    local mock_pid=$!
    sleep 0.5

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        ai_client_chat 'sys' 'user' 2>&1
    "

    kill "$mock_pid" 2>/dev/null || true
    wait "$mock_pid" 2>/dev/null || true

    [ $status -ne 0 ]
    [[ "$output" == *"401"* ]]
}

@test "ai_client_chat returns error on connection refused" {
    printf 'endpoint=http://127.0.0.1:19999/v1\nmodel=test\nmax_tokens=10\ntemperature=0.1\ntimeout=2\n' > "$HOME/.config/mole/ai.conf"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        ai_client_chat 'sys' 'user' 2>&1
    "

    [ $status -ne 0 ]
}

@test "ai_client_stream_chat returns error on connection refused" {
    printf 'endpoint=http://127.0.0.1:19999/v1\nmodel=test\nmax_tokens=10\ntemperature=0.1\ntimeout=2\n' > "$HOME/.config/mole/ai.conf"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/ai/config.sh'
        source '$PROJECT_ROOT/lib/ai/client.sh'
        ai_client_stream_chat 'sys' 'user' 2>&1
    "

    [ $status -ne 0 ]
}
