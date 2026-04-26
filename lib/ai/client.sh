#!/bin/bash
# FILE: lib/ai/client.sh
# VERSION: 1.3.0
# START_MODULE_CONTRACT
#   PURPOSE: OpenAI-compatible HTTP client for chat completions API (standard + SSE streaming)
#   SCOPE: Chat completion requests, JSON escaping, response parsing with reasoning_content fallback
#   DEPENDS: lib/ai/config.sh
#   LINKS: M-AI-CLIENT
# END_MODULE_CONTRACT
#
# START_MODULE_MAP
#   ai_client_chat - standard (non-streaming) chat completion with reasoning_content fallback
#   ai_client_stream_chat - SSE streaming chat completion
#   ai_client_test - test endpoint connectivity
#   _build_messages_json - build JSON messages array from system + user prompts
#   _json_escape_string - escape string for JSON via python3 json.dumps() with bash fallback
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - Initial module. Basic curl-based OpenAI client.
#   v1.1.0 - Added reasoning_content fallback for reasoning models.
#   v1.2.0 - Added SSE streaming support.
#   v1.3.0 - Rewrote _json_escape_string to use python3 json.dumps() for full control char escaping.
# END_CHANGE_SUMMARY

set -euo pipefail

if [[ -n "${MOLE_AI_CLIENT_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_AI_CLIENT_LOADED=1

_MOLE_AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_AI_CONFIG_LOADED:-}" ]] && source "$_MOLE_AI_DIR/config.sh"

_json_escape_string() {
    printf '%s' "$1" | python3 -c '
import sys, json
sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])
' 2>/dev/null || {
        local str="$1"
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        str="${str//$'\t'/\\t}"
        str="${str//$'\n'/\\n}"
        str="${str//$'\r'/\\r}"
        local i char code
        local result=""
        for ((i = 0; i < ${#str}; i++)); do
            char="${str:$i:1}"
            printf -v code '%d' "'$char"
            if [[ $code -lt 32 && $code -ne 9 && $code -ne 10 && $code -ne 13 ]]; then
                result+="\\u$(printf '%04x' $code)"
            else
                result+="$char"
            fi
        done
        printf '%s' "$result"
    }
}

_build_messages_json() {
    local system_prompt="$1"
    local user_message="$2"
    local escaped_system escaped_user
    escaped_system=$(_json_escape_string "$system_prompt")
    escaped_user=$(_json_escape_string "$user_message")
    printf '[{"role":"system","content":"%s"},{"role":"user","content":"%s"}]' "$escaped_system" "$escaped_user"
}

ai_client_chat() {
    set +e
    local system_prompt="$1"
    local user_message="$2"

    local endpoint model api_key max_tokens temperature timeout
    endpoint=$(ai_config_get_endpoint)
    model=$(ai_config_get_model)
    api_key=$(ai_config_get_api_key)
    max_tokens=$(ai_config_get_max_tokens)
    temperature=$(ai_config_get_temperature)
    timeout=$(ai_config_get_timeout)

    local url="${endpoint%/}/chat/completions"
    local messages
    messages=$(_build_messages_json "$system_prompt" "$user_message")

    local -a curl_args=(
        -sS
        --connect-timeout 10
        --max-time "$timeout"
        -H "Content-Type: application/json"
    )

    if [[ -n "$api_key" ]]; then
        curl_args+=(-H "Authorization: Bearer $api_key")
    fi

    local request_body
    request_body=$(cat <<EOF
{
  "model": "$(_json_escape_string "$model")",
  "messages": $messages,
  "max_tokens": $max_tokens,
  "temperature": $temperature
}
EOF
)

    curl_args+=(-d "$request_body")
    curl_args+=("$url")

    local response http_code
    response=$(curl -sS -w "\n%{http_code}" "${curl_args[@]}" 2>&1) || {
        echo "ERROR: Failed to connect to $url" >&2
        return 1
    }

    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        echo "ERROR: API returned HTTP $http_code" >&2
        echo "$body" | head -5 >&2
        [[ "$http_code" == "401" ]] && echo "HINT: Check your API key (mo advisor --setup)" >&2
        [[ "$http_code" == "404" ]] && echo "HINT: Model '$model' may not be available at this endpoint" >&2
        return 1
    fi

    local content
    content=$(echo "$body" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msg = data['choices'][0]['message']
    content = msg.get('content', '')
    reasoning = msg.get('reasoning_content', '')
    if content:
        print(content)
    elif reasoning:
        print(reasoning)
except Exception:
    pass
" 2>/dev/null || true)

    if [[ -z "$content" ]]; then
        echo "ERROR: Empty response from model" >&2
        return 1
    fi

    echo "$content"
}

ai_client_stream_chat() {
    set +e
    local system_prompt="$1"
    local user_message="$2"

    local endpoint model api_key max_tokens temperature timeout
    endpoint=$(ai_config_get_endpoint)
    model=$(ai_config_get_model)
    api_key=$(ai_config_get_api_key)
    max_tokens=$(ai_config_get_max_tokens)
    temperature=$(ai_config_get_temperature)
    timeout=$(ai_config_get_timeout)

    local url="${endpoint%/}/chat/completions"
    local messages
    messages=$(_build_messages_json "$system_prompt" "$user_message")

    local -a curl_args=(
        -sS
        --connect-timeout 10
        --max-time "$timeout"
        -H "Content-Type: application/json"
        -N
    )

    if [[ -n "$api_key" ]]; then
        curl_args+=(-H "Authorization: Bearer $api_key")
    fi

    local request_body
    request_body=$(cat <<EOF
{
  "model": "$(_json_escape_string "$model")",
  "messages": $messages,
  "max_tokens": $max_tokens,
  "temperature": $temperature,
  "stream": true
}
EOF
    )

    curl_args+=(-d "$request_body")
    curl_args+=("$url")

    local stream_tmp="/tmp/_mole_stream_reason_$$_${RANDOM}"
    curl "${curl_args[@]}" 2>/dev/null | python3 -u -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if line.startswith('data: '):
        data = line[6:]
        if data == '[DONE]':
            break
        try:
            obj = json.loads(data)
            delta = obj['choices'][0].get('delta', {})
            content = delta.get('content', '')
            reasoning = delta.get('reasoning_content', '')
            if content:
                sys.stdout.write(content)
                sys.stdout.flush()
            elif reasoning:
                sys.stdout.write(reasoning)
                sys.stdout.flush()
        except (json.JSONDecodeError, KeyError, IndexError):
            pass
" 2>/dev/null || {
        echo "ERROR: Stream connection failed" >&2
        return 1
    }
    echo
}

ai_client_test() {
    local endpoint model api_key
    endpoint=$(ai_config_get_endpoint)
    model=$(ai_config_get_model)
    api_key=$(ai_config_get_api_key)

    local url="${endpoint%/}/models"
    local -a curl_args=(
        -sS
        --connect-timeout 5
        --max-time 10
    )

    if [[ -n "$api_key" ]]; then
        curl_args+=(-H "Authorization: Bearer $api_key")
    fi
    curl_args+=("$url")

    local response
    response=$(curl "${curl_args[@]}" 2>/dev/null) && return 0

    url="${endpoint%/}/chat/completions"
    local test_body='{"model":"'"$(_json_escape_string "$model")"'","messages":[{"role":"user","content":"hi"}],"max_tokens":5}'
    curl_args+=(-H "Content-Type: application/json" -d "$test_body")
    response=$(curl -sS --connect-timeout 5 --max-time 15 "${curl_args[@]}" 2>/dev/null) && return 0

    return 1
}
