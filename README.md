# universal-clipboard-doctor

**Copy on your Mac, paste on your iPhone — and get yesterday's clipboard?** Or the other way round?
This is a Claude Code / agent skill (plus plain bash scripts) that reads the Mac's system log, tells you
**which direction is broken and why**, and applies the matching fix.

Built from two real incidents that were traced end-to-end through macOS and iOS logs — not from forum guesses.

## The two causes it detects

| Direction | What actually happens | Fix |
|---|---|---|
| **Mac → iPhone** | A Finder window showing **AirDrop** (often on another Space, hidden behind a full-screen app) keeps the Mac scanning for AirDrop. Its Bluetooth advert fills the Mac's advertising slots and the clipboard advert is silently dropped. The iPhone never learns there's anything new. | Close that window. Rebooting "worked" only because it closed the window. |
| **iPhone → Mac** | iOS sometimes restarts its `sharingd`; the new process resumes with a **lower anti-replay counter**. The Mac receives the iPhone's clipboard advert but discards it as a replay (`New counter is not greater than previous`). Heals by itself after ~30 min once the counter catches up. | `killall sharingd` on the Mac (relaunches instantly, forgets the stale counter). ⚠️ Inferred, not yet confirmed on a live incident — reports welcome. |

Full evidence patterns: [`references/failure-modes.md`](skills/universal-clipboard-doctor/references/failure-modes.md).

## Use it

**Without an agent** — run while it's still broken (fixing first erases the evidence):

```bash
git clone https://github.com/Hype-yolo/universal-clipboard-doctor
bash universal-clipboard-doctor/skills/universal-clipboard-doctor/scripts/diagnose.sh 30m
```

Add `--fix` to restart `sharingd` automatically when the iPhone→Mac counter problem is detected.

**As a Claude Code skill:**

```bash
cp -R universal-clipboard-doctor/skills/universal-clipboard-doctor ~/.claude/skills/
```

Then just tell Claude "Universal Clipboard is pasting old stuff again".

**Background monitor** (optional, LaunchAgent every 5 min, notifies on both failures, no sudo):

```bash
bash universal-clipboard-doctor/skills/universal-clipboard-doctor/scripts/install-monitor.sh
bash universal-clipboard-doctor/skills/universal-clipboard-doctor/scripts/install-monitor.sh --uninstall
```

Log: `~/Library/Logs/universal-clipboard-doctor.log`. Set `AUTOFIX=0` in the installed `monitor.sh` to only notify.

## Privacy & safety

- Read-only except: notifications, and restarting your Mac's own `sharingd` (only with `--fix` / `AUTOFIX=1`).
- Never reads or logs clipboard contents or device identifiers (macOS redacts them as `<private>` anyway).
- Doesn't change any settings. Uninstall removes everything it created.

Tested on macOS 26.6 with an iPhone 17 Pro Max (log strings may differ on other OS versions).

---

## 中文简介

Mac 和 iPhone 的「通用剪贴板」粘出旧内容？这个 skill 读 Mac 系统日志，判断是哪个方向坏、为什么坏：

- **Mac → iPhone 坏**：Finder 里开着「隔空投送」窗口（常在别的桌面、被全屏 App 挡住），占满 Mac 的蓝牙广播位，剪贴板广播被丢掉。关掉那个窗口即可。
- **iPhone → Mac 坏**：iOS 重启了 sharingd，iPhone 的防重放计数器回退，Mac 把 iPhone 的剪贴板信号当成「重放」拒收，约 30 分钟后自愈。`killall sharingd` 可立即恢复（推断，待更多实测）。

MIT License.
