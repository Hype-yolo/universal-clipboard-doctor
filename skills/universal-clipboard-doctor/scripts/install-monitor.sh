#!/bin/bash
# Install the background monitor as a per-user LaunchAgent (runs monitor.sh every 5 minutes). No sudo needed.
# Uninstall: install-monitor.sh --uninstall
set -eu
LABEL="io.github.universal-clipboard-doctor"
DIR="$HOME/Library/Application Support/universal-clipboard-doctor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$DIR"
  rm -f "$HOME/Library/Logs/universal-clipboard-doctor.log" "$HOME/Library/Logs/universal-clipboard-doctor.err"
  echo "Uninstalled."
  exit 0
fi

mkdir -p "$DIR" "$HOME/Library/LaunchAgents"
cp "$(cd "$(dirname "$0")" && pwd)/monitor.sh" "$DIR/monitor.sh"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DIR/monitor.sh</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>LowPriorityIO</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/universal-clipboard-doctor.err</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. Log: ~/Library/Logs/universal-clipboard-doctor.log"
echo "Edit NOTIFY / AUTOFIX at the top of: $DIR/monitor.sh"
