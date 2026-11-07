#!/bin/bash

APP_DIR='/home/logan/Desktop/WebCamCycler'
LOG_DIR="$APP_DIR/logs"
LOGFILE="$LOG_DIR/logfile.txt"
FIREFOX_LOGFILE="$LOG_DIR/firefox.log"
PIDFILE="$LOG_DIR/webcam-cycler.pid"
WATCHDOG_PIDFILE="$LOG_DIR/webcam-cycler-watchdog.pid"
DEPENDENCY_COMMIT_FILE="$LOG_DIR/dependencies-commit"
REQUIREMENTS_FILE="$APP_DIR/PIRequirements.txt"
FIREFOX_ROOT="$HOME/.local/opt/webcamcycler-firefox-mozilla/firefox"
FIREFOX_RUNTIME_ROOT="$HOME/.local/opt/webcamcycler-firefox-runtime/usr/lib/aarch64-linux-gnu"
FIREFOX_BIN="$FIREFOX_ROOT/firefox"
FIREFOX_PROFILE_DIR="$HOME/.local/share/webcamcycler/firefox-profile"
FIREFOX_STARTUP_DELAY_SECONDS=20
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

if [[ ! -x "$FIREFOX_BIN" ]]; then
    log "ERROR: Firefox is not installed at $FIREFOX_BIN; see the Firefox setup instructions in README.md"
    exit 1
fi
if [[ ! -r "$FIREFOX_RUNTIME_ROOT/libnss3.so" || ! -r "$FIREFOX_RUNTIME_ROOT/libnspr4.so" ]]; then
    log "ERROR: Firefox's user-local NSS/NSPR libraries are missing under $FIREFOX_RUNTIME_ROOT"
    exit 1
fi

if [[ -r "$WATCHDOG_PIDFILE" ]]; then
    OLD_WATCHDOG_PID="$(cat "$WATCHDOG_PIDFILE")"
    OLD_WATCHDOG_COMMAND=''
    if [[ "$OLD_WATCHDOG_PID" =~ ^[0-9]+$ ]] \
        && [[ -r "/proc/$OLD_WATCHDOG_PID/cmdline" ]]; then
        OLD_WATCHDOG_COMMAND="$(tr '\0' ' ' < "/proc/$OLD_WATCHDOG_PID/cmdline")"
    fi
    if [[ "$OLD_WATCHDOG_COMMAND" == *"$APP_DIR/rpiWatchdog.sh"* ]] \
        && kill -0 "$OLD_WATCHDOG_PID" 2>/dev/null; then
        log "Stopping previous browser watchdog (PID $OLD_WATCHDOG_PID)"
        if ! kill "$OLD_WATCHDOG_PID"; then
            log "ERROR: could not stop previous browser watchdog"
            exit 1
        fi
        sleep 2
    fi
fi

# retain the display session inherited from the desktop; use :0 as fallback
export DISPLAY="${DISPLAY:-:0}"
log "Display environment: DISPLAY=$DISPLAY, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-not set}, XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-not set}, XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-not set}"
LOCAL_XDOTOOL_ROOT="$HOME/.local/opt/webcamcycler-xdotool/usr"
if [[ -x "$LOCAL_XDOTOOL_ROOT/bin/xdotool" ]]; then
    export PATH="$LOCAL_XDOTOOL_ROOT/bin:$PATH"
    LOCAL_XDOTOOL_LIBRARY_PATH=''
    for library_dir in "$LOCAL_XDOTOOL_ROOT"/lib/*; do
        if [[ -d "$library_dir" ]]; then
            if [[ -z "$LOCAL_XDOTOOL_LIBRARY_PATH" ]]; then
                LOCAL_XDOTOOL_LIBRARY_PATH="$library_dir"
            else
                LOCAL_XDOTOOL_LIBRARY_PATH="$LOCAL_XDOTOOL_LIBRARY_PATH:$library_dir"
            fi
        fi
    done
    if [[ -n "$LOCAL_XDOTOOL_LIBRARY_PATH" ]]; then
        export WEBCAM_CYCLER_XDOTOOL_LIBRARY_PATH="$LOCAL_XDOTOOL_LIBRARY_PATH"
    fi
fi
if ! command -v xdotool >/dev/null 2>&1; then
    log "WARNING: xdotool is unavailable; NTV camera activation requires 'sudo apt install xdotool'"
fi

for browser_process in chromium firefox; do
    if pkill -u "$UID" -x "$browser_process" 2>/dev/null; then
        log "Stopped existing $browser_process process"
    fi
done

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
log "Waiting ${FIREFOX_STARTUP_DELAY_SECONDS}s for the Raspberry Pi display to settle before starting Firefox"
sleep "$FIREFOX_STARTUP_DELAY_SECONDS"

if ! mkdir -p "$FIREFOX_PROFILE_DIR"; then
    log "ERROR: unable to create Firefox profile directory $FIREFOX_PROFILE_DIR"
    exit 1
fi
if ! printf '%s\n' \
    'user_pref("media.autoplay.default", 0);' \
    'user_pref("media.autoplay.blocking_policy", 0);' \
    'user_pref("media.autoplay.block-webaudio", false);' \
    'user_pref("app.update.enabled", false);' \
    > "$FIREFOX_PROFILE_DIR/user.js"; then
    log "ERROR: unable to configure Firefox kiosk preferences"
    exit 1
fi

FIREFOX_LIBRARY_PATH="$FIREFOX_RUNTIME_ROOT:$FIREFOX_ROOT"
log "Recording Firefox diagnostics in $FIREFOX_LOGFILE"
{
    printf '\n[%s] ===== Firefox launch diagnostics =====\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')"
    LD_LIBRARY_PATH="$FIREFOX_LIBRARY_PATH" "$FIREFOX_BIN" --version
    if command -v free >/dev/null 2>&1; then
        free -h
    fi
    if command -v df >/dev/null 2>&1; then
        df -h /dev/shm
    fi
} >> "$FIREFOX_LOGFILE" 2>&1

log "Starting Firefox watchdog on X11"
nohup bash "$APP_DIR/rpiWatchdog.sh" \
    "$FIREFOX_BIN" "$LOGFILE" "$FIREFOX_LOGFILE" "$WATCHDOG_PIDFILE" \
    firefox "$FIREFOX_LIBRARY_PATH" --no-remote --kiosk --private-window \
    --profile "$FIREFOX_PROFILE_DIR" \
    http://127.0.0.1:5050 </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!
if ! printf '%s\n' "$WATCHDOG_PID" > "$WATCHDOG_PIDFILE"; then
    log "ERROR: unable to write browser watchdog PID file"
    exit 1
fi
log "Firefox watchdog launched (PID $WATCHDOG_PID); checking startup"
sleep 10
if kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    log "Firefox watchdog process $WATCHDOG_PID is still running"
else
    wait "$WATCHDOG_PID"
    WATCHDOG_STATUS=$?
    log "ERROR: browser watchdog exited during startup with status $WATCHDOG_STATUS; see $FIREFOX_LOGFILE"
fi

cleanup () {
	log "Cleanup started"
	if [[ -n "$WATCHDOG_PID" ]] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
		kill "$WATCHDOG_PID"
		log "Stopped browser watchdog process $WATCHDOG_PID"
	fi
	for browser_process in chromium firefox; do
		if pkill -u "$UID" -x "$browser_process" 2>/dev/null; then
			log "Stopped $browser_process"
		fi
	done
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

log "Startup procedure complete; app and Firefox watchdog remain detached (PIDs $APP_PID, $WATCHDOG_PID)"
