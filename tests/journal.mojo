# journal TOKEN: one WARN record to journald (and /dev/null); prints "journal: yes|no" (libsystemd loadable).
from std.sys import argv
from mlog import Logger, Field, WARN


def main() raises:
    var lg = Logger(WARN, False, "/dev/null", True)
    print("journal:", "yes" if lg.has_journal() else "no")
    lg.warn("mlog journald test", Field("mlog_token", String(argv()[1])), Field("n", 42), Field("pi", 3.5), Field("_bad key", "v w"))
