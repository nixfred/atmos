#!/bin/bash
# Facts for the shareable machine card that hw-inventory.py does not carry.
#
# Everything printed here is deliberately non-identifying: versions, sizes,
# counts and names of software. No hostname, no user, no addresses, no
# serials. The card is built to be posted in public, so this script is the
# other half of that promise and it is an allow-list too -- it prints the
# fields it was written to print and nothing is passed through from an
# environment or a command's full output.
set -euo pipefail

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

omarchy_version() {
  if [[ -r /usr/share/omarchy/version ]]; then
    head -n1 /usr/share/omarchy/version
    return
  fi
  if command -v omarchy >/dev/null 2>&1; then
    omarchy --version 2>/dev/null | head -n1 && return
  fi
  pacman -Q omarchy 2>/dev/null | awk '{print $2}' | head -n1
}

compositor() {
  if command -v hyprctl >/dev/null 2>&1; then
    local tag
    tag=$(hyprctl version -j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag",""))' 2>/dev/null || true)
    [[ -n $tag ]] && { echo "Hyprland $tag"; return; }
    echo "Hyprland"
    return
  fi
  echo "${XDG_CURRENT_DESKTOP:-}"
}

# Total bytes across real filesystems. Sizes are not identifying; mount
# points and device names can hint at setup, so only the total is emitted.
storage_total() {
  df -B1 --output=source,fstype,size 2>/dev/null | awk '
    NR > 1 && $1 ~ /^\/dev\// && $2 !~ /^(squashfs|overlay|tmpfs|devtmpfs)$/ {
      if (!seen[$1]++) total += $3
    }
    END { printf "%d", total + 0 }'
}

# Count only. Names of virtual machines are frequently personal.
vm_count() {
  local n=0
  if command -v virsh >/dev/null 2>&1; then
    n=$(virsh list --name 2>/dev/null | grep -c . || true)
  fi
  if [[ $n -eq 0 ]] && command -v pgrep >/dev/null 2>&1; then
    n=$(pgrep -c -x qemu-system-x86_64 2>/dev/null || true)
  fi
  printf '%d' "${n:-0}"
}

theme_name() {
  local f="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name"
  [[ -r $f ]] && head -n1 "$f" || true
}

printf '{'
printf '"omarchyVersion":%s,' "$(omarchy_version | json_escape)"
printf '"kernel":%s,' "$(uname -r | json_escape)"
printf '"arch":%s,' "$(uname -m | json_escape)"
printf '"compositor":%s,' "$(compositor | json_escape)"
printf '"shell":%s,' "$(basename "${SHELL:-}" | json_escape)"
printf '"uptime":%s,' "$(uptime -p 2>/dev/null | sed 's/^up //' | json_escape)"
printf '"theme":%s,' "$(theme_name | json_escape)"
printf '"storageTotal":%s,' "$(storage_total)"
printf '"vms":%s,' "$(vm_count)"
# Named so the UI can say "Asking codex…" rather than "asking the agent".
printf '"agent":%s' "$(command -v omarchy-default-agent >/dev/null 2>&1 && omarchy-default-agent 2>/dev/null | json_escape || echo '""')"
printf '}\n'
