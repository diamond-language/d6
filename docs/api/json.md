# JSON

[API reference](index.md) · Previous: [Math](math.md) · Next: [URI](uri.md)

`JSON` converts between d6 values and JSON text. Objects become Hashes with
String keys, arrays become Arrays, `null` becomes `nil`, and numbers become an
`Int` or a `Float`.

```ruby
data = JSON.parse("{\"name\": \"Ada\", \"tags\": [1, 2]}")
data["tags"]            # => [1, 2]
JSON.stringify(data)    # => "{\"name\":\"Ada\",\"tags\":[1,2]}"
```

## Functions

### `JSON.each(source) do |value| ... end -> Nil`

Calls the block with each value of `source`, a stream of JSON values separated
by whitespace, such as JSON Lines. Values before any invalid text reach the
block before `JSONError` is raised.

```ruby
JSON.each("1 [2, 3]\n{\"a\": 4}") do |value| p(value) end
# => 1
# => [2, 3]
# => {"a": 4}
```

### `JSON.parse(source) -> Value`

The value `source` describes. Text that is not valid JSON raises `JSONError`,
and so does nesting deeper than the program can recurse (about 9,600 levels in
the main program, 150 in a fiber or thread).

```ruby
JSON.parse("{\"a\": [1, 2.5, null, true]}")   # => {"a": [1, 2.5, nil, true]}
JSON.parse("3")                                # => 3
```

### `JSON.parse_all(source) -> Array`

Every value of a stream like `JSON.each`'s, in an Array.

```ruby
JSON.parse_all("true null 2.5")   # => [true, nil, 2.5]
```

### `JSON.stringify(value, options = nil) -> String`

`value` as compact JSON. `options` is a Hash: `"indent"` (a number of spaces,
or a String of whitespace) lays the text out over several lines, and
`"sort_keys"` (`true`) writes each Hash's keys in sorted order. Strings,
numbers, `true`, `false`, `nil`, Arrays and Hashes convert, and Hash keys are
written as strings (`{1: 2}` gives `{"1":2}`). Any other value, such as a
Symbol or an object, and a `NaN` or infinite Float raise `JSONError`.

```ruby
JSON.stringify([1, "a", nil])                                        # => "[1,\"a\",null]"
puts(JSON.stringify({"b": 1, "a": 2}, {"indent": 2, "sort_keys": true}))
```
