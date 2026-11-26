# d6 1.7.0

d6 1.7 adds reusable PostgreSQL and MySQL statements, new transport hooks for
HTTP and WebSocket clients, and opt-in keep-alive and timing events in Gremlin.

## Serve HTTP with Gremlin

Enable `keep_alive: true` to serve successive HTTP/1.1 requests on one connection.
Each request gets a fresh deadline and request ID. Idle connections expire, and
Gremlin closes each connection after at most 100 requests. Gremlin also gives
periodic ticks a turn during HTTP bursts.

Pass `on_event:` to observe completed HTTP responses and periodic ticks. Measure
request time from `parse_started_at` to `response_finished_at`. Measure tick lag
from `scheduled_at` to `started_at`. See [Gremlin HTTP and timing](networking.md#gremlin-http-and-timing)
for a server example.

## Use your own client transport

Supply an HTTP connector through the request or session options, or a WebSocket
connector through the `connector:` keyword. The application adapter can yield
while it waits for socket readiness. The cuts still handle HTTP framing and the
WebSocket handshake and frames. The adapter owns TLS setup and certificate
verification.

HTTP sessions retry GET, HEAD, OPTIONS, and TRACE once after an I/O failure on
a reused connection. A POST can already have committed when a response fails.
Choose `"retry_stale" => "always"` only when replay is safe.
[Client transport reference](networking.md#http-and-websocket-client-transports)

## Reuse database statements

Save a statement from `db.prepare(sql)` and call `query(params)` or
`execute(params)` repeatedly with fresh positional values. Close the statement
when finished. Each statement belongs to its connection and becomes unusable
when that connection closes. Arel 0.35.7 can use native statements in its
statement cache. [Prepared statement example](databases.md#reusable-postgresql-and-mysql-statements)

## Cut versions

| Cut | Version |
|---|---|
| Arel | 0.35.7 |
| HTTP | 0.2.12 |
| Gremlin | 0.5.11 |
| WebSocket | 0.2.6 |

## Runtime fixes

An unreachable [Supervisor](threads.md#supervisors) stops restarting children
and lets its current attempts finish without blocking garbage collection.
WebSocket frame reads preserve transport errors and distinguish them from clean
EOF.

[Release and downloads](https://github.com/diamond-language/d6/releases/tag/v1.7.0)
