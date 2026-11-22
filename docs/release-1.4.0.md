# d6 1.4.0

1.4.0 adds what five small applications ran short of: a static site generator, a process
supervisor, a log follower, a terminal kanban board and an IRC server with a full-screen client.
It is the first minor release with a breaking change, under the
[compatibility policy](compatibility.md) as it now reads: Strings count characters, not bytes.

## Breaking: Strings count characters

`length`, `size`, `slice`, `s[i]`, `s[range]`, `index`, `index_of`, `rindex`, `insert`,
`chars`, `each_char`, `reverse`, `ljust`, `rjust`, `center`, `split("")`, `tr`, `%s` widths in
`format` and `MatchData` offsets count UTF-8 characters, so `"日本".length()` is 2 (it was 6) and
`reverse` no longer breaks multi-byte text. A byte that isn't valid UTF-8 counts as one
character. ASCII-only Strings run as fast as before: the character count is worked out once and
kept with the String.

Code that treats a String as bytes, such as a binary format, a wire protocol or a
`Content-Length`, should use the byte methods:

| For | Use |
|---|---|
| a length in bytes | `bytesize` (now native), `StringBuilder#bytesize` (new) |
| a run of bytes | `byteslice(start, length)` (new) |
| one byte | `getbyte(i)`, `bytes`, `each_byte` |

Text that is all ASCII gives the same results either way. The cuts that counted bytes with
`length` were fixed and now say they need d6 1.4.0 (see below), so a project on 1.3 keeps the
releases it has.

New alongside: `String#display_width` counts terminal columns, with East Asian wide characters
and emoji as two and combining marks as none.

## Full-screen terminal programs

- `STDIN.raw() do ... end` runs the block in raw mode and restores the terminal however it ends.
  `STDIN.readpartial(n)` returns the bytes that have arrived, which in raw mode is a keypress.
- `STDOUT.winsize()` is `[rows, columns]`, and `Signal.trap("WINCH", handler)` hears resizes.
- `IO.poll` takes `STDIN` next to sockets, so one loop can wait on the keyboard and the network.
- The new `terminal` cut builds on these: key names from raw input (`Terminal::Keys`), text fitted
  and wrapped to columns (`Terminal::Cells`), and a screen that redraws only the lines that
  changed (`Terminal::Screen`)
  ([README](https://github.com/diamond-language/d6/blob/main/packages/terminal/README.md)).

## Nonblocking TLS

One thread can now serve TLS connections alongside everything else it waits on.
`TLSSocket.start_handshake(socket, host, {"nonblocking" => true})` keeps the socket nonblocking
after its handshake, and `TLSServer.listen(port, cert, key, {"nonblocking" => true})` accepts
connections whose handshake you finish with `finish_handshake`. On these sockets `read(n)` and
`write(text)` take what is ready and raise `WouldBlockError` otherwise, and `IO.poll` counts
bytes OpenSSL has already read as readable ([networking](api/network.md#nonblocking-tls)).
`TLSServer.listen` also takes `"host"`, and `TLSSocket#peer_address` is new.

## Syntax

- An assignment in parentheses is an expression: `while (line = file.gets()) != nil`. Without
  the parentheses, `if x = value` is an error that says to add them or to write `==`.
- Compound assignment through an attribute: `counter.count += 1`, `job.label ||= "x"`.
- An endless def can assign: `def reset() = @count = 0`.
- `puts`, `print` and `warn` take several arguments.
- `x.is_a?(T)` narrows `x` the way `x is T` does, and `block.call(x)` works as Ruby's
  `Proc#call` does.

## Warnings

d6 now prints compile warnings, and the LSP shows them. A warning never stops a program. The
first two catch:

- a line that only calls `concat`, `sort`, `reverse`, `uniq`, `compact`, `take` or `drop` on an
  Array and throws the result away (Ruby's `concat` appends in place; d6's returns a new Array);
- a method reference (`box.label` without parentheses) compared with `nil`, used as a condition
  or interpolated, which is almost always a missing `()`.

## Files and processes

- `Dir.glob(pattern)`, `File.mtime(path)`, and `File.join` with Arrays of parts.
- `File#pos` and `File#seek(offset)`. Reading a file that has reached its end tries again, so a
  program can follow a log as another process appends to it.
- `Process.spawn(argv, {"process_group": true})` starts the child in its own process group, and
  stopping that child stops everything it started.
- `require_cut` falls back to the `cuts/` of the entry file's project, so `d6 ~/tools/app/main.d6`
  runs from any directory.

## Projects and cuts

- A cut's `Cutfile` can name the d6 versions it works with: `"d6": ">=1.4.0"`. facet won't install
  it on a d6 outside that range, and the registry gives an older d6 the cut's last release that
  works for it ([cut contract](cut-contract.md)).
- `facet add` takes several names.
- New cuts on [cuts.rolld6.codes](https://cuts.rolld6.codes): `terminal` 0.1.0, `markdown` 0.1.0
  (the renderer the documentation site uses) and `mustache` 0.1.0.
- Updated for character Strings, needing 1.4.0: cookies 0.2.7, csv 0.1.1, div 0.3.4,
  gremlin 0.5.8, html 0.1.1, http 0.2.8, redis 0.2.5, registry 0.3.3, toml 0.1.2 and
  websocket 0.2.5. graphql 0.3.7 updates its example to match.

The [changelog](https://github.com/diamond-language/d6/blob/main/CHANGELOG.md) lists every fix,
including the clearer errors for Ruby brace blocks, `loop` as a variable and name clashes.

## Installing

[Getting started](getting-started.md#1-install) compares the ways to install d6. Packages
and tarballs are on the [release page](https://github.com/diamond-language/d6/releases/tag/v1.4.0).
