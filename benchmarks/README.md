# LunaPad Memory Benchmarks

This folder holds repeatable memory snapshots for the work tracked in [memoryplan.md](../memoryplan.md).

## What To Measure

Capture these scenarios in order:

1. Idle app after launch settles
2. 10 medium text tabs
3. 1 large plain-text document
4. 1 large Markdown document
5. 1 live `.log` file with auto-reload enabled
6. Relaunch into a restored session containing one large saved file

For each scenario, record:

- workspace count
- tab count
- selected document size
- whether the document is in normal mode, large-file safe mode, or `Edit Anyway`
- whether Markdown preview is active
- whether log watching is active
- `ps` RSS
- `vmmap` physical footprint
- `vmmap` peak physical footprint

## Fixture Generation

Create the repeatable test files with:

```bash
./benchmarks/generate-fixtures.sh
```

This generates:

- `benchmarks/fixtures/medium/medium-1.txt` through `medium-10.txt`
- `benchmarks/fixtures/large-plain.txt`
- `benchmarks/fixtures/large-markdown.md`
- `benchmarks/fixtures/live.log`

To simulate live log growth during the log scenario:

```bash
./benchmarks/append-live-log.sh
```

## Capture Command

Run LunaPad, put it in the target scenario, then capture a snapshot:

```bash
scripts/capture-memory-snapshot.sh \
  --label "idle" \
  --workspaces 1 \
  --tabs 1 \
  --doc-size "0 KB" \
  --mode "normal" \
  --preview no \
  --log-mode no
```

This writes a timestamped Markdown report into `benchmarks/results/`.

## Scenario Examples

### Idle

```bash
scripts/capture-memory-snapshot.sh \
  --label "idle" \
  --workspaces 1 \
  --tabs 1 \
  --doc-size "0 KB" \
  --mode "normal" \
  --preview no \
  --log-mode no
```

### Large Plain Text In Safe Mode

```bash
scripts/capture-memory-snapshot.sh \
  --label "large-plain-safe-mode" \
  --workspaces 1 \
  --tabs 1 \
  --doc-size "12 MB" \
  --mode "large-safe" \
  --preview no \
  --log-mode no
```

### Large Markdown In Split Preview

```bash
scripts/capture-memory-snapshot.sh \
  --label "large-markdown-split" \
  --workspaces 1 \
  --tabs 1 \
  --doc-size "2.5 MB" \
  --mode "markdown-split" \
  --preview yes \
  --log-mode no
```

### Live Log

```bash
scripts/capture-memory-snapshot.sh \
  --label "live-log-autoreload" \
  --workspaces 1 \
  --tabs 1 \
  --doc-size "8 MB retained" \
  --mode "log-view" \
  --preview no \
  --log-mode yes
```

## Results Convention

- one file per capture
- filename format: `<timestamp>-<label>.md`
- keep raw snapshots immutable once captured
- if you rerun a scenario after a code change, create a new file instead of editing the old one

## Baseline Checklist

Use this checklist when creating the first comparable baseline:

- build the current app with `./build.sh`
- launch `/Applications/LunaPad.app`
- wait for the app to settle before capturing idle
- capture each scenario with the script above
- write a short one-paragraph summary comparing the worst and best footprint numbers
