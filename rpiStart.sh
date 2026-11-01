#!/bin/bash

APP_DIR='/home/logan/Desktop/WebCamViewer'
LOG_DIR="$APP_DIR/logs"
LOGFILE="$LOG_DIR/logfile.txt"
PIDFILE="$LOG_DIR/webcam-cycler.pid"

cd "$APP_DIR" || exit 1
mkdir -p "$LOG_DIR"

echo 'rpiStart.sh opened' >> "$LOGFILE"

# make sure this runs on main display
export DISPLAY=:0

# kill browser
pkill chromium

# stop the previously recorded Flask process if it is still running
if [[ -f "$PIDFILE" ]]; then
    OLD_PID="$(cat "$PIDFILE")"
    OLD_COMMAND=''
    if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && [[ -r "/proc/$OLD_PID/cmdline" ]]; then
        OLD_COMMAND="$(tr '\0' ' ' < "/proc/$OLD_PID/cmdline")"
    fi
    if [[ "$OLD_COMMAND" == *"$APP_DIR/main.py"* ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID"
        sleep 2
    fi
fi

# start venv
source "$APP_DIR/.venv/bin/activate" || exit 1

# install/update app dependencies after pulling changes
python -m pip install -r "$APP_DIR/PIRequirements.txt" >> "$LOGFILE" 2>&1 || exit 1

# run webcam cycler
python "$APP_DIR/main.py" >> "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"
echo "python file opened with PID $(cat "$PIDFILE")" | tee -a "$LOGFILE"

# open chromium full screen 
chromium --start-fullscreen --incognito --app http://localhost:5050 &

## -- this section has things for local streaming. Workflow is flask hosting of webpage, ffmpeg to watch (record) the browser, threadfin serves to plex
# restart threadfin 
lxterminal -e /home/logan/threadfin/threadfin &
lxterminal -e bash -c "$APP_DIR/ffmpeg.sh" &
lxterminal -e bash -c "$APP_DIR/httpserver.sh" &

# Get the screen resolution using xrandr
# The output is parsed to extract the width and height of the primary display.
RESOLUTION=$(xrandr | grep '*' | awk '{print $1}')
SCREEN_WIDTH=$(echo $RESOLUTION | cut -d 'x' -f1)
SCREEN_HEIGHT=$(echo $RESOLUTION | cut -d 'x' -f2)

# Calculate the center coordinates
CENTER_X=$((SCREEN_WIDTH / 2))
CENTER_Y=$((SCREEN_HEIGHT / 2))

# Move the mouse cursor to the center coordinates and click
# The `mousemove` command moves the cursor without clicking.
# The `click 1` command simulates a left mouse button click.
xdotool mousemove $CENTER_X $CENTER_Y click 1
xdotool mousemove_relative 20 20 click 1
xdotool mousemove $CENTER_X $CENTER_Y click 1

echo 'clicked center'  | tee -a "$LOGFILE"

cleanup () {
	echo 'Cleaning up program and shutting down' >> "$LOGFILE"
	pkill chromium
	pkill ffmpeg
	pkill threadfin
	if [[ -f "$PIDFILE" ]]; then
		APP_PID="$(cat "$PIDFILE")"
		APP_COMMAND=''
		if [[ "$APP_PID" =~ ^[0-9]+$ ]] && [[ -r "/proc/$APP_PID/cmdline" ]]; then
			APP_COMMAND="$(tr '\0' ' ' < "/proc/$APP_PID/cmdline")"
		fi
		if [[ "$APP_COMMAND" == *"$APP_DIR/main.py"* ]] && kill -0 "$APP_PID" 2>/dev/null; then
			kill "$APP_PID"
		fi
		rm -f "$PIDFILE"
	fi
}

trap cleanup SIGINT
trap cleanup SIGTSTP

read HoldOpen
