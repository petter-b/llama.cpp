#!/usr/bin/env bash
# W3: Repetitive prose (boilerplate generation)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/run-eval.sh"

LOG="$RESULTS_DIR/w3-results.tsv"
echo -e "workload\tconfig\tlabel\ttokens\ttps\tdraft_n\tdraft_accepted\taccept_pct" > "$LOG"

PROMPT='Write a terms of service document for a SaaS product called CloudSync. Include sections for: definitions, account terms, payment terms, acceptable use, intellectual property, limitation of liability, termination, governing law. Each section should be 3-4 paragraphs.'

CONFIGS=("qwen3.5-27b" "qwen3.5-27b:ngram")
CONFIG_LABELS=("baseline" "ngram")
RUNS=3

for idx in "${!CONFIGS[@]}"; do
  model="${CONFIGS[$idx]}"
  label="${CONFIG_LABELS[$idx]}"
  echo ""
  echo "=== W3 config: $label ($model) ==="

  unload_model

  for run in $(seq 1 $RUNS); do
    echo "  Run $run/$RUNS..."
    resp="$RESULTS_DIR/w3-${label}-run${run}.json"
    messages=$(jq -n --arg p "$PROMPT" '[{"role":"user","content":$p}]')
    chat_request "$model" "$resp" "$messages"
    extract_metrics "$resp" "$LOG" "W3" "$label" "run$run"
  done
done

echo ""
echo "=== W3 Results ==="
column -t -s$'\t' "$LOG"
