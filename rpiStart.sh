#!/bin/bash

APP_DIR='/home/logan/Desktop/WebCamCycler'
LOG_DIR="$APP_DIR/logs"
LOGFILE="$LOG_DIR/logfile.txt"
CHROMIUM_LOGFILE="$LOG_DIR/chromium.log"
PIDFILE="$LOG_DIR/webcam-cycler.pid"
WATCHDOG_PIDFILE="$LOG_DIR/webcam-cycler-watchdog.pid"
DEPENDENCY_COMMIT_FILE="$LOG_DIR/dependencies-commit"
REQUIREMENTS_FILE="$APP_DIR/PIRequirements.txt"
CHROMIUM_STARTUP_DELAY_SECONDS=20
WATCHDOG_PID=''

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" >> "$LOGFILE"
}

report_error() {
    local status=$?
    log "ERROR: command failed with exit status $status at line ${BASH_LINENO[0]}: $BASH_COMMAND"
}
trap report_error ERR

if ! cd "$APP_DIR"; then
    printf '[%s] ERROR: cannot enter app directory: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')" "$APP_DIR" >&2
    exit 1
fi
if ! mkdir -p "$LOG_DIR"; then
    printf '[%s] ERROR: cannot create log directory: %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')" "$LOG_DIR" >&2
    exit 1
fi

log "===== rpiStart.sh starting (directory: $APP_DIR) ====="

if [[ -r "$WATCHDOG_PIDFILE" ]]; then
    OLD_WATCHDOG_PID="$(cat "$WATCHDOG_PIDFILE")"
    OLD_WATCHDOG_COMMAND=''
    if [[ "$OLD_WATCHDOG_PID" =~ ^[0-9]+$ ]] \
        && [[ -r "/proc/$OLD_WATCHDOG_PID/cmdline" ]]; then
        OLD_WATCHDOG_COMMAND="$(tr '\0' ' ' < "/proc/$OLD_WATCHDOG_PID/cmdline")"
    fi
    if [[ "$OLD_WATCHDOG_COMMAND" == *"$APP_DIR/rpiWatchdog.sh"* ]] \
        && kill -0 "$OLD_WATCHDOG_PID" 2>/dev/null; then
        log "Stopping previous Chromium watchdog (PID $OLD_WATCHDOG_PID)"
        if ! kill "$OLD_WATCHDOG_PID"; then
            log "ERROR: could not stop previous Chromium watchdog"
            exit 1
        fi
        sleep 2
    fi
fi

# retain the display session inherited from the desktop; use :0 as fallback
export DISPLAY="${DISPLAY:-:0}"
log "Display environment: DISPLAY=$DISPLAY, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-not set}, XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-not set}, XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-not set}"
if ! command -v xdotool >/dev/null 2>&1; then
    log "WARNING: xdotool is unavailable; NTV camera activation requires 'sudo apt install xdotool'"
fi

# kill browser
log "Closing any existing Chromium process"
if pkill chromium 2>/dev/null; then
    log "Existing Chromium process stopped"
else
    log "No existing Chromium process found"
fi

# stop the previously recorded Flask process if it is still running
if [[ -f "$PIDFILE" ]]; then
    OLD_PID="$(cat "$PIDFILE")"
    OLD_COMMAND=''
    if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && [[ -r "/proc/$OLD_PID/cmdline" ]]; then
        OLD_COMMAND="$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline")"
    fi
    if [[ "$OLD_COMMAND" == *"$APP_DIR/main.py"* ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "Stopping previous app process (PID $OLD_PID)"
        if ! kill "$OLD_PID"; then
            log "ERROR: could not stop previous app process (PID $OLD_PID)"
            exit 1
        fi
        sleep 2
    else
        log "No matching previous app process found for PID $OLD_PID"
    fi
else
    log "No previous app PID file found"
fi

# start venv
log "Activating virtual environment: $APP_DIR/.venv"
if ! source "$APP_DIR/.venv/bin/activate"; then
    log "ERROR: failed to activate virtual environment"
    exit 1
fi
log "Virtual environment activated (Python: $(command -v python))"

# install dependencies only when the requirements changed since the last check
log "Checking Git commit and Python requirements"
CURRENT_COMMIT="$(git -C "$APP_DIR" rev-parse HEAD 2>> "$LOGFILE")" || {
    log "ERROR: unable to determine current Git commit; cannot check dependencies"
    exit 1
}
LAST_CHECKED_COMMIT=''
if [[ -r "$DEPENDENCY_COMMIT_FILE" ]]; then
    LAST_CHECKED_COMMIT="$(cat "$DEPENDENCY_COMMIT_FILE")"
fi

INSTALL_REQUIREMENTS=1
if [[ -n "$LAST_CHECKED_COMMIT" ]]; then
    if git -C "$APP_DIR" cat-file -e "$LAST_CHECKED_COMMIT^{commit}" 2>> "$LOGFILE"; then
        git -C "$APP_DIR" diff --quiet "$LAST_CHECKED_COMMIT" "$CURRENT_COMMIT" -- PIRequirements.txt
        DIFF_STATUS=$?
        if [[ "$DIFF_STATUS" -eq 0 ]]; then
            INSTALL_REQUIREMENTS=0
        elif [[ "$DIFF_STATUS" -ne 1 ]]; then
            log "ERROR: unable to compare dependency requirements between commits"
            exit 1
        fi
    fi
fi

if [[ "$INSTALL_REQUIREMENTS" -eq 1 ]]; then
    log "Installing Python dependencies from $REQUIREMENTS_FILE (commit $CURRENT_COMMIT)"
    if ! python -m pip install -r "$REQUIREMENTS_FILE" >> "$LOGFILE" 2>&1; then
        log "ERROR: pip dependency installation failed; see preceding output"
        exit 1
    fi
    log "Python dependency installation completed"
else
    log "Python requirements unchanged; skipping pip install"
fi
if ! printf '%s\n' "$CURRENT_COMMIT" > "$DEPENDENCY_COMMIT_FILE"; then
    log "ERROR: unable to save dependency check commit"
    exit 1
fi
log "Dependency check recorded for commit $CURRENT_COMMIT"

# run webcam cycler
log "Starting Python app: $APP_DIR/main.py"
nohup python "$APP_DIR/main.py" </dev/null >> "$LOGFILE" 2>&1 &
APP_PID=$!
if ! printf '%s\n' "$APP_PID" > "$PIDFILE"; then
    log "ERROR: unable to write app PID file"
    exit 1
fi
log "Python app launched with PID $APP_PID; checking startup"
sleep 2
if ! kill -0 "$APP_PID" 2>/dev/null; then
    log "ERROR: Python app process $APP_PID exited during startup; see preceding Python output"
    exit 1
fi
log "Python app process $APP_PID is running"

# give the Raspberry Pi desktop and display session time to finish starting
log "Waiting ${CHROMIUM_STARTUP_DELAY_SECONDS}s for the Raspberry Pi display to settle before starting Chromium"
sleep "$CHROMIUM_STARTUP_DELAY_SECONDS"

# use software rendering because Chromium's GPU process fails on this Pi setup
# open Chromium in kiosk mode to hide browser controls and fill the display
CHROMIUM_BIN="$(command -v chromium)" || {
    log "ERROR: chromium executable was not found on PATH"
    exit 1
}
log "Recording Chromium diagnostics in $CHROMIUM_LOGFILE"
{
    printf '\n[%s] ===== Chromium launch diagnostics =====\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')"
    "$CHROMIUM_BIN" --version
    if command -v free >/dev/null 2>&1; then
        free -h
    fi
    if command -v df >/dev/null 2>&1; then
        df -h /dev/shm
    fi
} >> "$CHROMIUM_LOGFILE" 2>&1

log "Starting Chromium watchdog with X11 and software rendering"
nohup bash "$APP_DIR/rpiWatchdog.sh" \
    "$CHROMIUM_BIN" "$LOGFILE" "$CHROMIUM_LOGFILE" "$WATCHDOG_PIDFILE" \
    --ozone-platform=x11 --disable-gpu --disable-gpu-compositing \
    --disable-gpu-rasterization --disable-accelerated-video-decode \
    --disable-accelerated-video-encode --kiosk --incognito --no-first-run \
    --disable-infobars --password-store="basic" \
    http://127.0.0.1:5050 </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!
if ! printf '%s\n' "$WATCHDOG_PID" > "$WATCHDOG_PIDFILE"; then
    log "ERROR: unable to write Chromium watchdog PID file"
    exit 1
fi
log "Chromium watchdog launched (PID $WATCHDOG_PID); checking startup"
sleep 10
if kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    log "Chromium watchdog process $WATCHDOG_PID is still running"
else
    wait "$WATCHDOG_PID"
    WATCHDOG_STATUS=$?
    log "ERROR: Chromium watchdog exited during startup with status $WATCHDOG_STATUS; see $CHROMIUM_LOGFILE"
fi

cleanup () {
	log "Cleanup started"
	if [[ -n "$WATCHDOG_PID" ]] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
		kill "$WATCHDOG_PID"
		log "Stopped Chromium watchdog process $WATCHDOG_PID"
	fi
	if pkill chromium 2>/dev/null; then
		log "Stopped Chromium"
	fi
	if pkill ffmpeg 2>/dev/null; then
		log "Stopped FFmpeg"
	fi
	if pkill threadfin 2>/dev/null; then
		log "Stopped Threadfin"
	fi
	if [[ -f "$PIDFILE" ]]; then
		APP_PID="$(cat "$PIDFILE")"
		APP_COMMAND=''
		if [[ "$APP_PID" =~ ^[0-9]+$ ]] && [[ -r "/proc/$APP_PID/cmdline" ]]; then
			APP_COMMAND="$(tr '\0' ' ' < "/proc/$APP_PID/cmdline")"
		fi
		if [[ "$APP_COMMAND" == *"$APP_DIR/main.py"* ]] && kill -0 "$APP_PID" 2>/dev/null; then
			kill "$APP_PID"
			log "Stopped Python app process $APP_PID"
		fi
		rm -f "$PIDFILE"
	fi
	log "Cleanup complete"
}

trap 'cleanup; exit 0' SIGINT SIGTSTP SIGTERM

log "Startup procedure complete; app and Chromium watchdog remain detached (PIDs $APP_PID, $WATCHDOG_PID)"
