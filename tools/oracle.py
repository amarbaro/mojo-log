"""Python reference for mojo-log. Stdlib only, run as a subprocess by scripts/check.sh.
  gen N SEED DIR   write DIR/cases.txt (input of tests/cases.mojo) and DIR/json.exp, DIR/text.exp
  lines FILE       every line of FILE must parse with json.loads; prints the count
  bench N          the bench workload: N JSON lines to /dev/null, prints ms"""
import json, random, re, struct, sys, time
from datetime import datetime, timezone

NAMES = ["TRACE", "DEBUG", "INFO", "WARN", "ERROR"]
SAFE = re.compile(r"[A-Za-z0-9_.:/@+-]+")


def ts(ns):
    d = datetime.fromtimestamp(ns // 10**9, timezone.utc)
    return "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ" % (d.year, d.month, d.day, d.hour, d.minute, d.second, ns % 10**9 // 1000)


def val_json(kind, v):
    if kind == "f" and v - v != 0:
        return None  # non-finite floats are written as null
    return v


def text(s, strict):
    if strict:
        return s if SAFE.fullmatch(s) else json.dumps(s)
    return s if not any(ord(c) < 32 or ord(c) == 127 for c in s) else json.dumps(s)


def val_text(kind, v):
    if kind == "i":
        return str(v)
    if kind == "f":
        return repr(v) if v - v == 0 else "null"
    if kind == "b":
        return "true" if v else "false"
    return text(v, True)


def rstr(r):
    pools = ["abcxyzABCXYZ0123456789", " _.:/@+-=", '"\\', "".join(map(chr, range(32))) + "\x7f", "éüñß", "日本語中", "😀🎉𝄞", " ﻿￿\u0080"]
    out = []
    for _ in range(r.choice([0, 1, 2, 5, 12, 40])):
        p = r.choice(pools) if r.random() < 0.5 else pools[0]
        out.append(r.choice(p))
    return "".join(out)


def rfloat(r):
    m = r.random()
    if m < 0.25:
        return struct.unpack("<d", struct.pack("<Q", r.getrandbits(64)))[0]  # any bit pattern: subnormals, nan, inf
    if m < 0.45:
        return float(r.randint(-10**6, 10**6))
    if m < 0.7:
        return round(r.uniform(-1000, 1000), r.randint(0, 8))
    if m < 0.85:
        return r.choice([0.0, -0.0, 1e16, 1e15, 9999999999999998.0, 1e-4, 1e-5, 0.1, 5e-324, 1.7976931348623157e308, 2.2250738585072014e-308, 123456789012345680.0, 0.30000000000000004, float("inf"), float("-inf"), float("nan")])
    return r.uniform(-1, 1) * 10.0 ** r.randint(-300, 300)


def rint(r):
    return r.choice([0, -1, 1, 2**63 - 1, -2**63, r.randint(-100, 100), r.randint(-2**63, 2**63 - 1), r.randint(-10**9, 10**9)])


def gen(n, seed, d):
    r = random.Random(seed)
    fixed = [0, 951782400 * 10**9, 951868799999999999, 4102444800 * 10**9 - 1, 2**63 - 1, 1793772039123456789, 86400 * 10**9 - 1]
    cases, jx, tx = [], [], []
    for i in range(n):
        t = fixed[i] if i < len(fixed) else r.randint(0, 2**63 - 1)
        lvl = r.randint(0, 4)
        msg = rstr(r)
        fields, keys = [], set()
        while len(fields) < r.choice([0, 0, 1, 2, 3, 4, 6]):
            k = rstr(r) or "k"
            if k in keys or k in ("ts", "level", "msg"):
                continue
            keys.add(k)
            kind = r.choice("ifbs")
            fields.append((k, kind, {"i": rint, "f": rfloat, "b": lambda r: r.random() < 0.5, "s": rstr}[kind](r)))
        row = [str(t), str(lvl), msg.encode().hex()]
        dj = {"ts": ts(t), "level": NAMES[lvl].lower(), "msg": msg}
        tl = "%s %s %s" % (ts(t), NAMES[lvl], text(msg, False))
        for k, kind, v in fields:
            enc = {"i": str, "f": lambda x: struct.pack(">d", x).hex(), "b": lambda x: "1" if x else "0", "s": lambda x: x.encode().hex()}[kind](v)
            row += [k.encode().hex(), kind, enc]
            dj[k] = val_json(kind, v)
            tl += " %s=%s" % (text(k, True), val_text(kind, v))
        cases.append("\t".join(row))
        jx.append(json.dumps(dj, separators=(",", ":")))
        tx.append(tl)
    for name, rows in (("cases.txt", cases), ("json.exp", jx), ("text.exp", tx)):
        open(d + "/" + name, "w", encoding="utf-8", newline="\n").write("\n".join(rows) + "\n")


def main():
    op = sys.argv[1]
    if op == "gen":
        gen(min(int(sys.argv[2]), 100000), int(sys.argv[3]), sys.argv[4])  # bounded: memory is O(n)
    elif op == "lines":
        n = 0
        for line in open(sys.argv[2], "rb"):
            json.loads(line.decode("utf-8", "replace"))
            n += 1
        print(n)
    elif op == "bench":
        out = open("/dev/null", "w")
        t = time.perf_counter()
        for i in range(int(sys.argv[2])):
            now = datetime.now(timezone.utc)
            out.write(json.dumps({"ts": now.strftime("%Y-%m-%dT%H:%M:%S.%f") + "Z", "level": "info", "msg": "request done", "n": i, "path": "/api/v1/items", "ms": i * 0.25, "ok": True}, separators=(",", ":")) + "\n")
        out.flush()
        print("%d lines %d ms" % (int(sys.argv[2]), (time.perf_counter() - t) * 1000))


main()
