# d6 1.5.0

This release adds JSON stream processing and fixes block forwarding and
nonlocal exits found while building Quarry, a JSON processor written in d6.
Standalone binaries now support the same recursion depth as the interpreter.

## JSON and control flow

- `JSON.each(source)` yields values separated by whitespace, including JSON
  Lines. `JSON.parse_all(source)` collects the values into an Array. The
  runtime's remaining call-depth budget governs JSON nesting.
- Forwarded blocks bind to the callee's block parameter, so omitted defaulted
  arguments keep their defaults. A block's `break` resumes after keyword and
  spread calls, including calls through a Callable and to a constructor.
- A struct can extend a class with no fields or initializer. Exhaustiveness
  checks cover sealed classes with up to 256 direct subclasses.

## Files, numbers, and strings

- `File.touch` creates a file or sets its modification time. `Dir.pwd` returns
  the working directory, and `Dir.glob` accepts `hidden: true`.
- `Zlib.deflate` and `Zlib.inflate` support zlib-wrapped compressed data.
- Integers gain the same rounding and numeric predicates as floats.
- String character operations count malformed UTF-8 bytes individually.
- The compiler warns on more uses of a bare method reference where a call
  was intended, and on copies discarded at the end of iterator blocks.

## Cuts

- HTTP 0.2.9 fixes relative redirects with fragment-only and query-only
  locations. It supports d6 1.4.0 and later.
- The cancellation 0.7.2 cut is available through `facet add cancellation`.
