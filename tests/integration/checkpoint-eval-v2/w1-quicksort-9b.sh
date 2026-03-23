#!/usr/bin/env bash
# W1: Iterative code generation (quicksort suite) — 9B model eval
# Tests 9B + 0.8B draft model with better parameter ratio (~9% vs ~3%)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/run-eval.sh"

LOG="$RESULTS_DIR/w1-9b-results.tsv"
echo -e "workload\tconfig\tlabel\ttokens\ttps\tdraft_n\tdraft_accepted\taccept_pct\tspec_cycles\tspec_empty\tspec_skip" > "$LOG"

TURNS=(
  'Write a quicksort implementation in C with detailed comments.'
  'Now write a merge sort in C with the same style and commenting pattern.'
  'Add a benchmark harness that compares both sorting algorithms on arrays of size 100, 1000, and 10000. Print results in a table.'
  'Refactor: extract the timing logic into a reusable benchmark() function. Keep the same output format.'
)
TURN_NAMES=("quicksort" "merge-sort" "benchmark-harness" "refactor")

CONFIGS=("qwen3.5-9b" "qwen3.5-9b:ngram" "qwen3.5-9b:draft")
CONFIG_LABELS=("baseline" "ngram" "draft")

extract_metrics_9b() {
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
     else "" end),
    ((.timings.spec_cycles // "") | tostring),
    ((.timings.spec_empty // "") | tostring),
    ((.timings.spec_skip // "") | tostring)
  ] | @tsv' "$resp")
  echo "$line" >> "$log"
}

for idx in "${!CONFIGS[@]}"; do
  model="${CONFIGS[$idx]}"
  label="${CONFIG_LABELS[$idx]}"
  echo ""
  echo "=== W1-9B config: $label ($model) ==="

  unload_model

  messages='[]'

  for turn_idx in "${!TURNS[@]}"; do
    turn_num=$((turn_idx + 1))
    turn_name="${TURN_NAMES[$turn_idx]}"
    turn_prompt="${TURNS[$turn_idx]}"

    echo "  Turn $turn_num: $turn_name..."

    messages=$(echo "$messages" | jq --arg p "$turn_prompt" '. + [{"role":"user","content":$p}]')

    resp="$RESULTS_DIR/w1-9b-${label}-turn${turn_num}.json"
    chat_request "$model" "$resp" "$messages"
    extract_metrics_9b "$resp" "$LOG" "W1-9B" "$label" "turn$turn_num"

    assistant_content=$(jq -r '.choices[0].message.content' "$resp")
    messages=$(echo "$messages" | jq --arg a "$assistant_content" '. + [{"role":"assistant","content":$a}]')
  done

  echo "  Done. Results in $LOG"
done

echo ""
echo "=== W1-9B Results ==="
column -t -s$'\t' "$LOG"
