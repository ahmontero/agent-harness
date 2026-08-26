#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/ai-client.sh
# Local AI & OpenAI-Compatible LLM Client Fallback (Ollama / LocalAI / vLLM)
# ==============================================================================

set -eo pipefail

ai_is_enabled() {
    local enabled
    enabled="$(get_profile_value "localAI.enabled" "false")"
    [ "${enabled}" = "true" ]
}

ai_complete() {
    local system_prompt="$1"
    local user_prompt="$2"

    if ! ai_is_enabled; then
        return 1
    fi

    local base_url
    base_url="$(get_profile_value "localAI.baseUrl" "http://localhost:11434/v1")"
    local model
    model="$(get_profile_value "localAI.model" "qwen2.5-coder:latest")"
    local api_key
    api_key="$(get_profile_value "localAI.apiKey" "ollama")"
    local temp
    temp="$(get_profile_value "localAI.temperature" "0.2")"

    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    local payload
    payload=$(jq -n \
        --arg model "${model}" \
        --arg sys "${system_prompt}" \
        --arg user "${user_prompt}" \
        --argjson temp "${temp}" \
        '{
            model: $model,
            temperature: $temp,
            messages: [
                {role: "system", content: $sys},
                {role: "user", content: $user}
            ]
        }')

    local response
    response=$(curl -s --max-time 15 \
        -X POST "${base_url}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${api_key}" \
        -d "${payload}" 2>/dev/null || echo "")

    if [ -n "${response}" ]; then
        echo "${response}" | jq -r '.choices[0].message.content // empty' 2>/dev/null
    fi
}
