#!/usr/bin/env bash
# W4: Non-repetitive code (control) — 9B model eval
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/run-eval.sh"

LOG="$RESULTS_DIR/w4-9b-results.tsv"
echo -e "workload\tconfig\tlabel\ttokens\ttps\tdraft_n\tdraft_accepted\taccept_pct\tspec_cycles\tspec_empty\tspec_skip" > "$LOG"

PROMPT='Write a Python function that solves the N-queens problem using backtracking. Include type hints and a docstring.'

CONFIGS=("qwen3.5-9b" "qwen3.5-9b:ngram" "qwen3.5-9b:draft")
CONFIG_LABELS=("baseline" "ngram" "draft")
RUNS=3

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
  echo "=== W4-9B config: $label ($model) ==="

  unload_model

  for run in $(seq 1 $RUNS); do
    echo "  Run $run/$RUNS..."
    resp="$RESULTS_DIR/w4-9b-${label}-run${run}.json"
    messages=$(jq -n --arg p "$PROMPT" '[{"role":"user","content":$p}]')
    chat_request "$model" "$resp" "$messages" 1024
    extract_metrics_9b "$resp" "$LOG" "W4-9B" "$label" "run$run"
  done
done

echo ""
echo "=== W4-9B Results ==="
column -t -s$'\t' "$LOG"
