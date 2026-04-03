#!/bin/bash
set -euo pipefail

FIXTURE_DIR="${1:-benchmarks/fixtures}"

mkdir -p "$FIXTURE_DIR/medium"

generate_medium_files() {
  local index
  for index in $(seq 1 10); do
    awk -v idx="$index" '
      BEGIN {
        for (i = 1; i <= 900; i++) {
          printf("Medium benchmark file %02d line %04d: LunaPad memory test content for regular editing, search, and restore behavior. This line is intentionally long enough to create realistic editor load.\n", idx, i)
        }
      }
    ' > "$FIXTURE_DIR/medium/medium-$index.txt"
  done
}

generate_large_plain_text() {
  awk '
    BEGIN {
      for (i = 1; i <= 85000; i++) {
        printf("Large plain text benchmark line %06d: LunaPad should stay responsive while loading, viewing, and restoring this document. The content is repetitive on purpose but still line-oriented and realistic for editor stress.\n", i)
      }
    }
  ' > "$FIXTURE_DIR/large-plain.txt"
}

generate_large_markdown() {
  awk '
    BEGIN {
      for (i = 1; i <= 18000; i++) {
        printf("# Memory Benchmark Section %05d\n\n", i)
        printf("This Markdown fixture exists to measure LunaPad preview and editor behavior under sustained document size. It includes paragraphs, lists, quotes, and code blocks.\n\n")
        printf("- item one for section %05d\n- item two for section %05d\n- item three for section %05d\n\n", i, i, i)
        printf("> Quoted text for section %05d to create more structure and wrapping work inside the preview renderer.\n\n", i)
        printf("```text\nbenchmark-code-block-%05d\nLunaPad markdown memory test payload\n```\n\n", i)
      }
    }
  ' > "$FIXTURE_DIR/large-markdown.md"
}

generate_live_log() {
  awk '
    BEGIN {
      levels[0] = "INFO"
      levels[1] = "DEBUG"
      levels[2] = "WARN"
      levels[3] = "ERROR"
      for (i = 1; i <= 70000; i++) {
        level = levels[i % 4]
        printf("2026-04-03T12:%02d:%02dZ [%s] benchmark.service request_id=req-%06d message=\"Live log fixture for LunaPad auto-reload and highlighting\" duration_ms=%d\n", i % 60, (i * 7) % 60, level, i, (i * 13) % 4000)
      }
    }
  ' > "$FIXTURE_DIR/live.log"
}

report_sizes() {
  echo "Generated fixtures in $FIXTURE_DIR"
  find "$FIXTURE_DIR" -type f | sort | while read -r file; do
    stat -f "%z bytes  %N" "$file"
  done
}

generate_medium_files
generate_large_plain_text
generate_large_markdown
generate_live_log
report_sizes
