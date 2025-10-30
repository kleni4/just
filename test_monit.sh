#!/bin/bash
set -Eeuo pipefail

PS_NAME="test"
MONIT_URL="https://test.com/monitoring/test/api"
LOG="/var/log/monitoring.log"
STATUS_FILE="/tmp/test_ps_pid"

# test log directory exsts
mkdir -p "$(dirname "$LOG")"

# Get PID
CURRENT_PID=$(pgrep -xo "$PS_NAME" || true)

if [ -z "$CURRENT_PID" ]; then
    echo "Process $PS_NAME is not running" | tee -a "$LOG"
    exit 1
fi

if [ -f "$STATUS_FILE" ]; then
    LAST_PID=$(cat "$STATUS_FILE")
    if [ "$CURRENT_PID" != "$LAST_PID" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Process $PS_NAME restarted (PID: $CURRENT_PID)" >> "$LOG"
    fi
fi

echo "$CURRENT_PID" > "$STATUS_FILE"

# Request
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$MONIT_URL" || echo 000)

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - API OK (HTTP $HTTP_CODE)" >> "$LOG"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - API FAIL (HTTP $HTTP_CODE)" >> "$LOG"
fi


