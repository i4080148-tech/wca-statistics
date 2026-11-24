#!/bin/bash
# Sets up a daily run of bin/run_daily.sh on macOS using launchd.
# Usage: bin/install_daily_mac.sh [hour] [minute]   (default 4:30 AM)
# If the Mac is asleep at that time, the run happens as soon as it wakes up.
set -e
HOUR="${1:-4}"
MINUTE="${2:-30}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.local.wca-statistics"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$PROJECT/logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$PROJECT/bin/run_daily.sh</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$MINUTE</integer></dict>
  <key>StandardOutPath</key><string>$PROJECT/logs/daily.log</string>
  <key>StandardErrorPath</key><string>$PROJECT/logs/daily.log</string>
</dict>
</plist>
PLIST
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Daily update scheduled for $HOUR:$(printf %02d $MINUTE). Log: $PROJECT/logs/daily.log"
echo "To stop it: launchctl unload \"$PLIST\" && rm \"$PLIST\""
