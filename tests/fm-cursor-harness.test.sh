#!/usr/bin/env bash
# Behavior tests for cursor-agent harness identity (bin/fm-harness.sh detection
# and bin/fm-session-lock-lib.sh session-lock ancestry/liveness).
#
# cursor-agent's own env marker (CURSOR_AGENT=1) is set only for its
# child/tool processes, not the top-level cursor-agent process itself - the
# same child-process-marker shape as GROK_AGENT, verified live. Its process
# ancestry is also unusual: `ps -o comm=` for the cursor-agent process itself
# reports the literal string "MainThread" (a Node runtime-thread-naming
# quirk), not "cursor-agent" or "node", so the bare-interpreter args fallback
# needs its own case entry alongside node*/python*.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot fm-cursor-harness)

test_cursor_env_marker_precedence() {
  local out
  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT CURSOR_AGENT=1 \
    PATH="$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = cursor ] || fail "CURSOR_AGENT=1 should detect cursor, got '$out'"

  # A higher-precedence marker must still win over CURSOR_AGENT, matching the
  # documented Layer-1 ordering (claude, pi, grok, then cursor).
  out=$(CLAUDECODE=1 CURSOR_AGENT=1 PATH="$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = claude ] || fail "CLAUDECODE=1 must outrank CURSOR_AGENT=1, got '$out'"
  pass "fm-harness: CURSOR_AGENT=1 is detected at the documented Layer-1 precedence"
}

test_cursor_detection_uses_mainthread_ancestry_after_markers() {
  local dir fakebin out
  dir="$TMP_ROOT/detection"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  comm=:4242) printf 'MainThread\n' ;;
  args=:4242) printf '%s\n' '/home/user/.local/bin/cursor-agent --force --trust --model claude-opus-5-thinking-high you are a firstmate crewmate; port the grok and codex adapter notes' ;;
  comm=:*) printf '/bin/bash\n' ;;
  ppid=:4242) printf '1\n' ;;
  ppid=:*) printf '4242\n' ;;
  args=:*) printf 'bash\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = cursor ] || fail "cursor MainThread+args ancestry detection returned '$out'"
  pass "fm-harness: cursor-agent's MainThread comm is detected by ancestry via its args, even when the launch template's --model id and brief name other harnesses"
}

test_mainthread_without_cursor_agent_in_args_stays_unknown() {
  local dir fakebin out
  dir="$TMP_ROOT/mainthread-other"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  comm=:4242) printf 'MainThread\n' ;;
  args=:4242) printf '/usr/bin/node /opt/some-other-tool/index.js\n' ;;
  comm=:*) printf '/bin/bash\n' ;;
  ppid=:4242) printf '1\n' ;;
  ppid=:*) printf '4242\n' ;;
  args=:*) printf 'bash\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = unknown ] || fail "an unrelated MainThread process must not be misdetected as cursor, got '$out'"
  pass "fm-harness: a MainThread process without cursor-agent in its args stays unknown, never guessed"
}

# The test above uses a neutral argv, so it stays green even when the cursor
# arm shares the node*/python* case label and falls through to that case's
# generic patterns. This one isolates that fall-through: a MainThread hop whose
# argv NAMES an existing harness. Before cursor existed the MainThread comm
# matched no arm at all and this answered "unknown"; a shared label answers
# "claude" - a non-additive change to an already-verified adapter's detection.
test_mainthread_naming_another_harness_does_not_leak_into_that_adapter() {
  local dir fakebin out
  dir="$TMP_ROOT/mainthread-names-claude"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  comm=:4242) printf 'MainThread\n' ;;
  args=:4242) printf '%s\n' '/usr/bin/node /opt/claude/cli.js --print hello' ;;
  comm=:*) printf '/bin/bash\n' ;;
  ppid=:4242) printf '1\n' ;;
  ppid=:*) printf '4242\n' ;;
  args=:*) printf 'bash\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = unknown ] \
    || fail "a non-cursor MainThread process must not fall through to the bare-interpreter argv patterns, got '$out'"
  pass "fm-harness: the cursor MainThread arm matches cursor or nothing, so it cannot leak a MainThread process into an existing adapter"
}

# The mirror of the test above, guarding the opposite over-correction: the
# dedicated MainThread arm must not RETURN unknown when it fails to match, it
# must fall out of the case and let the ancestry walk continue - which is
# exactly what the comm did before cursor existed.
test_non_cursor_mainthread_does_not_halt_the_ancestry_walk() {
  local dir fakebin out
  dir="$TMP_ROOT/mainthread-walk-continues"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  # 4242: a MainThread hop that is not cursor-agent.
  comm=:4242) printf 'MainThread\n' ;;
  args=:4242) printf '/usr/bin/node /opt/some-other-tool/index.js\n' ;;
  ppid=:4242) printf '4343\n' ;;
  # 4343: the real harness, one hop above.
  comm=:4343) printf 'claude\n' ;;
  args=:4343) printf 'claude\n' ;;
  ppid=:4343) printf '1\n' ;;
  comm=:*) printf '/bin/bash\n' ;;
  args=:*) printf 'bash\n' ;;
  ppid=:*) printf '4242\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = claude ] \
    || fail "an unmatched MainThread hop must not halt the walk before the real claude harness above it, got '$out'"
  pass "fm-harness: an unmatched MainThread hop leaves the ancestry walk running, exactly as before cursor existed"
}

test_bare_node_ancestry_order_is_unchanged() {
  local dir fakebin out
  dir="$TMP_ROOT/bare-node"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  comm=:4242) printf 'node\n' ;;
  args=:4242) printf '%s\n' '/usr/bin/node /opt/claude/cli.js --print port the cursor-agent adapter' ;;
  comm=:*) printf '/bin/bash\n' ;;
  ppid=:4242) printf '1\n' ;;
  ppid=:*) printf '4242\n' ;;
  args=:*) printf 'bash\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = claude ] || fail "a bare-node claude process must still detect claude, got '$out'"
  pass "fm-harness: the cursor arm is gated on the MainThread comm, so bare node*/python* ancestry order is unchanged"
}

# The test above shares its fixture's argv between "claude" and "cursor-agent",
# so the claude arm wins on ordering alone and it passes whether or not a cursor
# arm exists in the shared node*/python* argv case. This one isolates the arm:
# the node hop names cursor-agent and NO other harness, with the real claude
# harness one hop above it. A cursor arm in the shared case makes the node hop
# answer "cursor" and never reach claude - the exact non-additive regression.
test_node_ancestry_naming_cursor_agent_does_not_shadow_the_real_harness() {
  local dir fakebin out
  dir="$TMP_ROOT/node-names-cursor"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  # 4242: a bare node hop whose argv mentions cursor-agent and no other harness.
  comm=:4242) printf 'node\n' ;;
  args=:4242) printf '%s\n' '/usr/bin/node /opt/tool/index.js --brief port the cursor-agent adapter' ;;
  ppid=:4242) printf '4343\n' ;;
  # 4343: the real harness, one hop above.
  comm=:4343) printf 'claude\n' ;;
  args=:4343) printf 'claude\n' ;;
  ppid=:4343) printf '1\n' ;;
  comm=:*) printf '/bin/bash\n' ;;
  args=:*) printf 'bash\n' ;;
  ppid=:*) printf '4242\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = claude ] \
    || fail "a node hop merely naming cursor-agent must not shadow the real claude harness above it, got '$out'"
  pass "fm-harness: adding cursor left the shared node*/python* argv case behavior-identical for existing adapters"
}

# A secondmate runs its own primary firstmate session, so it must acquire its
# own home's session lock through bin/fm-session-lock-lib.sh. That owner keys
# on `ps -o comm=`, which for cursor-agent is `MainThread` and matches no
# FM_HARNESS_RE alternative, so without its own identity a cursor secondmate
# fails lock acquisition and degrades to a permanently READ-ONLY session.
test_session_lock_identity_resolves_cursor_agent() {
  local dir fakebin got
  dir="$TMP_ROOT/session-lock"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  # 4242: the cursor-agent process itself, whose --model id names claude.
  comm=:4242) printf 'MainThread\n' ;;
  args=:4242) printf '%s\n' '/home/user/.local/bin/cursor-agent --force --trust --model claude-opus-5-thinking-high you are a firstmate secondmate' ;;
  ppid=:4242) printf '4343\n' ;;
  # 4343: an unrelated claude harness further up the real process tree.
  comm=:4343) printf 'claude\n' ;;
  args=:4343) printf 'claude\n' ;;
  ppid=:4343) printf '1\n' ;;
  comm=:*) printf '/bin/bash\n' ;;
  args=:*) printf 'bash\n' ;;
  ppid=:*) printf '4242\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  got=$(PATH="$fakebin:$BASE_PATH" bash -c \
    '. "$0/bin/fm-session-lock-lib.sh"; fm_harness_ancestry_pid' "$ROOT")
  [ "$got" = 4242 ] \
    || fail "session-lock ancestry selected '$got', expected the cursor-agent pid 4242 (a claude-named --model id must not extend the walk)"
  PATH="$fakebin:$BASE_PATH" bash -c \
    '. "$0/bin/fm-session-lock-lib.sh"; kill() { return 0; }; fm_harness_pid_alive 4242' "$ROOT" \
    || fail "session-lock liveness rejected a live cursor-agent lock holder"
  pass "session lock: cursor-agent's MainThread comm resolves as its own harness identity, first match wins"
}

test_session_lock_identity_stays_scoped_to_cursor_agent() {
  local dir fakebin got
  dir="$TMP_ROOT/session-lock-scope"
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && field=$arg
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
case "$field:$pid" in
  # 4242: a bare node hop whose argv merely NAMES cursor-agent.
  comm=:4242) printf 'node\n' ;;
  args=:4242) printf '%s\n' '/usr/bin/node /opt/tool/index.js --brief port the cursor-agent adapter' ;;
  ppid=:4242) printf '4343\n' ;;
  # 4343: an unrelated MainThread process that is not cursor-agent.
  comm=:4343) printf 'MainThread\n' ;;
  args=:4343) printf '/usr/bin/node /opt/some-other-tool/index.js\n' ;;
  ppid=:4343) printf '1\n' ;;
  comm=:*) printf '/bin/bash\n' ;;
  args=:*) printf 'bash\n' ;;
  ppid=:*) printf '4242\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  if got=$(PATH="$fakebin:$BASE_PATH" bash -c \
    '. "$0/bin/fm-session-lock-lib.sh"; fm_harness_ancestry_pid' "$ROOT"); then
    fail "session-lock ancestry resolved '$got' from processes that merely name cursor-agent"
  fi
  if PATH="$fakebin:$BASE_PATH" bash -c \
    '. "$0/bin/fm-session-lock-lib.sh"; kill() { return 0; }; fm_harness_pid_alive 4242' "$ROOT"; then
    fail "session-lock liveness accepted a node process that only names cursor-agent in its argv"
  fi
  if PATH="$fakebin:$BASE_PATH" bash -c \
    '. "$0/bin/fm-session-lock-lib.sh"; kill() { return 0; }; fm_harness_pid_alive 4343' "$ROOT"; then
    fail "session-lock liveness accepted an unrelated MainThread process as cursor-agent"
  fi
  pass "session lock: the cursor identity stays gated on MainThread + cursor-agent argv, so no existing adapter's result changes"
}

# tmux agent-process liveness for the cursor-agent comm (bin/backends/tmux.sh)
# is covered by tests/fm-secondmate-liveness.test.sh's
# test_tmux_agent_state_classifies, which now includes cursor-agent in its
# per-harness alive loop.

test_cursor_env_marker_precedence
test_cursor_detection_uses_mainthread_ancestry_after_markers
test_mainthread_without_cursor_agent_in_args_stays_unknown
test_mainthread_naming_another_harness_does_not_leak_into_that_adapter
test_non_cursor_mainthread_does_not_halt_the_ancestry_walk
test_bare_node_ancestry_order_is_unchanged
test_node_ancestry_naming_cursor_agent_does_not_shadow_the_real_harness
test_session_lock_identity_resolves_cursor_agent
test_session_lock_identity_stays_scoped_to_cursor_agent

echo "all fm-cursor-harness tests passed"
