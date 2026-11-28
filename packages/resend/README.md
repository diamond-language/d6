# resend

Email for d6 apps through the [Resend](https://resend.com) HTTPS API. There is
no SMTP server to run and no mail queue on the host.

- `Resend.sender(api_key, from)` is a sender for `Heimdall::Mailer`, so an
  app on heimdall sends its verification and reset mail through Resend.
- `bin/resend-sendmail.d6` is a sendmail-compatible command (`-i -t`, message
  on stdin), for anything that already pipes mail to sendmail.
- `Resend.deliver(raw, api_key)` sends one RFC 5322 text/plain message.

Each message's SHA-256 is its `Idempotency-Key`, so a retried message is
delivered once.

## Installation

```sh
facet add resend --registry https://cuts.rolld6.codes --version "^0.1.0"
facet install
```

```ruby
require_cut "resend"
```

## With heimdall

```ruby
sender = Resend.sender(Resend.api_key(), "Example <accounts@mail.example.com>")
mailer = Heimdall::Mailer.new(store, sender, logger)
```

A failed send raises, so the mailer logs the reason and retries the message
with its usual backoff. The retry carries the same idempotency key.

## The API key

`Resend.api_key(path = nil)` reads, in order:

1. the file at `path`, when given;
2. the systemd credential `resend-api-key`
   (`$CREDENTIALS_DIRECTORY/resend-api-key`);
3. `RESEND_API_KEY`.

It raises `ArgumentError` when none is set. A systemd credential keeps the
key out of the environment and readable only by the service:

```ini
# /etc/systemd/system/<app>.service.d/resend.conf
[Service]
LoadCredential=resend-api-key:/etc/<app>/resend-api-key
```

Use a sending-only key scoped to the sending domain, in a root-owned 0600
file. To rotate it, replace the file atomically and restart the service.

## As a sendmail command

```sh
d6 cuts/resend/bin/resend-sendmail.d6 -i -t < message.eml
```

The key is found as above, with `RESEND_API_KEY_FILE` as the path.
`RESEND_URL` overrides the endpoint for testing. It exits 0 when Resend
accepted the message, 2 for a message it can't send, and 1 otherwise.

## Limits

Only single-part `text/plain` messages with one `To` address are sent: what
account mail needs. HTML, attachments and multiple recipients are refused
rather than half-sent.

## Testing

Send to Resend's `delivered@resend.dev` to test the key and domain without
reaching an inbox. `test.sh` runs the suite against a local stand-in for the
API.
