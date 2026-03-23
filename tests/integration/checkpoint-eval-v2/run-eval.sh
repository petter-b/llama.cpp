#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-https://ai.gutan.se/v1}"
RESULTS_DIR="$(cd "$(dirname "$0")" && pwd)/results"
mkdir -p "$RESULTS_DIR"

# Send a chat completion request and save the full response
# Usage: chat_request <model> <output_file> <messages_json> [max_tokens] [extra_body_json]
# max_tokens defaults to 4096. extra_body_json is appended inside the request object.
chat_request() {
  local model="$1" output="$2" messages="$3"
  local max_tokens="${4:-4096}"
  local extra="${5:-}"
  local body="{
    \"model\": \"$model\",
    \"messages\": $messages,
    \"temperature\": 0,
    \"max_tokens\": $max_tokens"
  if [[ -n "$extra" ]]; then
    body="$body, $extra"
  fi
  body="$body }"
  curl -s "$API_BASE/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$body" > "$output"
}

# Extract metrics from a response file, append to TSV log
# Usage: extract_metrics <response_file> <log_file> <workload> <config> <label>
extract_metrics() {
  local resp="$1" log="$2" workload="$3" config="$4" label="$5"
  local line
  line=$(jq -r --arg w "$workload" --arg c "$config" --arg l "$label" '[
    $w, $c, $l,
    ((.timings.predicted_n // .usage.completion_tokens // "") | tostring),
    ((.timings.predicted_per_second // "") | tostring),
    ((.timings.draft_n // "") | tostring),
    ((.timings.draft_n_accepted // "") | tostring),
    (if (.timings.draft_n // 0) > 0
     then ((.timings.draft_n_accepted // 0) / .timings.draft_n * 100 | . * 10 | round / 10 | tostring)
     else "" end)
  ] | @tsv' "$resp")
  echo "$line" >> "$log"
}

# Unload current model to free VRAM
# UNLOAD_URL can be overridden if llama-swap uses a different path
UNLOAD_URL="${UNLOAD_URL:-${API_BASE%/v1}/unload}"
unload_model() {
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' "$UNLOAD_URL")
  if [[ "$status" != "200" && "$status" != "204" ]]; then
    echo "  WARNING: unload returned HTTP $status (URL: $UNLOAD_URL)" >&2
    echo "  n-gram map may carry over between configs" >&2
  fi
  sleep 2
}

# Only print banner when run directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Checkpoint Eval v2 — $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo "API: $API_BASE"
  echo "Results: $RESULTS_DIR"
fi
