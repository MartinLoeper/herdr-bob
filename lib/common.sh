# Shared helpers. Sourced by every bin/ script.
#
# Note the two very different callers:
#   - Herdr runs bin/bob-start, bin/bob-watch* and bin/bob-*install-hook, so those
#     get HERDR_PLUGIN_* in the environment.
#   - *Bob* runs bin/bob-hook, so it gets only what the pane inherited
#     (HERDR_ENV, HERDR_PANE_ID, HERDR_BIN_PATH). It must be told its state
#     directory on the command line; bob-install-hook bakes that in.

PLUGIN_ID="mloeper.herdr-bob"
AGENT_LABEL="bob"
SOURCE_ID="plugin:${PLUGIN_ID}"

herdr_bin() { printf '%s' "${HERDR_BIN_PATH:-herdr}"; }

# Strictly increasing across processes without a shared lock: epoch nanoseconds
# fit comfortably in u64 for the next few centuries. Herdr drops stale seqs from
# the same source, so hook and watcher can interleave safely.
next_seq() { date +%s%N; }

state_root() {
  if [ -n "${HERDR_BOB_STATE_DIR:-}" ]; then printf '%s' "$HERDR_BOB_STATE_DIR"
  elif [ -n "${HERDR_PLUGIN_STATE_DIR:-}" ]; then printf '%s' "$HERDR_PLUGIN_STATE_DIR"
  else printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/herdr-bob"
  fi
}

config_root() {
  if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ]; then printf '%s' "$HERDR_PLUGIN_CONFIG_DIR"
  else printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/herdr-bob"
  fi
}

# A registered Bob pane: one file per pane, holding the last known task id.
panes_dir()    { printf '%s/panes' "$(state_root)"; }
pane_file()    { printf '%s/panes/%s' "$(state_root)" "$1"; }
# Touched by the hook bridge; while fresh it owns idle/working and the watcher
# reports only `blocked`.
beat_file()    { printf '%s/heartbeat/%s' "$(state_root)" "$1"; }
HEARTBEAT_TTL=90

log() {
  local d; d="$(state_root)"
  mkdir -p "$d" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -Is)" "$*" >> "$d/herdr-bob.log" 2>/dev/null || true
  # Keep the log from growing without bound; cheap and good enough.
  local n; n=$(wc -l < "$d/herdr-bob.log" 2>/dev/null || echo 0)
  if [ "${n:-0}" -gt 2000 ]; then
    tail -n 500 "$d/herdr-bob.log" > "$d/herdr-bob.log.tmp" 2>/dev/null &&
      mv "$d/herdr-bob.log.tmp" "$d/herdr-bob.log" 2>/dev/null || true
  fi
}

report_state() { # pane, state, [session_id], [message]
  local pane=$1 state=$2 session=${3:-} message=${4:-}
  local -a args=(pane report-agent "$pane"
    --source "$SOURCE_ID" --agent "$AGENT_LABEL"
    --state "$state" --seq "$(next_seq)")
  [ -n "$session" ] && args+=(--agent-session-id "$session")
  [ -n "$message" ] && args+=(--message "$message")
  "$(herdr_bin)" "${args[@]}" >/dev/null 2>&1
}

release_agent() { # pane
  "$(herdr_bin)" pane release-agent "$1" \
    --source "$SOURCE_ID" --agent "$AGENT_LABEL" --seq "$(next_seq)" >/dev/null 2>&1
}

register_pane() { # pane, [session_id]
  mkdir -p "$(panes_dir)" 2>/dev/null || return 0
  printf '%s\n' "${2:-}" > "$(pane_file "$1")" 2>/dev/null || true
}

forget_pane() { rm -f "$(pane_file "$1")" "$(beat_file "$1")" 2>/dev/null || true; }

pane_alive() { "$(herdr_bin)" pane get "$1" >/dev/null 2>&1; }
