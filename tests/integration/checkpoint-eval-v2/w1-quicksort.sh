#!/usr/bin/env bash
# W1: Iterative code generation (quicksort suite)
# Source: PR #19164 (ggerganov's demo workload for ngram-mod)
# Multi-turn, same session — tests n-gram warmup across turns
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/run-eval.sh"

LOG="$RESULTS_DIR/w1-results.tsv"
echo -e "workload\tconfig\tlabel\ttokens\ttps\tdraft_n\tdraft_accepted\taccept_pct" > "$LOG"

# The 4 turns of the quicksort suite (order matters — each builds on previous)
TURNS=(
  'Write a quicksort implementation in C with detailed comments.'
  'Now write a merge sort in C with the same style and commenting pattern.'
  'Add a benchmark harness that compares both sorting algorithms on arrays of size 100, 1000, and 10000. Print results in a table.'
  'Refactor: extract the timing logic into a reusable benchmark() function. Keep the same output format.'
)
TURN_NAMES=("quicksort" "merge-sort" "benchmark-harness" "refactor")

CONFIGS=("qwen3.5-27b" "qwen3.5-27b:ngram" "qwen3.5-27b:draft")
CONFIG_LABELS=("baseline" "ngram" "draft")

for idx in "${!CONFIGS[@]}"; do
  model="${CONFIGS[$idx]}"
  label="${CONFIG_LABELS[$idx]}"
  echo ""
  echo "=== W1 config: $label ($model) ==="

  unload_model

  # Start with empty message history
  messages='[]'

  for turn_idx in "${!TURNS[@]}"; do
    turn_num=$((turn_idx + 1))
    turn_name="${TURN_NAMES[$turn_idx]}"
    turn_prompt="${TURNS[$turn_idx]}"

    echo "  Turn $turn_num: $turn_name..."

    # Add user message (use jq for safe JSON escaping)
    messages=$(echo "$messages" | jq --arg p "$turn_prompt" '. + [{"role":"user","content":$p}]')

    resp="$RESULTS_DIR/w1-${label}-turn${turn_num}.json"
    chat_request "$model" "$resp" "$messages"
    extract_metrics "$resp" "$LOG" "W1" "$label" "turn$turn_num"

    # Accumulate assistant response into history for next turn
    assistant_content=$(jq -r '.choices[0].message.content' "$resp")
    messages=$(echo "$messages" | jq --arg a "$assistant_content" '. + [{"role":"assistant","content":$a}]')
  done

  echo "  Done. Results in $LOG"
done

echo ""
echo "=== W1 Results ==="
column -t -s$'\t' "$LOG"
