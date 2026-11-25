#!/usr/bin/env bash
set -euo pipefail

# exit() terminates the whole OS process immediately (see DIAMOND_OP_EXIT,
# src/vm.c's exit_helper) -- it can never be exercised from tests/cases/*.d6,
# since build/run_cases runs its entire ~1000-case corpus in one shared
# process (tests/run_cases.c) and a real exit() there would kill the whole
# batch, not just this one case. Every assertion here goes through a real
# `diamond -e ...` subprocess instead, checking $? directly.
#
# `set -e` treats `var=$(cmd)` as a failing statement whenever cmd exits
# nonzero (which is the whole point here), so every such call below is
# wrapped in its own set +e / set -e pair rather than relying on the
# script-wide errexit.

diamond="$(realpath ./build/diamond)"
count=0
TMPDIR_EXIT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_EXIT"' EXIT

# --- exit(code) sets the process exit status, and halts before any
# later statement runs ---
set +e
out="$("$diamond" -e 'puts("before"); exit(5); puts("after")')"
status=$?
set -e
[[ "$status" == 5 ]]
[[ "$out" == "before" ]]
count=$((count + 1))

# --- exit() with no argument defaults to 0 ---
"$diamond" -e 'exit()' >/dev/null
count=$((count + 1))

# --- a rescued out-of-range code raises an ordinary, catchable
# ArgumentError -- it does NOT terminate the process; only a valid code
# (0..255) actually calls the real, unrescuable exit() ---
set +e
out="$("$diamond" -e '
begin
  exit(300)
rescue error: ArgumentError
  puts("caught: #{error.message()}")
end
exit(7)
')"
status=$?
set -e
[[ "$status" == 7 ]]
[[ "$out" == "caught: exit code must be between 0 and 255" ]]
count=$((count + 1))

# --- an uncaught out-of-range code still exits nonzero (an ordinary
# uncaught exception), distinct from the process-exit-code-7 case above ---
set +e
"$diamond" -e 'exit(300)' >/dev/null 2>/dev/null
status=$?
set -e
[[ "$status" != 0 ]]
[[ "$status" != 300 ]]
count=$((count + 1))

# --- a non-Int code raises TypeError (an uncaught exception, printed
# as "runtime error: <message>" -- an uncaught exception's own class
# name never appears in that text, only its message, so this checks
# exit_helper's actual message instead of the exception's class name) ---
set +e
error_output="$("$diamond" -e 'exit("nope")' 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]]
[[ "$error_output" == *"exit code must be an Int"* ]]
count=$((count + 1))

# --- an uncaught exception exits promptly even while a thread is still
# running: here the worker is blocked forever sending to a full channel
# nobody will drain, and joining it on teardown used to hang ---
blocked_worker='def fill(ch)
  loop do ch.send(1) end
end
ch = Channel.new(1)
worker = Thread.new(fill, ch)
raise ArgumentError.new("main failed")'
set +e
error_output="$(timeout 20 "$diamond" -e "$blocked_worker" 2>&1)"
status=$?
set -e
[[ "$status" == 70 ]]
[[ "$error_output" == *"main failed"* ]]
count=$((count + 1))

# --- ...and a failure with no thread left running still cleans up and
# exits normally ---
set +e
error_output="$("$diamond" -e 'def work() = 1
t = Thread.new(work)
t.join()
raise ArgumentError.new("after join")' 2>&1)"
status=$?
set -e
[[ "$status" == 70 ]]
[[ "$error_output" == *"after join"* ]]
count=$((count + 1))

# --- a thread that fails and is never joined reports its error on stderr
# instead of dropping it; the program's own output and exit status are
# unchanged ---
set +e
out="$("$diamond" -e 'def bad() = raise ArgumentError.new("lost worker")
Thread.new(bad)
puts("main done")' 2>"$TMPDIR_EXIT/err")"
status=$?
set -e
[[ "$status" == 0 ]]
[[ "$out" == "main done"* ]]
grep -q 'runtime error in unjoined thread: uncaught exception: ArgumentError: lost worker' "$TMPDIR_EXIT/err"
count=$((count + 1))

# --- ...also when the dropped handle is collected mid-program rather than
# at exit ---
"$diamond" -e 'def bad(i) = raise "dropped #{i}"
def spawn_some()
  (0...2).each() do |i| Thread.new(bad, i) end
  nil
end
spawn_some()
junk = []
(0...200000).each() do |i| junk.push("x#{i}") end' >/dev/null 2>"$TMPDIR_EXIT/err"
[[ "$(grep -c 'runtime error in unjoined thread' "$TMPDIR_EXIT/err")" == 2 ]]
count=$((count + 1))

# --- a joined failure is the joiner's to handle: no second report ---
"$diamond" -e 'def bad() = raise ArgumentError.new("seen")
begin
  Thread.new(bad).join()
rescue e: ArgumentError
  puts(e.message())
end' >/dev/null 2>"$TMPDIR_EXIT/err"
[[ ! -s "$TMPDIR_EXIT/err" ]]
count=$((count + 1))

# --- and an unjoined thread that succeeds stays silent ---
"$diamond" -e 'def ok() = 1
Thread.new(ok)' >/dev/null 2>"$TMPDIR_EXIT/err"
[[ ! -s "$TMPDIR_EXIT/err" ]]
count=$((count + 1))

# Dropping a thread handle must allow the parent to release the worker
# after a collection. Also exercise a finished parent with a live descendant.
for stress in DIAMOND_STRESS_GC DIAMOND_STRESS_MINOR_GC; do
    out="$(env "$stress=1" timeout -k 2 10 "$diamond" -e '
def worker(release)
  release.receive()
  puts("worker finished")
end
def start(release)
  Thread.new(worker, release)
  nil
end
def start_nested(release)
  Thread.new(start, release).join()
  nil
end
def supervise(release)
  sup = Supervisor.new()
  child = sup.add_child(start, release)
  while sup.alive?(child)
    sleep(0.001)
  end
  nil
end
def start_supervised(release)
  Thread.new(supervise, release).join()
  nil
end
release = Channel.new(1)
start(release)
junk = [0]
release.send(true)
start_nested(release)
junk = [1]
release.send(true)
start_supervised(release)
junk = [2]
release.send(true)
nil' 2>"$TMPDIR_EXIT/err")"
    [[ "$(sort <<<"$out")" == $'nil\nworker finished\nworker finished\nworker finished' ]]
    [[ ! -s "$TMPDIR_EXIT/err" ]]
    count=$((count + 1))
done

# A dropped Supervisor stops restarting without joining its current
# attempt in GC. Check direct collection and a deferred Supervisor in a
# finished Thread's VM. Normal shutdown must drain the last attempt.
for stress in DIAMOND_STRESS_GC DIAMOND_STRESS_MINOR_GC; do
    out="$(env "$stress=1" timeout -k 2 10 "$diamond" -e '
def worker(release)
  release.receive()
  puts("attempt finished")
  raise "do not restart after collection"
end
def start_supervisor(release)
  sup = Supervisor.new()
  sup.add_child(worker, release)
  nil
end
def start_nested(release)
  start_supervisor(release)
  junk = [0]
  nil
end
def launch_nested(release)
  Thread.new(start_nested, release).join()
  nil
end
release = Channel.new(1)
start_supervisor(release)
junk = [1]
release.send(true)
launch_nested(release)
junk = [2]
release.send(true)
nil' 2>"$TMPDIR_EXIT/err")"
    [[ "$(sort <<<"$out")" == $'attempt finished\nattempt finished\nnil' ]]
    [[ ! -s "$TMPDIR_EXIT/err" ]]
    count=$((count + 1))
done

echo "$count exit tests passed"
