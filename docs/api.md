# API

`from mlog import Logger, Field, TRACE, DEBUG, INFO, WARN, ERROR, OFF`

| Name | What |
|---|---|
| `TRACE=0 DEBUG=1 INFO=2 WARN=3 ERROR=4 OFF=5` | levels; a call below `Logger.level` writes nothing |
| `Field(key, v)` | `v` is `Int`, `Float64`, `Bool` or a string. Borrows `key` and a string `v` for the call; keep them alive until `end()` |
| `Logger(level=INFO, json=False, path="", journal=False, libsystemd="libsystemd.so.0") raises` | `path ""` = stderr, else append to that file. Raises `cannot open <path>` |
| `Logger.has_journal() -> Bool` | True when `journal` was asked and libsystemd loaded |
| `Logger.log(lvl, msg, *fields)` | filter, then `begin`, `field` each, `end` |
| `Logger.trace/debug/info/warn/error(msg, *fields)` | `log` at that level |
| `Logger.begin(lvl, msg)` | start a record; the caller has checked `lvl >= level` |
| `Logger.field(f)` | add a pair; any number |
| `Logger.end()` | one `write(2)` of the line, plus one `sd_journal_sendv` if journald is on |
| `Logger.level`, `Logger.json` | public, change at any time |
| `Logger.now` | unix ns to stamp instead of the clock (tests); `-1` = clock |

Output:

- JSON: keys `ts`, `level`, `msg`, then the fields in call order; strings escaped as Python `ensure_ascii`
  (`\uXXXX`, surrogate pairs); non-finite floats are `null`. Invalid UTF-8 never crashes (a truncated
  tail becomes U+FFFD; stray bytes are not validated).
- Text: `ts LEVEL msg k=v ...`. The message is bare unless it has a control byte. Keys and string values are
  bare only if non-empty and `[A-Za-z0-9_.:/@+-]`, else a JSON string.
- Timestamps: RFC 3339 UTC, microseconds, `Z`.
- journald: `MESSAGE`, `PRIORITY` (syslog 7/6/4/3), then each field as `KEY=value`; keys upper-cased, other
  bytes become `_`, a bad first byte becomes `X`.

Notes:

- A `Logger` owns one reused buffer; it is not thread-safe, use one per thread.
- Duplicate field keys are written as given (no dedup).
