#!/bin/bash

APP_DIR='/home/logan/Desktop/WebCamCycler'
LOG_DIR="$APP_DIR/logs"
LOGFILE="$LOG_DIR/logfile.txt"
PIDFILE="$LOG_DIR/webcam-cycler.pid"
DEPENDENCY_COMMIT_FILE="$LOG_DIR/dependencies-commit"
REQUIREMENTS_FILE="$APP_DIR/PIRequirements.txt"

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

# make sure this runs on main display
export DISPLAY=:0
log "DISPLAY set to $DISPLAY"

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

# open chromium full screen 
log "Launching Chromium kiosk"
chromium --start-fullscreen --incognito --app http://localhost:5050 &
log "Chromium launch requested (PID $!)"

cleanup () {
	log "Cleanup started"
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

trap cleanup SIGINT
trap cleanup SIGTSTP

log "Startup procedure complete; app remains detached in the background (PID $APP_PID)"
