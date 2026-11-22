# terminal

Building blocks for full-screen terminal programs: key names from raw input,
text fitted to screen columns, and a screen that redraws only what changed.
Needs d6 1.4.0 or later.

```ruby
require_cut "terminal"

keys = Terminal::Keys.new()
Terminal::Screen.open() do |screen|
  loop do
    rows, columns = screen.size()
    screen.draw([Terminal::Cells.fit(" press q to quit", columns)] +
      Array.new(rows - 1, " " * columns))
    bytes = screen.read(200)
    break if bytes == nil
    pressed = bytes.empty?() && keys.pending?() ? keys.flush() : keys.feed(bytes)
    break if pressed.include?("q")
  end
end
```

## Terminal::Keys

`feed(bytes)` returns the keys in the bytes read so far: `"a"`, `"日"`,
`"enter"`, `"tab"`, `"backspace"`, `"escape"`, `"ctrl-c"`, `"up"`, `"down"`,
`"left"`, `"right"`, `"home"`, `"end"`, `"insert"`, `"delete"`, `"page-up"`,
`"page-down"` and `"shift-tab"`. A key split across reads waits for the rest.
Alt with a key arrives as `"escape"` and then the key.

A lone ESC could be the start of a sequence, so it waits too. When a read
comes back empty and `pending?` is true, call `flush`: the ESC becomes
`"escape"`.

## Terminal::Cells

- `Terminal::Cells.fit(text, width)` cuts or pads `text` to exactly `width`
  columns, ending cut text in "…".
- `Terminal::Cells.wrap(text, width)` breaks `text` into lines no wider than
  `width`, at spaces where it can.

Both count columns with `String#display_width`, so wide characters such as 日
and emoji line up.

## Terminal::Screen

- `Terminal::Screen.open() do |screen| ... end` runs the block in raw mode on
  the alternate screen, and restores the terminal however the block ends.
  It raises `IOError` when standard input is not a terminal.
- `size()` is `[rows, columns]`.
- `read(wait)` returns the bytes that arrive within `wait` milliseconds: `""`
  if none do, `nil` when the terminal has gone away.
- `draw(lines)` draws one line per row, sending only the rows that changed.
  Each line should fill its row: `Cells.fit` makes that easy.
- `clear()` makes the next `draw` repaint everything, as after a resize.
- `write(text)` sends `text` as it is, for escape sequences of your own.

To wait on a socket as well as the keyboard, skip `read` and pass `STDIN` to
`IO.poll` next to the socket, then read the keys with `STDIN.readpartial(64)`.
To redraw on resize, trap the `WINCH` signal and call `clear` before the next
draw.

## Testing

`bash test.sh` checks the key decoding and text fitting. Run whatever uses
`Screen` by hand in a real terminal, or in tmux (`tmux send-keys` and
`tmux capture-pane`).
