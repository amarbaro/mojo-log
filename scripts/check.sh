#!/usr/bin/env bash
# The gate. Every command runs under a 4 GB cap (exit 137 = over it = a bug) and 60 s.
#  1 oracle   tools/oracle.py writes N seeded random records (every field kind, odd UTF-8, controls,
#             any float bit pattern, boundary timestamps) and the exact JSON-lines / text it expects;
#             $CASES (default tests/cases.mojo) must print identical bytes; JSON lines must parse.
#  2 control  the same compare on a one-byte-corrupted expectation must fail, or the gate is blind.
#  3 alloc    LD_PRELOAD counter: 1M disabled calls and 1M enabled calls add zero allocations.
#  4 api, example (the README's), journal (sent for real when libsystemd loads, read back with journalctl), doc examples.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work/fx
M=${MOJO:-.venv/bin/mojo}; N=${N:-3000}; O="python3 -I tools/oracle.py"
if systemd-run --user --scope -q true 2>/dev/null; then  # no user systemd (CI containers): run uncapped
  cap() { systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 timeout 60 "$@"; }
else cap() { timeout 60 "$@"; }; fi
build() { cap $M build -I src "tests/$1.mojo" -o ".work/$1" 2>.work/build.err || { echo "FAIL build: tests/$1.mojo"; cat .work/build.err; exit 1; }; }
for t in cases alloc api journal; do build $t; done
cc -shared -fPIC -O1 -o .work/allocs.so tools/allocs.c -ldl || { echo "FAIL build: tools/allocs.c"; exit 1; }
CASES=${CASES:-.work/cases}
cap $O gen "$N" 1 .work/fx || { echo "FAIL setup: oracle gen"; exit 1; }
for fmt in json text; do
  rm -f .work/fx/$fmt.out
  cap $CASES $fmt .work/fx/cases.txt .work/fx/$fmt.out || { echo "FAIL oracle: $CASES $fmt crashed"; exit 1; }
  cmp -s .work/fx/$fmt.out .work/fx/$fmt.exp || { echo "FAIL oracle: $fmt output differs: $(cmp .work/fx/$fmt.out .work/fx/$fmt.exp 2>&1 | head -1)"; exit 1; }
done
got=$(cap $O lines .work/fx/json.out) || { echo "FAIL oracle: a JSON line does not parse"; exit 1; }
[[ $got == "$N" ]] || { echo "FAIL oracle: $got JSON lines, want $N"; exit 1; }
echo "oracle: $N records x (json, text) byte-identical to Python, $got JSON lines parse with json.loads"
sed '1s/./X/' .work/fx/json.exp > .work/fx/bad.exp
! cmp -s .work/fx/json.out .work/fx/bad.exp || { echo "FAIL control: corrupted expectation still compared equal"; exit 1; }
echo "control: corrupted expectation is rejected"
allocs() { LD_PRELOAD=$PWD/.work/allocs.so cap .work/alloc "$@" 2>&1 >/dev/null | sed -n 's/^allocs //p'; }
for mode in disabled enabled; do
  a=$(allocs $mode 10); b=$(allocs $mode 1000000)
  [[ $a == "$b" ]] || { echo "FAIL alloc: $mode allocs $a at 10 calls, $b at 1000000"; exit 1; }
done
a=$(allocs leaky 10); b=$(allocs leaky 100000)
(( b > a + 99000 )) || { echo "FAIL control: counter did not move on the leaky run ($a -> $b)"; exit 1; }
echo "alloc: 1M disabled and 1M enabled calls add 0 allocations (control: leaky $a -> $b)"
cap $M run -I src tests/api.mojo >.work/api.log 2>&1 || { echo "FAIL api: tests/api.mojo"; cat .work/api.log; exit 1; }
echo "api: $(grep -ao 'Summary.*' .work/api.log | head -1)"
cap $M run -I src examples/quickstart.mojo 2>.work/ex.out >/dev/null || { echo "FAIL example: examples/quickstart.mojo"; cat .work/ex.out; exit 1; }
python3 -I - .work/ex.out <<'PY' || { echo "FAIL example: quickstart output is not the two records the README shows"; exit 1; }
import json, sys
a, b = [json.loads(l) for l in open(sys.argv[1]) if l.startswith("{")]  # mojo may print a crashpad warning first
assert a["level"] == "info" and a["msg"] == "request done" and list(a)[3:] == ["path", "ms", "n", "ok"] and a["ms"] == 12.5 and a["ok"] is True
assert b["level"] == "error" and b["i"] == 2 and sum(l.startswith("{") for l in open(sys.argv[1])) == 2
PY
echo "example: examples/quickstart.mojo prints the records the README shows"
tok=t$$-$N; out=$(cap .work/journal "$tok") || { echo "FAIL journal: crashed"; exit 1; }
if [[ $out == "journal: yes" ]] && ! command -v journalctl >/dev/null; then echo "journal: sent, no journalctl to read it back (CI container), skipped"
elif [[ $out == "journal: yes" ]]; then
  sleep 1; j=$(journalctl --since -2min -o cat "MLOG_TOKEN=$tok" 2>/dev/null | head -1)
  [[ $j == "mlog journald test" ]] || { echo "FAIL journal: sent, not found in journalctl ('$j')"; exit 1; }
  echo "journal: record found in journald"
else echo "journal: libsystemd absent, skipped at run time (api test covers the skip)"; fi
echo "PASS all"
