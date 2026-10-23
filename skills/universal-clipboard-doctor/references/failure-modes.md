# Known Universal Clipboard failure modes (macOS ↔ iPhone)

How Universal Clipboard works, briefly: when you copy, the device broadcasts a small encrypted Bluetooth LE
"Handoff" advert (Apple manufacturer data type 12) saying "I have a new clipboard". The other device decrypts
it, and when you paste it pulls the content over peer-to-peer Wi-Fi (AWDL). If the advert is not sent,
not received, or rejected, the other device pastes its **old** clipboard — no error is shown.

Both cases below were confirmed from real logs, not guessed.

## A. Mac → iPhone: an open Finder AirDrop window starves the advert

**Symptom:** copy on Mac, paste on iPhone gives old content. iPhone → Mac still works. Rebooting the Mac "fixes" it.

**Mechanism:** while a Finder window shows the AirDrop location (even on another Space, hidden behind a
full-screen app) and the screen is on, the Mac keeps browsing for AirDrop. Its advert (type 5) plus AirPlay
receiver (9) and Nearby Info (16) fill the Mac's BLE advertising slots, and `bluetoothd` drops the
Handoff advert (type 12). The iPhone never hears about the new clipboard.

**Evidence pattern (Mac log):**
- `bluetoothd`: `Start advertising for process identityservicesd … of type 12` (requested) but no
  `4C 00 0C 0E` manufacturer-data line (never aired).
- `AdvertisingRulesiOS - current advertisers: 5 9 16` — type 5 present, 12 missing.
- Reproduction: navigate the same window away from AirDrop → advertising stops instantly, type 12 airs,
  next copy is pulled by the iPhone in < 1 s.

**Fix:** close that window. Send files with Share → AirDrop instead; receiving does not need the window.
Note: AppleScript/System Events only list Finder windows on the current Space.

## B. iPhone → Mac: the Mac rejects the iPhone's advert as a replay

**Symptom:** copy on iPhone, paste on Mac gives old content. Mac → iPhone still works. Heals by itself
after a while (observed ~30 min), seemingly at random.

**Mechanism:** each Handoff advert carries an anti-replay counter. iOS sometimes reclaims and relaunches
its `sharingd` (iPhone log: `service inactive: com.apple.sharingd` → `Successfully spawned sharingd … because
inefficient`). The new instance resumes advertising from a **lower** counter than the Mac last saw. The Mac's
`sharingd` keeps rejecting until the iPhone's counter overtakes the remembered value.

**Evidence pattern (Mac log, `sharingd`, category Handoff):**
- `New counter <private> is not greater than previous <private>` for every iPhone copy.
- Followed by `Requesting Encryption key via Rapport/IDS` → `Received a new Handoff encryption key` →
  rejected again (same key, same counter problem).
- Meanwhile the iPhone log shows it *did* advertise: `bluetoothd: Requesting to start advertising for clients 12 16 22`.
- Recovery = first `Successfully decrypted advertisement` after the rejects.

**Fix:** `killall sharingd` on the Mac (launchd relaunches it immediately; it forgets the stale counter).
⚠️ Status: inferred from the mechanism, **not yet confirmed on a live incident**. The monitor records
`autofix:1` and whether adverts decrypt afterwards — please report results.
Fallback: keep copying on the iPhone; the counter catches up.

## Not the cause (ruled out in these cases)

- `SecItemCopyMatching wrappingKeyQuery failed` / `No wrapping key found in keychain` — appears daily on
  healthy systems.
- Rebooting, VPN, hotspot, toggling AWDL — only treated symptoms (rebooting closes the AirDrop window).

## Reading iPhone logs (needed to confirm B)

Connect the iPhone by cable, unlock, trust the Mac, then:

```bash
xcrun devicectl list devices                      # get the UDID
sudo /usr/bin/log collect --device-udid <UDID> --last 90m --output /tmp/iphone.logarchive
/usr/bin/log show --archive /tmp/iphone.logarchive --style compact --predicate 'process == "sharingd"'
```

The archive is shown in the iPhone's time zone; align clocks using an event visible on both sides
(e.g. a Mac copy → iPhone `Notify client of new remote pboard`).
Use `/usr/bin/log`, not `log` — zsh has a `log` builtin.
