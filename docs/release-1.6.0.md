# d6 1.6.0 and 1.6.1

d6 1.6 adds reusable type aliases, typed variadic parameters, and a way to
poll channels alongside sockets.

## Language and concurrency

- Declare a [type alias](types-and-errors.md#type-aliases) at program scope
  with `type Name = Type`. An alias can name a union or be used as a type argument.
- Annotate a [variadic parameter](callables.md#variadic-parameters) with
  its element type, such as `*names: String`. d6 checks extra arguments from
  ordinary calls and spreads and gives the body an `Array[String]`.
- [`IO.poll`](networking.md#wait-for-sockets-and-channels-together) accepts
  channels and sockets in the same readiness lists. Readiness observes a
  value, available capacity, or closure without consuming or reserving anything.
- [Array and hash literals](collections.md) support up to 512 entries.
  A [function](core-syntax.md) can use up to 128 named locals including parameters.
  Generated functions have more room for temporary registers.

## Runtime and tools

- `Time#iso8601` preserves the requested decimal precision when formatting
  parsed fractions and pads years such as `0001`. UTC and fixed-offset calendar
  conversions support years before 1900 on macOS.
- Standalone builds refresh cached runtime objects when their inputs change
  content, including inputs restored with older modification times.
- Facet's top-level help lists the `graphql` starter.

## 1.6.1 patch release

The live-thread-limit regression test keeps child handles alive through the
release signal. This prevents the test from getting stuck in garbage
collection while it waits for a worker to report.

[Release and downloads](https://github.com/diamond-language/d6/releases/tag/v1.6.1)
