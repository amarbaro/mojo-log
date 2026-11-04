# Performance

Rerun: `scripts/bench.sh [N]` (N = 1000000). 3 runs each, every run under a 4 GB cap.
Workload: one record of message + 4 fields (int, string, float, bool) per call, to `/dev/null`.
Python oracle: `json.dumps(dict, separators=(",",":"))` + `datetime.now(utc).strftime`.
Machine: 7800X3D, Mojo 1.2.0.

| 1M records | mojo ms | python ms | peak RSS mojo / python |
|---|---|---|---|
| JSON lines | 929, 860, 841 | 4867, 4865, 5192 | 11 MB / 12 MB |
| text | 801, 790, 771 | n/a | 11 MB |
| disabled (level filter) | 4, 3, 3 | n/a | 11 MB |

Source size: `wc -l src/mlog/*.mojo` = 358.
Allocations: 1M disabled and 1M enabled calls add 0 (`scripts/check.sh`, section alloc).
