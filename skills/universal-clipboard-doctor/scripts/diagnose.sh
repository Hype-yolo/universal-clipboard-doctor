#!/bin/bash
# Universal Clipboard doctor: read-only diagnosis of Mac <-> iPhone Universal Clipboard from the Mac's unified log.
# Usage: diagnose.sh [window]   e.g. diagnose.sh 30m   (default 30m)
#        diagnose.sh --fix      also restart the Mac's sharingd if iPhone->Mac is stuck on counter rejects
# Prints counts and a verdict. Never prints clipboard contents or device identifiers.
set -u
WINDOW="30m"
FIX=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    *[0-9][smhd]) WINDOW="$a" ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  esac
done
LOG=/usr/bin/log   # zsh has a `log` builtin; always call the binary

show() { "$LOG" show --last "$WINDOW" --style compact --predicate "$1" 2>/dev/null | grep -E '^[0-9]{4}-'; }
cnt() { printf '%s\n' "$1" | grep -c -- "$2"; }

# --- iPhone -> Mac -----------------------------------------------------------------------------
HO="$(show 'process == "sharingd" AND category == "Handoff" AND (eventMessage CONTAINS "Successfully decrypted advertisement" OR eventMessage CONTAINS "is not greater than previous")')"
adv_ok=$(cnt "$HO" "Successfully decrypted advertisement")
ctr_reject=$(cnt "$HO" "is not greater than previous")
ctr_stuck=$(printf '%s\n' "$HO" | grep -v '^$' | tail -1 | grep -c "is not greater than previous")
last_ok=$(printf '%s\n' "$HO" | grep "Successfully decrypted" | tail -1 | cut -c1-19)

# --- Mac -> iPhone -----------------------------------------------------------------------------
UA="$(show 'process == "useractivityd" AND (eventMessage CONTAINS "PBOARD CONTROLLER] Got type update" OR eventMessage CONTAINS "Requested from remote")')"
mac_copy=$(cnt "$UA" "Got type update")
iphone_pull=$(cnt "$UA" "Requested from remote")
BT="$(show 'process == "bluetoothd" AND ((eventMessage CONTAINS "Start advertising for process identityservicesd" AND eventMessage CONTAINS "of type 12") OR eventMessage CONTAINS "4C 00 0C 0E" OR eventMessage CONTAINS "current advertisers")')"
ho_req=$(cnt "$BT" "of type 12")
ho_aired=$(cnt "$BT" "4C 00 0C 0E")
adv_set=$(printf '%s\n' "$BT" | grep "current advertisers" | tail -1 | sed -E 's/.*advertisers: ?//')
airdrop_slot=$(printf '%s\n' "$adv_set" | grep -c -E '(^| )5( |$)')

# --- transport / environment -------------------------------------------------------------------
RP="$(show 'process == "rapportd" AND (eventMessage CONTAINS "Connect failed:" OR (eventMessage CONTAINS "Connected to [" AND eventMessage CONTAINS "awdl0"))')"
awdl_ok=$(cnt "$RP" "Connected to \[")
awdl_fail=$(cnt "$RP" "Connect failed:")
hotspot=$(ifconfig en0 2>/dev/null | grep -c constrained)
bt_on=$(system_profiler SPBluetoothDataType -detailLevel mini 2>/dev/null | grep -c 'State: On')

cat <<EOF
Universal Clipboard doctor — last $WINDOW
  iPhone→Mac  iPhone adverts decrypted: $adv_ok (last: ${last_ok:--})   counter rejects: $ctr_reject   stuck now: $ctr_stuck
  Mac→iPhone  Mac copies: $mac_copy   iPhone pulls: $iphone_pull   handoff advert requested: $ho_req aired: $ho_aired   advertiser set: [${adv_set:-?}]
  transport   AWDL ok: $awdl_ok  fail: $awdl_fail   Bluetooth on: $bt_on   on iPhone hotspot: $hotspot

EOF

found=0
if [ "$ctr_stuck" = 1 ] || { [ "$ctr_reject" -gt 0 ] && [ "$adv_ok" = 0 ]; }; then
  found=1
  cat <<'EOF'
✗ iPhone→Mac: COUNTER REJECT
  The Mac receives the iPhone's Handoff advert but discards it as a replay ("New counter is not greater than
  previous"). Typically starts after iOS relaunches its sharingd and resumes from a lower counter. Self-heals once
  the iPhone's counter overtakes the value the Mac remembers (observed: ~30 min).
  Fix: restart the Mac's sharingd so it forgets the old counter:  killall sharingd   (launchd relaunches it)
       (or run this script with --fix). Then copy on the iPhone again.
EOF
  if [ "$FIX" = 1 ]; then
    killall sharingd && echo "  → sharingd restarted. Copy on the iPhone again, then re-run this script to confirm adverts decrypt."
  fi
fi
if [ "$found" = 0 ] && [ "$ctr_reject" -gt 0 ]; then
  echo "· iPhone→Mac had $ctr_reject counter rejects in this window but has since recovered (see references/failure-modes.md, case B)."
fi
if [ "$airdrop_slot" = 1 ] && [ "$ho_req" -gt 0 ] && [ "$ho_aired" = 0 ]; then
  found=1
  cat <<'EOF'
✗ Mac→iPhone: AIRDROP WINDOW STARVES HANDOFF ADVERT
  An open Finder AirDrop window (possibly on another Space / behind a full-screen app) keeps the Mac browsing for
  AirDrop. Its advert (type 5) plus AirPlay (9) and Nearby Info (16) fill the Mac's BLE advertising slots, and the
  Handoff/clipboard advert (type 12) is dropped. The iPhone never learns there is a new Mac clipboard.
  Fix: close the AirDrop window in Finder (check other Spaces; or ⌘⇧R then ⌘W). Use Share → AirDrop to send;
       receiving does not need that window open.
EOF
fi
if [ "$mac_copy" -gt 0 ] && [ "$iphone_pull" = 0 ] && [ "$ho_aired" -gt 0 ]; then
  found=1
  echo "? Mac→iPhone: the Mac advertised its clipboard but the iPhone never pulled it. Keep the iPhone unlocked & nearby, check Handoff is on there."
fi
if [ "$awdl_fail" -gt 0 ] && [ "$awdl_ok" = 0 ]; then
  found=1
  echo "? Transport: peer-to-peer Wi-Fi (AWDL) connects are failing. Turn Wi-Fi on for both devices; leave the iPhone hotspot / try without VPN."
fi
if [ "$adv_ok" = 0 ] && [ "$ctr_reject" = 0 ]; then
  echo "· No iPhone adverts seen at all in this window. If you copied on the iPhone, it is locked/asleep, out of range, or Handoff/Bluetooth is off there."
fi
[ "$found" = 0 ] && echo "✓ No known failure pattern in this window. Reproduce the failure, then re-run within a few minutes."
exit 0
