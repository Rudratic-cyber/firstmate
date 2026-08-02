#!/usr/bin/env bash
# Behavior tests for cursor-agent harness detection (bin/fm-harness.sh).
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
  args=:4242) printf '/home/user/.local/bin/cursor-agent --force --trust\n' ;;
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
  pass "fm-harness: cursor-agent's MainThread comm is detected by ancestry via its args after env-marker precedence"
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

# tmux agent-process liveness for the cursor-agent comm (bin/backends/tmux.sh)
# is covered by tests/fm-secondmate-liveness.test.sh's
# test_tmux_agent_state_classifies, which now includes cursor-agent in its
# per-harness alive loop.

test_cursor_env_marker_precedence
test_cursor_detection_uses_mainthread_ancestry_after_markers
test_mainthread_without_cursor_agent_in_args_stays_unknown

echo "all fm-cursor-harness tests passed"
