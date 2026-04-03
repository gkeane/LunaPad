#!/bin/bash
set -euo pipefail

LOG_FILE="${1:-benchmarks/fixtures/live.log}"
LINES="${2:-5000}"

if [ ! -f "$LOG_FILE" ]; then
  echo "Log file not found: $LOG_FILE" >&2
  exit 1
fi

awk -v lines="$LINES" '
  BEGIN {
    levels[0] = "INFO"
    levels[1] = "DEBUG"
    levels[2] = "WARN"
    levels[3] = "ERROR"
    for (i = 1; i <= lines; i++) {
      level = levels[i % 4]
      printf("2026-04-03T13:%02d:%02dZ [%s] benchmark.append request_id=append-%06d message=\"Appended live log data for LunaPad benchmark\" duration_ms=%d\n", i % 60, (i * 11) % 60, level, i, (i * 17) % 5000)
    }
  }
' >> "$LOG_FILE"

stat -f "%z bytes  %N" "$LOG_FILE"
