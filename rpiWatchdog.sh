#!/bin/bash

CHROMIUM_BIN="$1"
LOGFILE="$2"
CHROMIUM_LOGFILE="$3"
WATCHDOG_PIDFILE="$4"
shift 4
CHROMIUM_ARGS=("$@")
HEARTBEAT_CHECK_INTERVAL_SECONDS=15
HEARTBEAT_FAILURE_LIMIT=4
CHROMIUM_PID=''
HEARTBEAT_FAILURES=0

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" >> "$LOGFILE"
}

start_chromium() {
    "$CHROMIUM_BIN" "${CHROMIUM_ARGS[@]}" \
        --enable-logging=stderr --v=0 >> "$CHROMIUM_LOGFILE" 2>&1 &
    CHROMIUM_PID=$!
    HEARTBEAT_FAILURES=0
    log "Chromium started by watchdog (PID $CHROMIUM_PID)"
}

stop_chromium() {
    if pgrep -x chromium >/dev/null 2>&1; then
        pkill -TERM -x chromium 2>/dev/null || true
    fi
    if [[ -n "$CHROMIUM_PID" ]]; then
        wait "$CHROMIUM_PID" 2>/dev/null || true
        CHROMIUM_PID=''
    fi
}

cleanup() {
    trap - EXIT INT TERM
    stop_chromium
    if [[ -r "$WATCHDOG_PIDFILE" ]] \
        && [[ "$(cat "$WATCHDOG_PIDFILE")" == "$$" ]]; then
        rm -f "$WATCHDOG_PIDFILE"
    fi
}

printf '%s\n' "$$" > "$WATCHDOG_PIDFILE"
trap cleanup EXIT
trap 'exit 0' INT TERM

start_chromium
while true; do
    sleep "$HEARTBEAT_CHECK_INTERVAL_SECONDS"

    if ! kill -0 "$CHROMIUM_PID" 2>/dev/null; then
        wait "$CHROMIUM_PID"
        CHROMIUM_STATUS=$?
        CHROMIUM_PID=''
        log "Chromium exited with status $CHROMIUM_STATUS; restarting"
        sleep 5
        start_chromium
        continue
    fi

    if curl --silent --show-error --fail --max-time 3 \
        http://127.0.0.1:5050/browser-heartbeat/ >/dev/null 2>&1; then
        HEARTBEAT_FAILURES=0
    else
        HEARTBEAT_FAILURES=$((HEARTBEAT_FAILURES + 1))
        if (( HEARTBEAT_FAILURES >= HEARTBEAT_FAILURE_LIMIT )); then
            log "Viewer heartbeat missed $HEARTBEAT_FAILURES checks; restarting Chromium"
            stop_chromium
            sleep 5
            start_chromium
        fi
    fi
done
