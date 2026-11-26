# websocket

Accept and exchange WebSocket frames on a live HTTP connection.

## Installation

From your project directory (see the [package guide](https://github.com/diamond-language/d6/blob/main/docs/packages.md) for `facet`):

```sh
facet init myapp          # once, if the project has no Cutfile yet
facet add websocket
facet install
```

This installs the cut into `cuts/websocket/`; load it with `require_cut "websocket"`.

## Usage

```ruby
require_cut "gremlin"
require_cut "websocket"

def handler(request, context)
  if request["path"] == "/echo" && websocket_upgrade_request?(request)
    return [403, {}, "cross-origin WebSocket refused"] unless websocket_origin_allowed?(request)
    ws = websocket_accept(request["gremlin_connection"], request)
    loop do
      message = ws.receive()
      if message == nil
        break   # the peer closed the connection or went away
      end
      ws.send_text(message["data"])   # echo it back
    end
    nil
  else
    [404, {"Content-Type": "text/plain"}, "not found"]
  end
end

gremlin_serve(8080, handler)
```

## A client

`websocket_connect` opens a connection to a `ws://` or `wss://` URL and returns the
same kind of connection, which masks what it sends as clients must:

```ruby
ws = websocket_connect("ws://127.0.0.1:8080/echo", {"Origin": "http://127.0.0.1:8080"})
ws.send_text("hello")
puts(ws.receive()["data"])
ws.close()
```

The second argument adds request headers (an `Origin`, a `Cookie`); a third is passed to
`TCPSocket.connect` or `TLSSocket.connect` for timeouts and CA files. It raises `IOError` if
the server does not answer the upgrade.

To share the handshake with a readiness-aware adapter, pass
`connector: connect_transport`, where the callable takes
`(host, port, tls, options)` and returns a connected stream. Retain that
stream if you need to poll it before `receive()`. The stream must fill
`read(n)` unless it reaches EOF, send the complete string on `write(bytes)`,
and release its resources on `close()`. An adapter for nonblocking sockets
handles readiness and partial I/O internally. It also owns TLS setup and
verification for `wss://` URLs.

## Notes

- Use a server that exposes the live connection in `request["gremlin_connection"]` (gremlin
  also sets `context["gremlin_connection"]`, but `context` is shared by every connection on
  the worker, so it names whichever request arrived last once your handler has waited for a
  frame). After `websocket_accept`, send and receive frames, then return `nil` from the HTTP
  handler.
- A browser sends cookies with a WebSocket upgrade but no CSRF token, so check
  `websocket_origin_allowed?(request)` first: the `Origin` must match the `Host` header, or
  be one of the origins you pass as a second argument. A request with no `Origin` (not a
  browser) passes.
- `receive` returns `nil` on a Close frame or EOF between frames. Read failures
  such as timeouts and resets propagate as errors. A partial frame or a protocol
  violation raises `IOError`.
- gremlin's `limits` do not time a WebSocket out: `websocket_accept` clears the request
  deadline.
