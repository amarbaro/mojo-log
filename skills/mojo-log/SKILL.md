---
name: mojo-log
description: "Structured logging for Mojo: levels, key=value fields, text or JSON lines, stderr, file or journald. Use when a Mojo program needs fast logs that allocate nothing per call."
metadata:
  short-description: "Structured logging for Mojo: levels, fields, text/JSON lines, stderr/file/journald"
---

# mojo-log

Package `mlog`, Mojo 1.2, Linux. JSON lines are byte-identical with what Python `json.loads` reads.

## When to use

A Mojo program needs logs with levels and `key=value` fields, JSON lines, or journald.
Not thread-safe: one `Logger` per thread.

## Install

`mojo run -I src app.mojo` from a clone, or copy `src/mlog/`.

## The calls

```mojo
from mlog import Logger, Field, INFO, WARN

def main() raises:
    var log = Logger(INFO, True)       # (level, json, path="" = stderr, journal=False); raises on a bad path
    log.info("done", Field("n", 3), Field("ms", 12.5), Field("ok", True), Field("path", "/x"))
    log.begin(WARN, "runtime fields")  # field list built at run time
    log.field(Field("k", 1))
    log.end()
    log.level = WARN                   # change the filter any time; a disabled call is one compare
    print(Logger(INFO, False, "app.log", True).has_journal())  # file sink plus journald
```

JSON: `{"ts":"2026-01-01T00:00:00.123456Z","level":"info","msg":"done","n":3,...}`.
Text: `2026-01-01T00:00:00.123456Z INFO done n=3 ms=12.5 ok=true path=/x`.

## Gotchas

- `Field` borrows its key and any string value: keep the owning `String` alive until the call returns
  (until `end()` for a `begin` list).
- `has_journal()` is False when `libsystemd` is absent; journald is then skipped, not an error.
- journald keys are upper-cased, a bad byte becomes `_`, a bad first byte `X`.
- Duplicate keys are written as given.
- Levels: `TRACE DEBUG INFO WARN ERROR OFF`.

## Gate

`scripts/check.sh` from the repo: records byte-identical to Python, a corrupted-expectation control,
zero allocations over 1M calls, API tests, the README example, journald read back. `scripts/bench.sh` for speed.
