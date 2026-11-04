# mojo-log

<!-- install -->
Install: `pixi add mojo-log` once published. For now: `git clone https://github.com/amarbaro/mojo-log`, then `mojo run -I mojo-log/src app.mojo`.

```mojo
from mlog import Logger, Field, INFO

def main() raises:
    var log = Logger(INFO, True)        # JSON lines on stderr; Logger(INFO, False, "app.log") appends text to a file
    log.info("request done", Field("path", "/api/v1/items"), Field("ms", 12.5), Field("n", 3), Field("ok", True))
    log.debug("below INFO: costs one compare, writes nothing")
    log.begin(4, "any number of fields")  # begin / field / end for a field list built at run time
    for i in range(3):
        log.field(Field("i", i))
    log.end()
```

| 1M records | mojo ms | python ms | peak RSS mojo / python |
|---|---|---|---|
| JSON lines | 929, 860, 841 | 4867, 4865, 5192 | 11 MB / 12 MB |
Baselines and method: [docs/perf.md](docs/perf.md)
<!-- /install -->

Structured logging for Mojo: levels, `key=value` fields, text or JSON-lines, stderr, file and
journald sinks. 358 lines. A disabled call costs one compare (3 ns); an enabled call allocates
nothing after the first line (gated: 1M calls add 0 allocations). JSON lines are byte-identical to
Python `json.dumps(..., separators=(",",":"))` on 3000 seeded random records.

```mojo
from mlog import Logger, Field, INFO

def main() raises:
    var log = Logger(INFO, True)        # JSON lines on stderr; Logger(INFO, False, "app.log") appends text to a file
    log.info("request done", Field("path", "/api/v1/items"), Field("ms", 12.5), Field("n", 3), Field("ok", True))
    log.debug("below INFO: costs one compare, writes nothing")
    log.begin(4, "any number of fields")  # begin / field / end for a field list built at run time
    for i in range(3):
        log.field(Field("i", i))
    log.end()
```

This is `examples/quickstart.mojo`; the gate runs it.

## Install

Requires Mojo 1.2 on Linux. `libsystemd.so.0` is optional (journald).

| Way | Command |
|---|---|
| Source path | `mojo run -I path/to/mojo-log/src app.mojo` |
| Precompiled | `mojo precompile src/mlog -o mlog.mojoc` |
| Vendor | copy `src/mlog/` into your project |

## What you get

- Levels `TRACE DEBUG INFO WARN ERROR`, `OFF`. `Logger(level, json, path, journal)`.
- JSON line: `{"ts":"2026-11-04T06:00:39.123456Z","level":"info","msg":"...","k":v}`.
  Text line: `2026-11-04T06:00:39.123456Z INFO msg k=v`, values quoted only when needed.
- Fields: `Int`, `Float64` (Python `repr`; NaN and infinity become `null`), `Bool`, string.
- Sinks: stderr, a file (append, safe for several loggers), journald when libsystemd loads
  (else skipped at run time, not an error).

API: [docs/api.md](docs/api.md). Design: [docs/design.md](docs/design.md). Numbers: [docs/perf.md](docs/perf.md).

## Performance

`scripts/bench.sh`, 1M records of 4 fields to `/dev/null`: JSON 841 to 929 ms against Python
4865 to 5192 ms (about 5.6x), peak RSS 11 MB against 12 MB. Text 771 to 801 ms. 1M disabled calls: 3 to 4 ms.

## Checks

`scripts/check.sh` (about 10 s, every command under a 4 GB cap): 3000 records in both formats
byte-identical to the Python reference, every JSON line parses, a corrupted expectation is
rejected, 0 allocations over 1M disabled and 1M enabled calls (control: a leaking loop moves the
counter), 5 API tests, the README example, a record read back from journald.
`scripts/ci.sh` runs it from a clean checkout.

Apache-2.0.
