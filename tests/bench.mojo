# bench N: N JSON lines to /dev/null (tools/oracle.py bench does the same work), then N text lines,
# then N calls the level filters out. Prints ms for each.
from std.sys import argv
from std.time import perf_counter_ns
from mlog import Logger, Field, INFO, ERROR


def run(mut lg: Logger, n: Int) -> Int:
    var t = perf_counter_ns()
    for i in range(n):
        lg.info("request done", Field("n", i), Field("path", "/api/v1/items"), Field("ms", Float64(i) * 0.25), Field("ok", True))
    return Int(perf_counter_ns() - t) // 1_000_000


def main() raises:
    var n = Int(argv()[1])
    var j = Logger(INFO, True, "/dev/null")
    var t = Logger(INFO, False, "/dev/null")
    var d = Logger(ERROR, True, "/dev/null")
    print(n, "lines json", run(j, n), "ms, text", run(t, n), "ms, disabled", run(d, n), "ms")
