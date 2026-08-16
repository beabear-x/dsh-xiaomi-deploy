#!/bin/sh
# Start local DeepSeek Harness Web UI for this phone only.
set -eu

BASE="${DSH_MINIS_DIR:-/var/minis/shared/deepseek-harness}"
RUNTIME="$BASE/runtime"
STATE="$BASE/state"
PORT="${1:-3080}"
PIDFILE="$BASE/dsh-web.pid"
LOGFILE="$BASE/dsh-web.log"
URL="http://127.0.0.1:$PORT/"

if [ ! -f "$RUNTIME/node_modules/@deepseek-ai/dsh/lib/bin.js" ]; then
  echo "DSH is not installed. Run $BASE/install-dsh.sh first." >&2
  exit 1
fi
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "DSH is already running: $URL"
  exit 0
fi

mkdir -p "$STATE"
rm -f "$PIDFILE"
cd "$RUNTIME"
DSH_HOME="$STATE" node --expose-internals ./node_modules/@deepseek-ai/dsh/lib/bin.js web --port "$PORT" > "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"

n=0
while [ "$n" -lt 12 ]; do
  if wget -q -O /dev/null -T 2 "$URL"; then
    echo "DSH Web UI is ready: $URL"
    echo "Open that address in Chrome or another system browser on this phone."
    exit 0
  fi
  n=$((n + 1))
  sleep 1
done

echo "DSH did not become ready. Recent log:" >&2
tail -80 "$LOGFILE" >&2 || true
exit 1
