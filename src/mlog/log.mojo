"""Structured logging: levels, key=value fields, text or JSON-lines, stderr/file/journald sinks.
A disabled call costs one compare. An enabled call formats into one reused buffer and makes one
write(2), so it allocates nothing after the first line."""
from std.ffi import OwnedDLHandle, external_call

comptime TRACE = 0
comptime DEBUG = 1
comptime INFO = 2
comptime WARN = 3
comptime ERROR = 4
comptime OFF = 5
comptime _Sp = Span[UInt8, ImmUntrackedOrigin]
comptime _NAMES = "TRACEDEBUGINFO WARN ERROR".as_bytes()
comptime _HEX = "0123456789abcdef".as_bytes()


def _sp(s: StringSlice[_]) -> _Sp:
    return _Sp(unsafe_ptr=rebind[Pointer[UInt8, ImmUntrackedOrigin]](s.unsafe_ptr()), length=s.byte_length())


struct Field(TrivialRegisterPassable):
    """One key=value pair; borrows the key and any string value for the duration of the call."""
    var k: _Sp
    var kind: Int  # 0 int, 1 float, 2 bool, 3 string
    var n: Int
    var f: Float64
    var s: _Sp

    def __init__(out self, key: StringSlice[_], v: Int):
        self.k = _sp(key); self.kind = 0; self.n = v; self.f = 0; self.s = self.k
    def __init__(out self, key: StringSlice[_], v: Float64):
        self.k = _sp(key); self.kind = 1; self.n = 0; self.f = v; self.s = self.k
    def __init__(out self, key: StringSlice[_], v: Bool):
        self.k = _sp(key); self.kind = 2; self.n = Int(v); self.f = 0; self.s = self.k
    def __init__(out self, key: StringSlice[_], v: StringSlice[_]):
        self.k = _sp(key); self.kind = 3; self.n = 0; self.f = 0; self.s = _sp(v)


def _int(n: Int, mut out: List[UInt8]):
    var u = UInt64(n) if n >= 0 else UInt64(0) - UInt64(n)
    if n < 0:
        out.append(45)
    var a = len(out)
    while True:
        out.append(UInt8(48 + Int(u % 10)))
        u //= 10
        if u == 0:
            break
    var b = len(out) - 1
    while a < b:
        var t = out[a]
        out[a] = out[b]
        out[b] = t
        a += 1
        b -= 1


def _pad(n: Int, w: Int, mut out: List[UInt8]):
    var d = 1
    for _ in range(w - 1):
        d *= 10
    while d > 0:
        out.append(UInt8(48 + (n // d) % 10))
        d //= 10


def _ts(s: Int, mut out: List[UInt8]):
    """YYYY-MM-DDTHH:MM:SS for unix seconds s (civil date from days, Hinnant)."""
    var z = s // 86400 + 719468
    var era = z // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var m = mp + (3 if mp < 10 else -9)
    _pad(yoe + era * 400 + (1 if m <= 2 else 0), 4, out)
    out.append(45); _pad(m, 2, out)
    out.append(45); _pad(doy - (153 * mp + 2) // 5 + 1, 2, out)
    out.append(84); _pad(s % 86400 // 3600, 2, out)
    out.append(58); _pad(s % 3600 // 60, 2, out)
    out.append(58); _pad(s % 60, 2, out)


def _d(t: List[UInt8], s: Int, k: Int, nd: Int) -> UInt8:
    return UInt8(48) if k >= nd else t[s if k == 0 else s + 1 + k]


def _flt(f: Float64, mut out: List[UInt8], mut t: List[UInt8]):
    """Python's repr(float): the fewest digits that read back as f, printf rounding (half-even)."""
    var p = 15 if abs(f) >= 2.3e-308 else 1  # 15 digits always read back for a normal double
    while True:
        _ = external_call["snprintf", Int32, num_fixed_args=3](t.unsafe_ptr(), Int(40), "%.*e".as_c_string_span().ptr(), Int32(p - 1), f)
        if external_call["strtod", Float64](t.unsafe_ptr(), Int(0)) == f:
            break
        p += 1
    var s = 0
    if t[0] == 45:
        out.append(45)
        s = 1
    var nd = p
    while nd > 1 and t[s + nd] == 48:  # strip trailing zeros (digit k > 0 sits at s + 1 + k)
        nd -= 1
    var ep = s + p + (1 if p > 1 else 0)
    var e = 0
    for i in range(ep + 2, ep + 8):
        if t[i] == 0:
            break
        e = e * 10 + Int(t[i]) - 48
    if t[ep + 1] == 45:
        e = -e
    if e < -4 or e >= 16:
        out.append(_d(t, s, 0, nd))
        if nd > 1:
            out.append(46)
            for k in range(1, nd):
                out.append(_d(t, s, k, nd))
        out.append(101)
        out.append(UInt8(45 if e < 0 else 43))
        _pad(abs(e), 2 if abs(e) < 100 else 3, out)
    elif e >= 0:
        for k in range(e + 1):
            out.append(_d(t, s, k, nd))
        out.append(46)
        if nd > e + 1:
            for k in range(e + 1, nd):
                out.append(_d(t, s, k, nd))
        else:
            out.append(48)
    else:
        out.append(48)
        out.append(46)
        for _ in range(-e - 1):
            out.append(48)
        for k in range(nd):
            out.append(_d(t, s, k, nd))


def _q(s: Span[UInt8, _], mut out: List[UInt8]):
    """A JSON string literal as Python's ensure_ascii writes it; s is valid UTF-8."""
    out.append(34)
    var i = 0
    var n = len(s)
    while i < n:
        var c = Int(s[i])
        i += 1
        if c >= 0x80:
            var x = 1 if c < 0xE0 else (2 if c < 0xF0 else 3)
            if i + x > n:
                c = 0xFFFD
                i = n
            else:
                c &= 0x3F >> x
                for _ in range(x):
                    c = (c << 6) | (Int(s[i]) & 0x3F)
                    i += 1
        if c == 34 or c == 92:
            out.append(92)
            out.append(UInt8(c))
        elif c >= 32 and c < 127:
            out.append(UInt8(c))
        elif c == 8 or c == 9 or c == 10 or c == 12 or c == 13:
            out.append(92)
            out.append(UInt8(110 if c == 10 else (114 if c == 13 else (116 if c == 9 else (98 if c == 8 else 102)))))
        else:
            for u in range(2 if c > 0xFFFF else 1):
                var cu = c
                if c > 0xFFFF:
                    cu = 0xD800 + ((c - 0x10000) >> 10) if u == 0 else 0xDC00 + ((c - 0x10000) & 0x3FF)
                out.append(92)
                out.append(117)
                for sh in range(4):
                    out.append(_HEX[(cu >> (12 - 4 * sh)) & 15])
    out.append(34)


def _txt(s: Span[UInt8, _], strict: Bool, mut out: List[UInt8]):
    """logfmt text: bare when safe, else a JSON string. Strict (keys, values): bare only if
    non-empty and [A-Za-z0-9_.:/@+-]. Loose (message): bare unless it holds a control byte."""
    var bare = not strict or len(s) > 0
    for c in s:
        if c < 32 or c == 127 or (strict and not ((c | 32 >= 97 and c | 32 <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 46 or c == 58 or c == 47 or c == 64 or c == 43 or c == 45)):
            bare = False
    if bare:
        out.extend(s)
    else:
        _q(s, out)


def _val(f: Field, mode: Int, mut out: List[UInt8], mut t: List[UInt8]):
    """mode 0 text, 1 JSON, 2 raw (journald)."""
    if f.kind == 0:
        _int(f.n, out)
    elif f.kind == 1:
        if f.f - f.f == 0:
            _flt(f.f, out, t)
        else:
            out.extend("null".as_bytes())
    elif f.kind == 2:
        out.extend("true".as_bytes() if f.n != 0 else "false".as_bytes())
    elif mode == 1:
        _q(f.s, out)
    elif mode == 0:
        _txt(f.s, True, out)
    else:
        out.extend(f.s)


struct Logger(Movable):
    var level: Int
    var json: Bool
    var fd: Int
    var now: Int  # >= 0: use this unix time in ns instead of the clock (tests)
    var buf: List[UInt8]
    var tmp: List[UInt8]
    var ts: List[Int64]
    var sec: List[UInt8]  # the date part for second `csec`, rebuilt once a second
    var csec: Int
    var jb: List[UInt8]
    var iov: List[Int]
    var sd: Optional[OwnedDLHandle]

    def __init__(out self, level: Int = INFO, json: Bool = False, path: String = "", journal: Bool = False, libsystemd: String = "libsystemd.so.0") raises:
        """path "" logs to stderr, else appends to that file; journal also sends to systemd-journald
        when libsystemd can be loaded (check has_journal(): it is skipped, not an error, if absent)."""
        self.level = level
        self.json = json
        self.fd = 2
        self.now = -1
        self.buf = List[UInt8](capacity=512)
        self.tmp = List[UInt8](length=40, fill=0)
        self.ts = List[Int64](length=2, fill=0)
        self.sec = List[UInt8](capacity=24)
        self.csec = -1
        self.jb = List[UInt8](capacity=512)
        self.iov = List[Int]()
        self.sd = None
        if path.byte_length() > 0:
            var p = path.copy()
            self.fd = Int(external_call["open64", Int32, num_fixed_args=2](p.as_c_string_span().ptr(), Int32(0o2101 | 0o2000000), Int32(0o644)))
            if self.fd < 0:
                raise Error("cannot open " + path)
        if journal:
            try:
                self.sd = OwnedDLHandle(libsystemd)
            except:
                pass

    def __deinit__(deinit self):
        if self.fd > 2:
            _ = external_call["close", Int32](Int32(self.fd))

    def has_journal(self) -> Bool:
        return Bool(self.sd)

    def _stamp(mut self, ns: Int):
        self.buf.extend(Span(self.sec))
        self.buf.append(46)
        _pad(ns % 1_000_000_000 // 1000, 6, self.buf)
        self.buf.append(90)

    def begin(mut self, lvl: Int, msg: StringSlice[_]):
        """Start a record (the caller has checked lvl >= self.level); field() adds pairs, end() writes.
        Use log() or info() for a fixed field list; begin/field/end take any number of fields."""
        var ns = self.now
        if ns < 0:
            _ = external_call["clock_gettime", Int32](Int32(0), self.ts.unsafe_ptr())
            ns = Int(self.ts[0]) * 1_000_000_000 + Int(self.ts[1])
        if ns // 1_000_000_000 != self.csec:
            self.csec = ns // 1_000_000_000
            self.sec.clear()
            _ts(self.csec, self.sec)
        var m = _sp(msg)
        var nl = 4 if lvl == INFO or lvl == WARN else 5
        self.buf.clear()
        if self.json:
            self.buf.extend('{"ts":"'.as_bytes())
            self._stamp(ns)
            self.buf.extend('","level":"'.as_bytes())
            for i in range(nl):
                self.buf.append(_NAMES[lvl * 5 + i] | 32)
            self.buf.extend('","msg":'.as_bytes())
            _q(m, self.buf)
        else:
            self._stamp(ns)
            self.buf.append(32)
            self.buf.extend(_NAMES[lvl * 5 : lvl * 5 + nl])
            self.buf.append(32)
            _txt(m, False, self.buf)
        if self.sd:  # journald: one sd_journal_sendv of MESSAGE, PRIORITY, then KEY=value per field
            self.jb.clear()
            self.iov.clear()
            self.iov.append(0)
            self.jb.extend("MESSAGE=".as_bytes())
            self.jb.extend(m)
            self.iov.append(len(self.jb))
            self.iov.append(len(self.jb))
            self.jb.extend("PRIORITY=".as_bytes())
            self.jb.append(UInt8(48 + (7 if lvl < INFO else (6 if lvl == INFO else (4 if lvl == WARN else 3)))))
            self.iov.append(len(self.jb) - self.iov[2])

    def field(mut self, f: Field):
        if self.json:
            self.buf.append(44)
            _q(f.k, self.buf)
            self.buf.append(58)
        else:
            self.buf.append(32)
            _txt(f.k, True, self.buf)
            self.buf.append(61)
        _val(f, 1 if self.json else 0, self.buf, self.tmp)
        if self.sd:  # journald wants keys A-Z0-9_ with no leading _: upper-case, other bytes become _
            var a = len(self.jb)
            self.iov.append(a)
            for j in range(len(f.k)):
                var c = f.k[j]
                if c >= 97 and c <= 122:
                    c -= 32
                if not ((c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 95) or (j == 0 and c == 95):
                    c = 88 if j == 0 else 95
                self.jb.append(c)
            self.jb.append(61)
            _val(f, 2, self.jb, self.tmp)
            self.iov.append(len(self.jb) - a)

    def end(mut self):
        if self.json:
            self.buf.append(125)
        self.buf.append(10)
        _ = external_call["__write", Int](Int32(self.fd), self.buf.unsafe_ptr(), len(self.buf))
        if self.sd:
            var n = len(self.iov) // 2
            for k in range(n):
                self.iov[2 * k] += Int(self.jb.unsafe_ptr())
            _ = self.sd.value().call["sd_journal_sendv", Int32](self.iov.unsafe_ptr(), Int32(n))

    def log(mut self, lvl: Int, msg: StringSlice[_], *fs: Field):
        if lvl < self.level:
            return
        self.begin(lvl, msg)
        for i in range(len(fs)):
            self.field(fs[i])
        self.end()

    def trace(mut self, msg: StringSlice[_], *fs: Field):
        self.log(TRACE, msg, *fs)

    def debug(mut self, msg: StringSlice[_], *fs: Field):
        self.log(DEBUG, msg, *fs)

    def info(mut self, msg: StringSlice[_], *fs: Field):
        self.log(INFO, msg, *fs)

    def warn(mut self, msg: StringSlice[_], *fs: Field):
        self.log(WARN, msg, *fs)

    def error(mut self, msg: StringSlice[_], *fs: Field):
        self.log(ERROR, msg, *fs)
