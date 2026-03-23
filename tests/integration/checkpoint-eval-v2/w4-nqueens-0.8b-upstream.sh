#!/usr/bin/env bash
# W4: Non-repetitive code (control — expected to show no benefit)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/run-eval.sh"

LOG="$RESULTS_DIR/w4-results.tsv"
echo -e "workload\tconfig\tlabel\ttokens\ttps\tdraft_n\tdraft_accepted\taccept_pct" > "$LOG"

PROMPT='Write a Python function that solves the N-queens problem using backtracking. Include type hints and a docstring.'

CONFIGS=("qwen3.5-0.8b" "qwen3.5-0.8b:ngram-upstream")
CONFIG_LABELS=("baseline" "ngram-upstream")
RUNS=3

for idx in "${!CONFIGS[@]}"; do
  model="${CONFIGS[$idx]}"
  label="${CONFIG_LABELS[$idx]}"
  echo ""
  echo "=== W4 config: $label ($model) ==="

  unload_model

  for run in $(seq 1 $RUNS); do
    echo "  Run $run/$RUNS..."
    resp="$RESULTS_DIR/w4-${label}-run${run}.json"
    messages=$(jq -n --arg p "$PROMPT" '[{"role":"user","content":$p}]')
    chat_request "$model" "$resp" "$messages" 1024
    extract_metrics "$resp" "$LOG" "W4" "$label" "run$run"
  done
done

echo ""
echo "=== W4 Results ==="
column -t -s$'\t' "$LOG"
