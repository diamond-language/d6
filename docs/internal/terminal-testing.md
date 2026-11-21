# Testing the terminal methods

`STDIN.raw`, `STDOUT.winsize` and `STDIN.readpartial` in raw mode need a real
terminal, which CI does not have. `tests/run.sh` covers what works without
one (tests/terminal/streams_without_terminal.d6). Check raw mode by hand
with tmux, which gives the program a pseudo-terminal you can type into and read
back:

```sh
tmux -L d6term new-session -d -x 100 -y 30 \
  "build/diamond tests/terminal/raw_mode_by_hand.d6; echo EXITED=\$?; stty -a | grep -o -- '-\?echo \|-\?icanon'; sleep 30"
sleep 1
tmux -L d6term send-keys a;  sleep 0.3
tmux -L d6term send-keys Up; sleep 0.3
tmux -L d6term resize-window -x 70 -y 20; sleep 0.5
tmux -L d6term send-keys C-c; sleep 0.3
tmux -L d6term send-keys -l "日"; sleep 1
tmux -L d6term capture-pane -p
tmux -L d6term kill-server
```

Expected:

```
size [30, 100]
keys [[97], [27, 91, 65], [3], [230, 151, 165]] resizes 1 size [20, 70]
EXITED=3
icanon
echo
```

Each key is one read (the arrow's three bytes together, Ctrl-C as byte 3
instead of an interrupt), the resize ran the WINCH handler, and `icanon` and
`echo` without a leading `-` show the terminal was restored although the
program exited inside the raw block.
