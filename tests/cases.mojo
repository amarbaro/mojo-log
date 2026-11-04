# cases json|text IN OUT: one record per IN line, appended to OUT.
# IN line (tabs): unix ns, level, hex(msg), then per field: hex(key), kind i|f|b|s, value
# (i decimal, f 16 hex digits of the IEEE bits, b 0|1, s hex of the UTF-8). tools/oracle.py writes it.
from std.sys import argv
from std.memory import bitcast
from mlog import Logger, Field, TRACE


def unhex(s: StringSlice[_]) -> List[UInt8]:
    var o = List[UInt8](capacity=s.byte_length() // 2)
    var b = s.as_bytes()
    for i in range(0, len(b), 2):
        var h = Int(b[i]) - (48 if b[i] < 58 else 87)
        var l = Int(b[i + 1]) - (48 if b[i + 1] < 58 else 87)
        o.append(UInt8(h * 16 + l))
    return o^


def main() raises:
    var a = argv()
    var lg = Logger(TRACE, a[1] == "json", String(a[3]))
    var text = open(String(a[2]), "r").read()
    for line in text.split("\n"):
        if line.byte_length() == 0:
            continue
        var p = line.split("\t")
        var keep = List[List[UInt8]]()  # decoded msg, then key and (string) value per field
        keep.append(unhex(p[2]))
        var nf = (len(p) - 3) // 3
        for k in range(nf):
            keep.append(unhex(p[3 + 3 * k]))
            keep.append(unhex(p[5 + 3 * k]) if p[4 + 3 * k] == "s" else List[UInt8]())
        lg.now = Int(p[0])
        lg.begin(Int(p[1]), StringSlice(unsafe_from_utf8=Span(keep[0])))
        for k in range(nf):
            var key = StringSlice(unsafe_from_utf8=Span(keep[1 + 2 * k]))
            var kind = p[4 + 3 * k]
            var v = p[5 + 3 * k]
            if kind == "i":
                lg.field(Field(key, Int(v)))
            elif kind == "b":
                lg.field(Field(key, v == "1"))
            elif kind == "f":
                var u = UInt64(0)
                for c in v.as_bytes():
                    u = u * 16 + UInt64(Int(c) - (48 if c < 58 else 87))
                lg.field(Field(key, bitcast[DType.float64, 1](SIMD[DType.uint64, 1](u))[0]))
            else:
                lg.field(Field(key, StringSlice(unsafe_from_utf8=Span(keep[2 + 2 * k]))))
        lg.end()
