#!/usr/bin/env bash
# W2: Repetitive structured output (JSON generation)
# Grammar-constrained via response_format: json_object
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/run-eval.sh"

LOG="$RESULTS_DIR/w2-results.tsv"
echo -e "workload\tconfig\tlabel\ttokens\ttps\tdraft_n\tdraft_accepted\taccept_pct" > "$LOG"

PROMPT='Generate a JSON array of 50 people with name, age, city, occupation.'

CONFIGS=("qwen3.5-27b" "qwen3.5-27b:ngram")
CONFIG_LABELS=("baseline" "ngram")
RUNS=5

for idx in "${!CONFIGS[@]}"; do
  model="${CONFIGS[$idx]}"
  label="${CONFIG_LABELS[$idx]}"
  echo ""
  echo "=== W2 config: $label ($model) ==="

  unload_model

  for run in $(seq 1 $RUNS); do
    echo "  Run $run/$RUNS..."
    resp="$RESULTS_DIR/w2-${label}-run${run}.json"
    messages=$(jq -n --arg p "$PROMPT" '[{"role":"user","content":$p}]')

    chat_request "$model" "$resp" "$messages" 4096 '"response_format": {"type": "json_object"}'
    extract_metrics "$resp" "$LOG" "W2" "$label" "run$run"

    # Validate JSON in response
    content=$(jq -r '.choices[0].message.content' "$resp")
    if echo "$content" | jq . > /dev/null 2>&1; then
      echo "    JSON: valid"
    else
      echo "    JSON: INVALID — check $resp"
    fi
  done
done

echo ""
echo "=== W2 Results ==="
column -t -s$'\t' "$LOG"
