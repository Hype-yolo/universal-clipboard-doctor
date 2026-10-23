---
name: universal-clipboard-doctor
description: Diagnose and fix Apple Universal Clipboard (copy on Mac, paste on iPhone or the reverse) when it pastes old content. Reads the Mac's unified log to tell which direction is broken and why — an open Finder AirDrop window starving the Mac's Bluetooth advert, or the Mac rejecting the iPhone's advert as a replay after iOS restarts sharingd — then applies the matching fix and can install a background monitor. Use when the user says Universal Clipboard / 通用剪贴板 / Handoff / 接力 / Mac 和 iPhone 复制粘贴互通 stopped working or pastes old content.
---

# Universal Clipboard doctor

Scripts live next to this file: `S=<this skill dir>/scripts`.

## Steps

1. **Ask which direction fails** if the user didn't say: copy on Mac → paste on iPhone, or the reverse.
   The two directions have different causes; don't apply one's fix to the other.
2. **Run the diagnosis while it is still broken** (fixing first erases the evidence):
   `bash $S/diagnose.sh 30m` — widen to `2h` if the failure was earlier. Read-only.
3. **Act on the verdict** (details and evidence patterns in `references/failure-modes.md`):
   - `AIRDROP WINDOW STARVES HANDOFF ADVERT` (Mac→iPhone): tell the user to close the Finder AirDrop window,
     including on other Spaces. Don't kill Finder or AirDrop processes.
   - `COUNTER REJECT` (iPhone→Mac): `bash $S/diagnose.sh --fix` restarts the Mac's `sharingd`. Then ask the user
     to copy on the iPhone again and re-run `diagnose.sh 5m` to confirm adverts decrypt. Say plainly this fix
     is inferred, not yet proven on many machines.
   - No iPhone adverts at all: iPhone locked/asleep, out of range, or Bluetooth/Handoff off on the iPhone.
   - Nothing matches: have the user reproduce once (copy, wait 5 s, paste) and re-run with `5m`.
     For iPhone-side causes, collect iPhone logs over USB (see the reference) — needs the user to type their
     sudo password themselves.
4. **Offer the monitor** for recurring problems: `bash $S/install-monitor.sh` (LaunchAgent, every 5 min,
   notifies on both failures; `AUTOFIX=1` restarts sharingd on counter rejects). Remove with `--uninstall`.

## Rules

- Always call `/usr/bin/log`, never bare `log` (zsh builtin).
- Never print clipboard contents or device identifiers back to the user or into files.
- Report what the logs show, including when the cause is still unproven. Don't call a workaround a root fix.
