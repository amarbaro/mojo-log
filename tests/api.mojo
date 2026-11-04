# API behaviour: level filter, exact text line, file append, bad path, absent libsystemd, odd UTF-8.
from std.testing import assert_equal, assert_true, assert_false, assert_raises, TestSuite
from mlog import Logger, Field, TRACE, INFO, WARN, ERROR, OFF

comptime F = ".work/api.log"
comptime NS = 1793772039123456789  # 2026-11-04T06:00:39.123456Z


def fresh() raises:
    with open(F, "w") as f:
        f.write("")


def test_filter_and_text() raises:
    fresh()
    var lg = Logger(WARN, False, F)
    lg.now = NS
    lg.info("dropped", Field("a", 1))
    lg.warn("kept it", Field("n", -7), Field("s", "x y"), Field("f", 2.5), Field("ok", False))
    lg.error("boom")
    var off = Logger(OFF, False, F)
    off.error("never")
    assert_equal(open(F, "r").read(), '2026-11-04T06:00:39.123456Z WARN kept it n=-7 s="x y" f=2.5 ok=false\n2026-11-04T06:00:39.123456Z ERROR boom\n')


def test_two_loggers_append() raises:
    fresh()
    var a = Logger(INFO, True, F)
    var b = Logger(INFO, True, F)
    a.now = NS
    b.now = NS
    a.info("one")
    b.info("two", Field("k", "v"))
    a.info("three")
    var lines = open(F, "r").read().split("\n")
    assert_equal(len(lines), 4)
    assert_equal(String(lines[1]), '{"ts":"2026-11-04T06:00:39.123456Z","level":"info","msg":"two","k":"v"}')


def test_bad_path_raises() raises:
    with assert_raises():
        _ = Logger(INFO, False, "/nonexistent-dir/x.log")


def test_journal_absent_is_skipped() raises:
    fresh()
    var lg = Logger(INFO, False, F, True, "libmlog-no-such-lib.so.9")
    assert_false(lg.has_journal())
    lg.now = NS
    lg.info("still written")
    assert_equal(open(F, "r").read(), "2026-11-04T06:00:39.123456Z INFO still written\n")


def test_odd_utf8_does_not_crash() raises:
    fresh()
    var lg = Logger(INFO, True, F)
    var bad: List[UInt8] = [97, 0xC3, 98, 0xE2, 0x82, 0xFF, 0xF0, 0x9F, 0x98]  # stray, truncated and invalid bytes
    lg.info(StringSlice(unsafe_from_utf8=Span(bad)), Field("v", StringSlice(unsafe_from_utf8=Span(bad))))
    assert_true(open(F, "r").read().byte_length() > 20)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
