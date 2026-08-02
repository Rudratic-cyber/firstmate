#!/usr/bin/env bash
# Behavior tests for agy (Antigravity CLI) harness detection (bin/fm-harness.sh).
#
# agy's own env marker (ANTIGRAVITY_AGENT=1) is set only for its child/tool
# processes, not the top-level agy process itself - the same
# child-process-marker shape as GROK_AGENT/CURSOR_AGENT, verified live. Unlike
# cursor-agent, agy's own top-level process comm is the clean literal "agy"
# (verified via `ps -o comm=` and tmux's `#{pane_current_command}`), so
# ancestry detection needs no MainThread-style special case.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot fm-antigravity-harness)

test_antigravity_env_marker_precedence() {
  local out
  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT ANTIGRAVITY_AGENT=1 \
    PATH="$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = antigravity ] || fail "ANTIGRAVITY_AGENT=1 should detect antigravity, got '$out'"

  # A higher-precedence marker must still win over ANTIGRAVITY_AGENT, matching
  # the documented Layer-1 ordering (claude, pi, grok, cursor, then antigravity).
  out=$(CLAUDECODE=1 ANTIGRAVITY_AGENT=1 PATH="$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = claude ] || fail "CLAUDECODE=1 must outrank ANTIGRAVITY_AGENT=1, got '$out'"
  pass "fm-harness: ANTIGRAVITY_AGENT=1 is detected at the documented Layer-1 precedence"
}

test_antigravity_detection_uses_agy_comm_ancestry() {
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
  comm=:4242) printf 'agy\n' ;;
  comm=:*) printf '/bin/bash\n' ;;
  ppid=:4242) printf '1\n' ;;
  ppid=:*) printf '4242\n' ;;
esac
SH
  chmod +x "$fakebin/ps"

  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u CURSOR_AGENT -u ANTIGRAVITY_AGENT \
    PATH="$fakebin:$BASE_PATH" "$ROOT/bin/fm-harness.sh")
  [ "$out" = antigravity ] || fail "agy comm ancestry detection returned '$out'"
  pass "fm-harness: agy's own clean 'agy' comm is detected by ancestry after env-marker precedence"
}

# tmux agent-process liveness for the agy comm (bin/backends/tmux.sh) is
# covered by tests/fm-secondmate-liveness.test.sh's
# test_tmux_agent_state_classifies, which now includes agy in its per-harness
# alive loop.

test_antigravity_env_marker_precedence
test_antigravity_detection_uses_agy_comm_ancestry

echo "all fm-antigravity-harness tests passed"
