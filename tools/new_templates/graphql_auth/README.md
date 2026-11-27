# {{name}}

A GraphQL API with accounts, written in [d6](https://rolld6.codes). It is built
schema-first with `GraphQL::App` and served by gremlin. Accounts use
[heimdall](https://github.com/diamond-language/d6/tree/main/packages/heimdall),
and data lives in SQLite through mjolnir.

```sh
facet install              # fetch the cuts into cuts/
d6 main.d6                 # http://127.0.0.1:8080/graphql
bash test.sh               # run the tests
```

Try it:

```sh
curl -s localhost:8080/graphql -H 'content-type: application/json' \
  -d '{"query": "mutation { signUp(email: \"ada@example.com\", name: \"Ada\", password: \"correct horse\") { token } }"}'
curl -s localhost:8080/graphql -H 'content-type: application/json' -H "authorization: Bearer $TOKEN" \
  -d '{"query": "{ me { name emailVerified } }"}'
```

The verification message prints in the server log. Pass its token to
`verifyEmail`, and then `addNote` works.

## Accounts

heimdall handles each part of sign-in:

- **Passwords:** bcrypt; 8 characters to 72 bytes.
- **Sessions:** bearer tokens starting `ust_`. Only their SHA-256 is stored, and
  they expire after 30 days.
- **Lockouts:** sign-in locks out after repeated failures per email, per
  address, and per email and address together. Sign-ups, reset requests and
  wrong tokens are rate-limited too.
- **Password reset:** the token works once and expires in an hour. A reset signs
  out every session, and changing the password signs out every other session.
- **Email verification:** the token lasts three days.
- **Privacy:** answers never reveal whether an email is registered.

`@auth(as: ANY)` in the schema requires a signed-in caller, and
`@auth(as: VERIFIED)` also requires a verified email.

## Settings

| Variable | Does |
|---|---|
| `PORT`, `HOST` | the address (default `127.0.0.1:8080`, reachable only from this machine) |
| `DATABASE` | the SQLite file (default `{{name}}.sqlite3`) |
| `MAIL_COMMAND`, `MAIL_FROM` | send mail through a sendmail-style command, such as `sendmail -t` |
| `RESET_URL`, `VERIFY_URL` | links to put in messages, with `{token}` where the token goes |
| `TRUST_PROXY=1` | rate-limit by `X-Forwarded-For`; set it only behind a proxy that overwrites it |

## Files

- `lib/schema.graphql` is the API. `File.embed` compiles it into the program.
- `lib/{{name}}.d6` holds the migrations, the resolvers (one method per field, named
  in snake_case), and the HTTP routes: `POST /graphql`, `GET /schema.graphql`,
  and `GET /health`.
- `test/{{name}}_test.d6` posts queries to the handler with an in-memory database,
  so the tests start no server.

`facet install` writes `Cutfile.lock`; commit it so every checkout gets the same versions.
