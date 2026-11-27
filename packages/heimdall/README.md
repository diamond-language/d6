# heimdall

Accounts for d6 GraphQL apps built on `mjolnir`. It handles:

- passwords (bcrypt, with a 72-byte limit and timing that doesn't reveal
  which emails exist);
- bearer-token sessions;
- single-use email tokens for password reset and email verification;
- rate limits shared by every worker;
- a mail outbox;
- the `@auth` schema directive.

It works on SQLite and PostgreSQL, with integer or string ids.

`facet new graphql --auth` generates a working app wired to heimdall.

## Installation

```sh
facet add heimdall --registry https://cuts.rolld6.codes --version "^0.1.0"
facet install
```

```ruby
require_cut "heimdall"
```

## Tables

`Heimdall::Migrations.statements(dialect, id_type, session_tables)` returns
the `CREATE TABLE` statements. Run them in a migration. `dialect` is
`"sqlite"` or `"postgres"`. `id_type` is `:int` (ids the database assigns) or
`:string` (32 random hex characters made by Heimdall). `session_tables` maps
each sessions table to its accounts table:

```ruby
Heimdall::Migrations.statements("sqlite", :int, {"user_sessions": "users"}).each() do |sql|
  db.execute(sql)
end
```

The tables are:

| Table | Holds |
|---|---|
| one sessions table per kind of account | `owner_id`, `token_digest`, `expires_at`, `created_at` |
| `account_tokens` | reset and verify tokens: `kind`, `account_id`, `purpose`, `token_digest`, `expires_at` |
| `rate_limits` | `bucket`, `window_start`, `count` |
| `mail_outbox` | `to_address`, `subject`, `body`, `attempts`, `next_attempt_at` |

Your accounts table is your own. Heimdall needs its `id`, `email`,
`password_digest` and `email_verified_at` (epoch seconds, NULL until
verified) columns.

## Setup

```ruby
store = Heimdall::Store.new(Mjolnir::Repo.new(db), :int)
users = Mjolnir::Schema.new("users", {"id": :int, "email": :string, "handle": :string,
  "password_digest": :string, "email_verified_at": :int}, build_user)

mailer = Heimdall::Mailer.new(store, Heimdall::Mailer.command_sender("sendmail -t", "Ada <ada@example.com>"),
  logger: logger)
realm = Heimdall::Realm.new("user", users,
  Heimdall::Sessions.new(store, "user_sessions", "ust_"),
  Heimdall::AccountTokens.new(store), Heimdall::RateLimiter.new(store), mailer,
  app_name: "Ada", reset_url: "https://ada.example/reset?token={token}",
  verify_url: "https://ada.example/verify?token={token}")
```

Pass a nil sender to turn mail off. With the sender `:queue`, the mailer only
queues messages and another process delivers them, such as a timer job with
its own Mailer on the same table. `Mailer.log_sender(logger)` and
`Mailer.directory_sender(dir)` help in development. A sender is any function
that takes the outbox row and returns true once the message is handed off.
Call `mailer.deliver_due()` from a worker tick.

An app with several kinds of account builds one Realm per kind. Each needs its
own sessions table and token prefix; the realms share the rest. For example,
Pheint has developers (`pdt_`) and players (`ppt_`).

## Requests

Put the caller in the GraphQL context, and register the directive:

```ruby
context = {"principal": Heimdall.principal([realm], request["headers"]["authorization"]),
           "client_ip": Heimdall.client_address(request)}
app.directive("auth", Heimdall.directive(Heimdall.roles([realm])))
```

```graphql
directive @auth(as: Role!) on FIELD_DEFINITION
enum Role { ANY VERIFIED USER }

type Query { me: User! @auth(as: ANY) }
```

`Heimdall.roles` gives `ANY`, `VERIFIED`, and each realm's kind in capitals.
Add your own roles to the Hash it returns: each value is a function of the
context that raises to refuse.

In resolvers, `Heimdall.account!(context)` returns the signed-in account.
`Heimdall.verified!(context)` also requires a verified email.

## Flows

| Realm method | Does |
|---|---|
| `password_digest!(password)`, `email!(email)` | the checks for your sign-up mutation |
| `throttle_signup!(ip)` | 10 sign-ups an hour per address |
| `start_session(account)` | signs in an account you just created |
| `sign_in(email, password, ip)` | locks out after 10 failures per email, 5 per email and address, 30 per address, in 15 minutes |
| `change_password(account, current, new, keep_session)` | signs out every other session |
| `request_reset(email, ip)` / `reset_password(token, new, ip)` | always answers true; a reset signs out everywhere |
| `send_verification(account)`, `request_verification(account)`, `verify_email(token, ip)` | email verification |
| `request_verification_by_email(email, ip)` | resend verification before sign-in; always true, like `request_reset` |
| `delete_account(account, password) do ... end` | checks the password, runs your block, drops sessions and tokens |

Wrong reset and verify tokens count against the client address: 20 an hour.
To change a limit, pass `{"signin_fail_ip": [50, 900]}` to `RateLimiter.new`.
Add policies of your own the same way, and use them with `check_request!`.

Errors use `GraphQL::Fail.signal` with these codes: `UNAUTHENTICATED`,
`FORBIDDEN`, `RATE_LIMITED`, and `BAD_USER_INPUT` for invalid input. Pass
`invalid_code:` to `Realm.new` to use another code for invalid input.
