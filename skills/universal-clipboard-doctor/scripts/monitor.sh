#!/bin/bash
# Background monitor (run every 5 min by a LaunchAgent, see install-monitor.sh).
# Appends one line per run to ~/Library/Logs/universal-clipboard-doctor.log and notifies on the two known failures.
# Never logs clipboard contents or device identifiers. The only actions are notifications and, if AUTOFIX=1,
# restarting the Mac's own sharingd when iPhone->Mac is stuck on counter rejects.
set -u
NOTIFY=1    # 0 = log only
AUTOFIX=1   # 0 = notify only, never restart sharingd
LOGFILE="$HOME/Library/Logs/universal-clipboard-doctor.log"
STATE="$HOME/Library/Application Support/universal-clipboard-doctor/state"
WINDOW="6m"
LOG=/usr/bin/log
mkdir -p "$(dirname "$LOGFILE")" "$STATE"
if [ -f "$LOGFILE" ] && [ "$(stat -f%z "$LOGFILE")" -gt 5242880 ]; then
  tail -n 2000 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
fi
show() { "$LOG" show --last "$WINDOW" --style compact --predicate "$1" 2>/dev/null | grep -E '^[0-9]{4}-'; }
cnt() { printf '%s\n' "$1" | grep -c -- "$2"; }
notify() { [ "$NOTIFY" = 1 ] && osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1; }

# iPhone -> Mac: adverts decrypted vs. rejected as replays
HO="$(show 'process == "sharingd" AND category == "Handoff" AND (eventMessage CONTAINS "Successfully decrypted advertisement" OR eventMessage CONTAINS "is not greater than previous")')"
adv_ok=$(cnt "$HO" "Successfully decrypted advertisement")
ctr_reject=$(cnt "$HO" "is not greater than previous")
ctr_stuck=$(printf '%s\n' "$HO" | grep -v '^$' | tail -1 | grep -c "is not greater than previous")

# Mac -> iPhone: copies, pulls, and whether the Handoff advert (type 12) actually aired
UA="$(show 'process == "useractivityd" AND (eventMessage CONTAINS "PBOARD CONTROLLER] Got type update" OR eventMessage CONTAINS "Requested from remote")')"
mac_copy=$(cnt "$UA" "Got type update")
iphone_pull=$(cnt "$UA" "Requested from remote")
BT="$(show 'process == "bluetoothd" AND ((eventMessage CONTAINS "Start advertising for process identityservicesd" AND eventMessage CONTAINS "of type 12") OR eventMessage CONTAINS "4C 00 0C 0E" OR eventMessage CONTAINS "current advertisers")')"
ho_req=$(cnt "$BT" "of type 12")
ho_aired=$(cnt "$BT" "4C 00 0C 0E")
airdrop_slot=$(printf '%s\n' "$BT" | grep "current advertisers" | tail -1 | grep -c -E "advertisers: (5|.* 5)( |$)")

# Failure A (Mac->iPhone): AirDrop window starving the advert — notify after 2 consecutive runs, once per incident
if [ "$airdrop_slot" = 1 ] && [ "$ho_req" -gt 0 ] && [ "$ho_aired" = 0 ]; then
  strikes=$(( $(cat "$STATE/airdrop_strikes" 2>/dev/null || echo 0) + 1 ))
else
  strikes=0; rm -f "$STATE/airdrop_notified"
fi
printf '%s' "$strikes" > "$STATE/airdrop_strikes"
airdrop_alert=0
if [ "$strikes" -ge 2 ] && [ ! -e "$STATE/airdrop_notified" ]; then
  notify "Mac→iPhone clipboard blocked" "A Finder AirDrop window (maybe on another Space) is starving the clipboard advert. Close it." \
    && touch "$STATE/airdrop_notified" && airdrop_alert=1
fi

# Failure B (iPhone->Mac): counter rejects — restart sharingd at most every 30 min, notify once per incident
ctr_fixed=0
if [ "$ctr_stuck" = 1 ]; then
  now=$(date +%s); last=$(cat "$STATE/ctr_fix_at" 2>/dev/null || echo 0)
  if [ "$AUTOFIX" = 1 ] && [ $((now - last)) -ge 1800 ]; then
    killall sharingd >/dev/null 2>&1 && ctr_fixed=1 && printf '%s' "$now" > "$STATE/ctr_fix_at"
  fi
  if [ ! -e "$STATE/ctr_notified" ]; then
    if [ "$ctr_fixed" = 1 ]; then msg="Mac rejected the iPhone's clipboard advert as a replay. Restarted sharingd — copy on the iPhone again."
    else msg="Mac rejected the iPhone's clipboard advert as a replay (iPhone counter went backwards). Run: killall sharingd"; fi
    notify "iPhone→Mac clipboard rejected" "$msg" && touch "$STATE/ctr_notified"
  fi
else
  rm -f "$STATE/ctr_notified"
fi

printf '%s | iPhone adverts ok:%s counter-rejects:%s stuck:%s autofix:%s | Mac copies:%s iPhone pulls:%s | handoff advert req:%s aired:%s airdrop-slot:%s alert:%s\n' \
  "$(date '+%F %T')" "$adv_ok" "$ctr_reject" "$ctr_stuck" "$ctr_fixed" "$mac_copy" "$iphone_pull" "$ho_req" "$ho_aired" "$airdrop_slot" "$airdrop_alert" >> "$LOGFILE"
