#!/bin/bash

BROWSER_BIN="$1"
LOGFILE="$2"
BROWSER_LOGFILE="$3"
WATCHDOG_PIDFILE="$4"
BROWSER_PROCESS_NAME="$5"
BROWSER_LIBRARY_PATH="$6"
shift 6
BROWSER_ARGS=("$@")
HEARTBEAT_CHECK_INTERVAL_SECONDS=15
HEARTBEAT_FAILURE_LIMIT=4
BROWSER_PID=''
HEARTBEAT_FAILURES=0

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" >> "$LOGFILE"
}

start_browser() {
    LD_LIBRARY_PATH="$BROWSER_LIBRARY_PATH" MOZ_ENABLE_WAYLAND=0 \
        "$BROWSER_BIN" "${BROWSER_ARGS[@]}" \
        >> "$BROWSER_LOGFILE" 2>&1 &
    BROWSER_PID=$!
    HEARTBEAT_FAILURES=0
    log "Browser started by watchdog (PID $BROWSER_PID)"
}

stop_browser() {
    if pgrep -u "$UID" -x "$BROWSER_PROCESS_NAME" >/dev/null 2>&1; then
        pkill -TERM -u "$UID" -x "$BROWSER_PROCESS_NAME" 2>/dev/null || true
    fi
    if [[ -n "$BROWSER_PID" ]]; then
        wait "$BROWSER_PID" 2>/dev/null || true
        BROWSER_PID=''
    fi
}

cleanup() {
    trap - EXIT INT TERM
    stop_browser
    if [[ -r "$WATCHDOG_PIDFILE" ]] \
        && [[ "$(cat "$WATCHDOG_PIDFILE")" == "$$" ]]; then
        rm -f "$WATCHDOG_PIDFILE"
    fi
}

printf '%s\n' "$$" > "$WATCHDOG_PIDFILE"
trap cleanup EXIT
trap 'exit 0' INT TERM

start_browser
while true; do
    sleep "$HEARTBEAT_CHECK_INTERVAL_SECONDS"

    if ! kill -0 "$BROWSER_PID" 2>/dev/null; then
        wait "$BROWSER_PID"
        BROWSER_STATUS=$?
        BROWSER_PID=''
        log "Browser exited with status $BROWSER_STATUS; restarting"
        sleep 5
        start_browser
        continue
    fi

    if curl --silent --show-error --fail --max-time 3 \
        http://127.0.0.1:5050/browser-heartbeat/ >/dev/null 2>&1; then
        HEARTBEAT_FAILURES=0
    else
        HEARTBEAT_FAILURES=$((HEARTBEAT_FAILURES + 1))
        if (( HEARTBEAT_FAILURES >= HEARTBEAT_FAILURE_LIMIT )); then
            log "Viewer heartbeat missed $HEARTBEAT_FAILURES checks; restarting browser"
            stop_browser
            sleep 5
            start_browser
        fi
    fi
done
