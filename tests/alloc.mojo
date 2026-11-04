# alloc MODE N: N log calls, for the allocation count (tools/allocs.c) and the RSS check.
#   disabled  level filters every call out        enabled  every call formats and writes to /dev/null
#   leaky     control: a List allocated per call, so the counter must move
from std.sys import argv
from mlog import Logger, Field, INFO, ERROR


def main() raises:
    var a = argv()
    var n = Int(a[2])
    if a[1] == "leaky":
        var s = 0
        for i in range(n):
            var l = List[Int](length=64, fill=i)
            l[i % 64] = s
            s += l[(i * 7) % 64] + 1
        print(s)
        return
    var lg = Logger(ERROR if a[1] == "disabled" else INFO, True, "/dev/null")
    for i in range(n):
        lg.info("request done", Field("n", i), Field("path", "/api/v1/items"), Field("ms", Float64(i) * 0.25), Field("ok", True))
