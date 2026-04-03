#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-LunaPad}"
PROCESS_PATTERN="${PROCESS_PATTERN:-}"
PID=""
LABEL=""
OUTPUT=""
WORKSPACES="unknown"
TABS="unknown"
DOC_SIZE="unknown"
MODE="unknown"
PREVIEW="unknown"
LOG_MODE="unknown"

usage() {
  cat <<'EOF'
Usage:
  scripts/capture-memory-snapshot.sh [options]

Options:
  --pid <pid>                Capture a specific process instead of auto-detecting LunaPad
  --app-name <name>          App name to report and auto-detect, defaults to LunaPad
  --process-pattern <regex>  Custom ps/awk regex used to find the process
  --label <label>            Scenario label, used in the output filename and report body
  --output <path>            Write to this file instead of benchmarks/results/<timestamp>-<label>.md
  --workspaces <count>       Active workspace count
  --tabs <count>             Active tab count
  --doc-size <value>         Selected document size, e.g. 24 KB or 8.2 MB
  --mode <value>             editor mode: normal, large-safe, edit-anyway, markdown-split, etc.
  --preview <yes|no>         Whether markdown preview is active
  --log-mode <yes|no>        Whether log watching is active
  --help                     Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pid)
      PID="${2:-}"
      shift 2
      ;;
    --app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --process-pattern)
      PROCESS_PATTERN="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --workspaces)
      WORKSPACES="${2:-}"
      shift 2
      ;;
    --tabs)
      TABS="${2:-}"
      shift 2
      ;;
    --doc-size)
      DOC_SIZE="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --preview)
      PREVIEW="${2:-}"
      shift 2
      ;;
    --log-mode)
      LOG_MODE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

find_pid() {
  local pattern="$PROCESS_PATTERN"

  if [ -z "$pattern" ]; then
    case "$APP_NAME" in
      LunaPad)
        pattern='LunaPad\.app/Contents/MacOS/LunaPad'
        ;;
      CotEditor)
        pattern='CotEditor\.app/Contents/MacOS/CotEditor'
        ;;
      *)
        pattern="${APP_NAME//./\\.}\\.app/Contents/MacOS/${APP_NAME//./\\.}"
        ;;
    esac
  fi

  ps -axo pid=,command= | awk -v pattern="$pattern" '
    $0 ~ pattern { pid=$1 }
    END {
      if (pid != "") {
        print pid
      }
    }
  '
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

slugify() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'
}

extract_vmmap_value() {
  local label="$1"
  local content="$2"
  local line
  line=$(printf "%s\n" "$content" | awk -F: -v label="$label" 'index($0, label ":") == 1 { print $2; exit }')
  trim "$line"
}

if [ -z "$PID" ]; then
  PID="$(find_pid || true)"
fi

if [ -z "$PID" ]; then
  echo "Could not find a running $APP_NAME process. Launch $APP_NAME first, then rerun this script." >&2
  exit 1
fi

TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TIMESTAMP_FILE="$(date -u +"%Y%m%dT%H%M%SZ")"

if [ -z "$LABEL" ]; then
  LABEL="snapshot"
fi

if [ -z "$OUTPUT" ]; then
  mkdir -p benchmarks/results
  OUTPUT="benchmarks/results/${TIMESTAMP_FILE}-$(slugify "$LABEL").md"
fi

PS_ROW="$(ps -o pid=,rss=,vsz=,etime=,command= -p "$PID" | sed -n '1p')"
RSS_KB="$(printf "%s\n" "$PS_ROW" | awk '{print $2}')"
VSZ_KB="$(printf "%s\n" "$PS_ROW" | awk '{print $3}')"
ELAPSED="$(printf "%s\n" "$PS_ROW" | awk '{print $4}')"
COMMAND="$(printf "%s\n" "$PS_ROW" | awk '{for (i=5; i<=NF; i++) printf("%s%s", $i, (i < NF ? OFS : ""))}')"

VMMAP_SUMMARY="$(vmmap -summary "$PID" 2>&1 || true)"
PHYSICAL_FOOTPRINT="$(extract_vmmap_value "Physical footprint" "$VMMAP_SUMMARY")"
PEAK_PHYSICAL_FOOTPRINT="$(extract_vmmap_value "Physical footprint (peak)" "$VMMAP_SUMMARY")"

mkdir -p "$(dirname "$OUTPUT")"

cat > "$OUTPUT" <<EOF
# $APP_NAME Memory Snapshot

- Timestamp (UTC): \`$TIMESTAMP_UTC\`
- Scenario label: \`$LABEL\`
- PID: \`$PID\`

## Scenario Metadata

- Workspaces: \`$WORKSPACES\`
- Tabs: \`$TABS\`
- Selected document size: \`$DOC_SIZE\`
- Active mode: \`$MODE\`
- Markdown preview active: \`$PREVIEW\`
- Log mode active: \`$LOG_MODE\`

## Process Metrics

- RSS: \`${RSS_KB:-unknown} KB\`
- VSZ: \`${VSZ_KB:-unknown} KB\`
- Elapsed runtime: \`${ELAPSED:-unknown}\`
- Physical footprint: \`${PHYSICAL_FOOTPRINT:-unavailable}\`
- Peak physical footprint: \`${PEAK_PHYSICAL_FOOTPRINT:-unavailable}\`

## Raw Capture

\`\`\`text
$PS_ROW
\`\`\`

\`\`\`text
$(printf "%s\n" "$VMMAP_SUMMARY" | grep -E "Physical footprint|Process:" || printf "%s\n" "$VMMAP_SUMMARY")
\`\`\`
EOF

printf "Wrote %s\n" "$OUTPUT"
