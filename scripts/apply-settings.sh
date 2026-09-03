#!/bin/bash
# Apply a settings plan from services/Settings.js planImport().
#
# The plan arrives on stdin as
#   { "schema": 1, "changes": [ { "key": ..., "value": ..., "from": ... } ] }
# and every change is dispatched to the writer that already owns that
# setting. Nothing here writes a config file directly.
#
#   --dry-run   print the command for each change and run none of them
#   --plan F    read the plan from F instead of stdin
#   --snapshot F  use a snapshot from F instead of running snapshot.sh
#   --backup DIR  where to leave the undo plan and file copies
#
# A failing change is reported and the rest still run. Stopping halfway
# leaves the most confusing state possible, so the run finishes and the
# exit status tells you whether anything failed.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
DRY=0
NO_BACKUP=0
PLAN_FILE=""
SNAPSHOT_FILE=""
BACKUP_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --plan) PLAN_FILE=${2:-}; shift 2 ;;
    --snapshot) SNAPSHOT_FILE=${2:-}; shift 2 ;;
    --backup) BACKUP_DIR=${2:-}; shift 2 ;;
    *) echo "Usage: apply-settings.sh [--dry-run] [--no-backup] [--plan <file>] [--snapshot <file>] [--backup <dir>]" >&2; exit 2 ;;
  esac
done

for tool in jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "apply-settings.sh: $tool is required" >&2; exit 1; }
done

if [[ -n $PLAN_FILE ]]; then
  [[ -r $PLAN_FILE ]] || { echo "apply-settings.sh: cannot read $PLAN_FILE" >&2; exit 1; }
  PLAN=$(cat -- "$PLAN_FILE")
else
  PLAN=$(cat)
fi

jq -e 'type == "object" and (.changes | type == "array")' <<<"$PLAN" >/dev/null 2>&1 ||
  { echo "apply-settings.sh: the plan needs a changes array" >&2; exit 1; }

schema=$(jq -r '.schema // 0' <<<"$PLAN")
if [[ $schema != 1 ]]; then
  echo "apply-settings.sh: this plan is schema $schema and this Atmos applies 1" >&2
  exit 1
fi

count=$(jq -r '.changes | length' <<<"$PLAN")
if [[ $count -eq 0 ]]; then
  echo "Nothing to apply."
  exit 0
fi

if [[ -n $SNAPSHOT_FILE ]]; then
  [[ -r $SNAPSHOT_FILE ]] || { echo "apply-settings.sh: cannot read $SNAPSHOT_FILE" >&2; exit 1; }
  SNAPSHOT=$(cat -- "$SNAPSHOT_FILE")
else
  SNAPSHOT=$(bash "$ROOT/snapshot.sh")
fi

plan_value() { jq -r --arg k "$1" '.changes[] | select(.key == $k) | .value' <<<"$PLAN"; }
# A list value has to stay JSON on the way to its writer.
plan_list() { jq -c --arg k "$1" '[.changes[] | select(.key == $k) | .value] | .[0] // []' <<<"$PLAN"; }
plan_has() { jq -e --arg k "$1" 'any(.changes[]; .key == $k)' <<<"$PLAN" >/dev/null 2>&1; }
snap_value() { jq -r --arg p "$1" 'getpath($p | split(".")) // empty' <<<"$SNAPSHOT"; }

# The value the plan sets, or the machine's current value when the plan does
# not mention it. A paired writer takes every value at once, so the halves the
# plan left alone have to be read back rather than dropped.
plan_or_snapshot() {
  if plan_has "$1"; then plan_value "$1"; else snap_value "$1"; fi
}

# hypr-sentinel replaces the managed block wholesale, so a grouped writer has
# to be handed the current object with the changes merged in. Sending only the
# changed fields would drop every setting the plan did not mention.
merged_group() {
  local group=$1
  jq -c --arg g "$group" '
    (.snapshot[$g] // {}) as $base
    | reduce (.plan.changes[] | select(.key | startswith($g + "."))) as $c
        ($base; .[$c.key | split(".")[1]] = $c.value)
  ' <<<"$(jq -n --argjson snapshot "$SNAPSHOT" --argjson plan "$PLAN" '{snapshot:$snapshot, plan:$plan}')"
}

# Files a writer may rewrite, so a copy exists before it does.
backup_for() {
  case $1 in
    hyprLook) printf '%s\n' "$HOME/.config/hypr/looknfeel.lua" ;;
    hyprInput) printf '%s\n' "$HOME/.config/hypr/input.lua" ;;
    bindings) printf '%s\n' "$HOME/.config/hypr/bindings.lua" ;;
    autostart) printf '%s\n' "$HOME/.config/hypr/autostart.lua" ;;
    windowRules) printf '%s\n' "$HOME/.config/hypr/atmos.lua" ;;
    nightlightSchedule) printf '%s\n' "$HOME/.config/hypr/hyprsunset.conf" ;;
    clock | barLayout) printf '%s\n' "$HOME/.config/omarchy/shell.json" ;;
    *) : ;;
  esac
}

declare -a RUN_KEYS=()
declare -a RUN_CMDS=()
declare -a RUN_GROUPS=()

queue() {
  local key=$1 group=$2
  shift 2
  RUN_KEYS+=("$key")
  RUN_GROUPS+=("$group")
  RUN_CMDS+=("$(printf '%s\0' "$@" | base64 -w0)")
}

bool_arg() { [[ $1 == true ]] && printf 'true\n' || printf 'false\n'; }

# A toggle has no "set" verb, so it only runs when the plan actually flips it.
toggle_needed() {
  local key=$1
  local want current
  want=$(plan_value "$key")
  current=$(snap_value "$key")
  [[ $want != "$current" ]]
}

seen_group() {
  local g=$1 i
  for i in "${RUN_GROUPS[@]:-}"; do
    [[ $i == "$g" ]] && return 0
  done
  return 1
}

while IFS= read -r key; do
  value=$(plan_value "$key")
  case $key in
    theme) queue "$key" "" omarchy theme set "$value" ;;
    background) queue "$key" "" omarchy theme bg set "$value" ;;
    font) queue "$key" "" omarchy font set "$value" ;;
    textSize) queue "$key" "" omarchy display text size "$value" ;;

    hyprLook.*)
      seen_group hyprLook || queue "$key" hyprLook bash "$ROOT/set-hypr-look.sh" "$(merged_group hyprLook)"
      ;;
    hyprInput.*)
      seen_group hyprInput || queue "$key" hyprInput bash "$ROOT/set-hypr-input.sh" "$(merged_group hyprInput)"
      ;;
    hyprNoGaps) queue "$key" "" omarchy hyprland toggle window-no-gaps ;;
    hyprSquareAspect) queue "$key" "" omarchy hyprland toggle single-window-aspect-ratio ;;

    barPosition) queue "$key" "" omarchy bar position "$value" ;;
    barTransparent) queue "$key" "" omarchy bar transparent "$(bool_arg "$value")" ;;
    barVisible)
      toggle_needed "$key" && queue "$key" "" omarchy toggle bar "$([[ $value == true ]] && echo on || echo off)"
      ;;
    clockFormat) queue "$key" clock omarchy bar set omarchy.clock format "$value" ;;
    clockFormatAlt) queue "$key" clock omarchy bar set omarchy.clock formatAlt "$value" ;;
    clockWeekStart) queue "$key" clock omarchy bar set omarchy.clock weekStartDay "$value" ;;

    browser | terminal | editor | agent) queue "$key" "" omarchy default "$key" "$value" ;;
    mimePdf) queue "$key" "" bash "$ROOT/set-mime-default.sh" pdf "$value" ;;
    mimeImage) queue "$key" "" bash "$ROOT/set-mime-default.sh" image "$value" ;;
    mimeVideo) queue "$key" "" bash "$ROOT/set-mime-default.sh" video "$value" ;;

    idleScreensaver | idleLock)
      if ! seen_group idle; then
        screensaver=$(plan_or_snapshot idleScreensaver)
        lock=$(plan_or_snapshot idleLock)
        queue "$key" idle bash "$ROOT/set-idle.sh" "$screensaver" "$lock"
      fi
      ;;
    stayAwake)
      toggle_needed "$key" && queue "$key" "" omarchy toggle idle "$([[ $value == true ]] && echo stay-awake || echo allow-idle)"
      ;;
    screensaverEnabled)
      toggle_needed "$key" && queue "$key" "" omarchy toggle screensaver-off "$([[ $value == true ]] && echo off || echo on)"
      ;;
    doNotDisturb)
      toggle_needed "$key" && queue "$key" "" omarchy toggle notification silencing
      ;;
    nightlight)
      toggle_needed "$key" && queue "$key" "" omarchy toggle nightlight
      ;;
    nightlightTemperature) queue "$key" "" bash "$ROOT/set-nightlight-temp.sh" "$value" ;;
    nightlightDay | nightlightNight | nightlightNightOn)
      if ! seen_group nightlightSchedule; then
        day=$(plan_or_snapshot nightlightDay)
        night=$(plan_or_snapshot nightlightNight)
        on=$(plan_or_snapshot nightlightNightOn)
        temp=$(snap_value nightlightTemperature)
        queue "$key" nightlightSchedule bash "$ROOT/set-hyprsunset.sh" \
          "$(jq -nc --arg d "$day" --arg n "$night" --argjson o "${on:-false}" --argjson t "${temp:-0}" \
            '{day:$d, night:$n, nightOn:$o, temperature:$t}')"
      fi
      ;;

    # The sentinel writers take the whole list, so a list setting is one call.
    # `managed` is a fact about where a row currently lives, not part of the
    # row, so it never travels to the writer.
    bindings)
      queue "$key" bindings bash "$ROOT/set-hypr-bindings.sh" \
        "$(jq -c '{items: [.[] | {keys, label, command, unbind}]}' <<<"$(plan_list "$key")")"
      ;;
    windowRules)
      queue "$key" windowRules bash "$ROOT/set-hypr-windows.sh" \
        "$(jq -c '{items: [.[] | del(.managed)]}' <<<"$(plan_list "$key")")"
      ;;
    autostart)
      queue "$key" autostart bash "$ROOT/set-hypr-autostart.sh" \
        "$(jq -c '{commands: [.[] | .command]}' <<<"$(plan_list "$key")")"
      ;;

    hostname) queue "$key" "" bash "$ROOT/set-hostname.sh" "$value" ;;
    timezone) queue "$key" "" bash "$ROOT/set-timezone.sh" "$value" ;;
    locale) queue "$key" "" bash "$ROOT/set-locale.sh" "$value" ;;
    keyboardLayout) queue "$key" "" bash "$ROOT/set-keyboard-layout.sh" "$value" ;;
    ntp) queue "$key" "" bash "$ROOT/set-ntp.sh" "$(bool_arg "$value")" ;;
    fullName) queue "$key" "" bash "$ROOT/set-full-name.sh" "$value" ;;
    parallelDownloads) queue "$key" "" bash "$ROOT/set-parallel-downloads.sh" "$value" ;;
    dns) queue "$key" "" omarchy dns "$value" ;;

    *)
      echo "apply-settings.sh: no writer for $key" >&2
      exit 1
      ;;
  esac
done < <(jq -r '.changes[].key' <<<"$PLAN")

# The undo plan is the same plan with from and value swapped, so reversing an
# import is the ordinary path rather than a special one.
EXPLICIT_BACKUP=0
if [[ -n $BACKUP_DIR ]]; then
  EXPLICIT_BACKUP=1
else
  BACKUP_DIR="$STATE_HOME/atmos/imports/$(date -u +%Y%m%dT%H%M%SZ)"
fi

# Undoing must not leave a way back of its own. If it did, the newest way
# back would be the one that reverses the undo, and pressing undo twice
# would put the import straight back rather than doing nothing.
if [[ $NO_BACKUP -eq 1 ]]; then
  EXPLICIT_BACKUP=0
fi

# A dry run writes the undo plan when you name a directory, so you can read
# the way back before you commit to the way forward. It never copies files,
# because nothing is about to change them.
if [[ $NO_BACKUP -eq 0 && ( $DRY -eq 0 || $EXPLICIT_BACKUP -eq 1 ) ]]; then
  mkdir -p -- "$BACKUP_DIR"
  jq '{schema: .schema, changes: [.changes[] | select(.from != null) | {key: .key, value: .from, from: .value}]}' \
    <<<"$PLAN" >"$BACKUP_DIR/undo.json"
fi

if [[ $DRY -eq 0 && $NO_BACKUP -eq 0 ]]; then
  for group in "${RUN_GROUPS[@]:-}"; do
    [[ -n $group ]] || continue
    file=$(backup_for "$group")
    [[ -n ${file:-} && -f $file ]] || continue
    cp -- "$file" "$BACKUP_DIR/$(basename -- "$file")"
  done
fi

status=0
results=()
for i in "${!RUN_KEYS[@]}"; do
  key=${RUN_KEYS[$i]}
  mapfile -d '' -t argv < <(base64 -d <<<"${RUN_CMDS[$i]}")
  if [[ $DRY -eq 1 ]]; then
    printf '%s\t%s\n' "$key" "$(printf '%q ' "${argv[@]}")"
    results+=("$(jq -nc --arg k "$key" '{key:$k, status:"dry-run"}')")
    continue
  fi
  if err=$("${argv[@]}" 2>&1 >/dev/null); then
    results+=("$(jq -nc --arg k "$key" '{key:$k, status:"applied"}')")
  else
    status=1
    echo "apply-settings.sh: $key failed: $err" >&2
    results+=("$(jq -nc --arg k "$key" --arg e "$err" '{key:$k, status:"failed", error:$e}')")
  fi
done

if [[ $DRY -eq 0 ]]; then
  printf '%s\n' "${results[@]}" | jq -sc \
    --arg dir "$([[ $NO_BACKUP -eq 1 ]] && echo "" || echo "$BACKUP_DIR")" \
    '{backup:$dir, results:.}'
fi

exit $status
