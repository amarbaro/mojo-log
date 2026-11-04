#!/usr/bin/env bash
# tests/bench.mojo vs tools/oracle.py bench: N JSON lines (ts, level, msg, int, string, float, bool)
# to /dev/null, 3 runs each; ms of the timed loop and peak RSS of the whole process (getrusage).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 timeout 60 .venv/bin/mojo build -I src tests/bench.mojo -o .work/bench 2>.work/build.err || { echo "FAIL build: tests/bench.mojo"; cat .work/build.err; exit 1; }
N=${1:-1000000}
run() {  # each run under the 4 GB cap
  python3 -I -c 'import resource, subprocess, sys
out = subprocess.run(["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=4G", "-p", "MemorySwapMax=0"] + sys.argv[2:], capture_output=True, text=True, check=True).stdout.strip()
print("%-7s %s, peak RSS %d MB" % (sys.argv[1], out, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024))' "$@" \
    || { echo "FAIL run: $1"; exit 1; }
}
for i in 1 2 3; do run mojo timeout 60 .work/bench "$N"; run python timeout 60 python3 -I tools/oracle.py bench "$N"; done
