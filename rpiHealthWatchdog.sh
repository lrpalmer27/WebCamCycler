#!/bin/bash

APP_DIR='/home/logan/Desktop/WebCamViewer'
LOGFILE="$APP_DIR/logs/logfile.txt"
PIDFILE="$APP_DIR/logs/webcam-cycler.pid"
HEALTH_URL='http://127.0.0.1:5050/health/'

cd "$APP_DIR" || exit 1
mkdir -p "$APP_DIR/logs"
echo "Health watchdog running @ $(date '+%r')" >> "$LOGFILE"
export DISPLAY=:0
source "$APP_DIR/myvenv/bin/activate"

while true; do
    sleep 30

    if curl --silent --show-error --fail --max-time 5 "$HEALTH_URL" >/dev/null; then
        continue
    fi

    echo "Webcam server health check failed @ $(date '+%r'); restarting it" >> "$LOGFILE"
    if [[ -f "$PIDFILE" ]]; then
        APP_PID="$(cat "$PIDFILE")"
        APP_COMMAND=''
        if [[ "$APP_PID" =~ ^[0-9]+$ ]] && [[ -r "/proc/$APP_PID/cmdline" ]]; then
            APP_COMMAND="$(tr '\0' ' ' < "/proc/$APP_PID/cmdline")"
        fi
        if [[ "$APP_COMMAND" == *"$APP_DIR/main.py"* ]] && kill -0 "$APP_PID" 2>/dev/null; then
            kill "$APP_PID"
            for attempt in {1..10}; do
                kill -0 "$APP_PID" 2>/dev/null || break
                sleep 1
            done
        fi
    fi

    python "$APP_DIR/main.py" >> "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    echo "Restarted webcam server with PID $(cat "$PIDFILE")" >> "$LOGFILE"
done
