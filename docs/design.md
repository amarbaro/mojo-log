# Design

Rule: format into one reused buffer, write once, allocate nothing per record.

## Layout

- `Field` is a register-passable struct of a borrowed key, a kind tag and one value. `*fields` costs no heap
  allocation, and a string value is a view into the caller's bytes.
- `Logger.buf` is cleared per record, never freed. One `write(2)` per record keeps lines whole when several
  loggers append to the same file (`O_APPEND`).
- The date part of the timestamp is rebuilt once a second (Hinnant civil-from-days); each record only
  appends microseconds.
- A disabled call returns at `lvl < self.level` before any formatting. 1M calls take 3 to 4 ms.

## Floats

`repr(float)` is the shortest digit string that reads back to the same double. `snprintf("%.*e")` plus
`strtod` finds it: start at 15 digits (always enough for a normal double), raise until the value reads back.
Then the digits are laid out as Python does (exponent form below 1e-4 and from 1e16). Gate: random bit
patterns, subnormals, 1e16, 5e-324, max double.

## System libs

- libc only for `write`, `open64`, `clock_gettime`, `snprintf`, `strtod`. `open` itself clashes with the
  stdlib's own declaration, hence `open64`.
- libsystemd is loaded with `OwnedDLHandle` when asked. Absent: `has_journal()` is False and logging
  continues to the other sink. No linker flag, no `-dev` package.

## Memory

Measured with `LD_PRELOAD` counting every malloc-family call and Mojo's own allocator entry
(`tools/allocs.c`); a loop that allocates a `List` per call is the control that proves the counter moves.
Peak RSS for 1M lines is 11 MB, of which the process baseline is most.
