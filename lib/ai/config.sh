#!/bin/bash
# FILE: lib/ai/config.sh
# VERSION: 1.0.0
# START_MODULE_CONTRACT
#   PURPOSE: Manage AI advisor configuration stored in ~/.config/mole/ai.conf
#   SCOPE: Read/write config values, interactive setup wizard, display config
#   DEPENDS: lib/core/base.sh
#   LINKS: M-AI-CONFIG
# END_MODULE_CONTRACT
#
# START_MODULE_MAP
#   ai_config_get - read config value by key with optional default
#   ai_config_set - write config value to file
#   ai_config_setup - interactive setup wizard for endpoint/model/api_key
#   ai_config_show - display current config (masks API key)
#   ai_config_is_configured - check if endpoint and model are set
#   ai_config_get_endpoint - get API endpoint URL
#   ai_config_get_model - get model name
#   ai_config_get_api_key - get API key
#   ai_config_get_max_tokens - get max_tokens parameter
#   ai_config_get_temperature - get temperature parameter
#   ai_config_get_timeout - get request timeout in seconds
# END_MODULE_MAP
#
# START_CHANGE_SUMMARY
#   v1.0.0 - Initial module. Config management for AI advisor endpoint/model/api_key.
# END_CHANGE_SUMMARY

set -euo pipefail

if [[ -n "${MOLE_AI_CONFIG_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_AI_CONFIG_LOADED=1

_MOLE_AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${MOLE_BASE_LOADED:-}" ]] && source "$_MOLE_AI_DIR/../core/base.sh"

readonly MOLE_AI_CONFIG_FILE="${MOLE_CONFIG_DIR:-$HOME/.config/mole}/ai.conf"

readonly MOLE_AI_DEFAULT_ENDPOINT="http://localhost:11434/v1"
readonly MOLE_AI_DEFAULT_MODEL="qwen3:8b"
readonly MOLE_AI_DEFAULT_MAX_TOKENS=16384
readonly MOLE_AI_DEFAULT_TEMPERATURE=0.3
readonly MOLE_AI_DEFAULT_TIMEOUT=300

_ai_config_get_raw() {
    local key="$1"
    if [[ ! -f "$MOLE_AI_CONFIG_FILE" ]]; then
        return 1
    fi
    local value
    value=$(grep -E "^${key}=" "$MOLE_AI_CONFIG_FILE" 2> /dev/null | head -1 | sed "s/^${key}=//" || true)
    [[ -n "$value" ]] && echo "$value" && return 0
    return 1
}

ai_config_get() {
    local key="$1"
    local default="${2:-}"
    local value
    value=$(_ai_config_get_raw "$key") || true
    echo "${value:-$default}"
}

ai_config_set() {
    local key="$1"
    local value="$2"
    ensure_user_dir "$(dirname "$MOLE_AI_CONFIG_FILE")"
    ensure_user_file "$MOLE_AI_CONFIG_FILE"
    if _ai_config_get_raw "$key" > /dev/null 2>&1; then
        local tmp
        tmp=$(mktemp_file)
        sed "s|^${key}=.*|${key}=${value}|" "$MOLE_AI_CONFIG_FILE" > "$tmp" || true
        cat "$tmp" > "$MOLE_AI_CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$MOLE_AI_CONFIG_FILE"
    fi
}

ai_config_get_endpoint() { ai_config_get "endpoint" "$MOLE_AI_DEFAULT_ENDPOINT"; }
ai_config_get_model() { ai_config_get "model" "$MOLE_AI_DEFAULT_MODEL"; }
ai_config_get_api_key() { ai_config_get "api_key" ""; }
ai_config_get_max_tokens() { ai_config_get "max_tokens" "$MOLE_AI_DEFAULT_MAX_TOKENS"; }
ai_config_get_temperature() { ai_config_get "temperature" "$MOLE_AI_DEFAULT_TEMPERATURE"; }
ai_config_get_timeout() { ai_config_get "timeout" "$MOLE_AI_DEFAULT_TIMEOUT"; }

ai_config_is_configured() {
    local endpoint model
    endpoint=$(ai_config_get_endpoint)
    model=$(ai_config_get_model)
    [[ -n "$endpoint" && -n "$model" ]]
}

ai_config_show() {
    if [[ ! -f "$MOLE_AI_CONFIG_FILE" ]]; then
        echo -e "${YELLOW}AI advisor is not configured yet.${NC}"
        echo ""
        echo "Run: ${GREEN}mo advisor --setup${NC}"
        return 0
    fi
    echo -e "${PURPLE_BOLD}AI Advisor Configuration${NC}"
    echo ""
    echo -e "  ${ICON_LIST} Endpoint:    ${CYAN}$(ai_config_get_endpoint)${NC}"
    echo -e "  ${ICON_LIST} Model:       ${CYAN}$(ai_config_get_model)${NC}"
    local api_key
    api_key=$(ai_config_get_api_key)
    if [[ -n "$api_key" ]]; then
        local masked="${api_key:0:8}...${api_key: -4}"
        echo -e "  ${ICON_LIST} API Key:     ${CYAN}${masked}${NC}"
    else
        echo -e "  ${ICON_LIST} API Key:     ${GRAY}(none)${NC}"
    fi
    echo -e "  ${ICON_LIST} Max Tokens:  ${CYAN}$(ai_config_get_max_tokens)${NC}"
    echo -e "  ${ICON_LIST} Temperature: ${CYAN}$(ai_config_get_temperature)${NC}"
    echo -e "  ${ICON_LIST} Timeout:     ${CYAN}$(ai_config_get_timeout)s${NC}"
    echo ""
    echo -e "  Config file: ${GRAY}${MOLE_AI_CONFIG_FILE}${NC}"
}

ai_config_setup() {
    clear
    echo -e "${PURPLE_BOLD}${ICON_ARROW} AI Advisor Setup${NC}"
    echo ""
    echo "Configure an OpenAI-compatible API endpoint."
    echo "Works with Ollama, vLLM, LM Studio, OpenRouter, or any OpenAI-compatible server."
    echo ""

    local current_endpoint current_model current_key
    current_endpoint=$(ai_config_get_endpoint)
    current_model=$(ai_config_get_model)
    current_key=$(ai_config_get_api_key)

    echo -ne "  API Endpoint [${GREEN}${current_endpoint}${NC}]: "
    local endpoint
    IFS= read -r endpoint || endpoint=""
    endpoint="${endpoint:-$current_endpoint}"
    [[ -z "$endpoint" ]] && endpoint="$MOLE_AI_DEFAULT_ENDPOINT"

    echo -ne "  Model name [${GREEN}${current_model}${NC}]: "
    local model
    IFS= read -r model || model=""
    model="${model:-$current_model}"
    [[ -z "$model" ]] && model="$MOLE_AI_DEFAULT_MODEL"

    local key_prompt="(leave empty if not required)"
    [[ -n "$current_key" ]] && key_prompt="(current: set)"
    echo -ne "  API Key ${key_prompt}: "
    local api_key
    IFS= read -r api_key || api_key=""
    [[ -z "$api_key" ]] && api_key="$current_key"

    ai_config_set "endpoint" "$endpoint"
    ai_config_set "model" "$model"
    [[ -n "$api_key" ]] && ai_config_set "api_key" "$api_key"

    echo ""
    echo -e "${GREEN}${ICON_SUCCESS} Configuration saved.${NC}"
    echo ""
    echo "Testing connection..."
    if ai_client_test; then
        echo -e "${GREEN}${ICON_SUCCESS} Connection successful!${NC}"
    else
        echo -e "${YELLOW}${ICON_WARNING} Could not reach the endpoint. Check settings and try again.${NC}"
        echo "  Run: ${GREEN}mo advisor --setup${NC}"
    fi
}
