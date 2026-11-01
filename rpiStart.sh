#!/bin/bash

cd /home/logan/Desktop/WebCamViewer
mkdir -p logs
LOGFILE='/home/logan/Desktop/WebCamViewer/logs/logfile.txt'
PIDFILE='/home/logan/Desktop/WebCamViewer/logs/webcam-cycler.pid'

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
    if [[ "$OLD_COMMAND" == *'/home/logan/Desktop/WebCamViewer/main.py'* ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID"
        sleep 2
    fi
fi

# monitor the Flask health endpoint instead of rebooting the Pi every six hours
bash /home/logan/Desktop/WebCamViewer/rpiHealthWatchdog.sh >> "$LOGFILE" 2>&1 &
WATCHDOG_PID=$!
echo "rpiHealthWatchdog.sh opened with PID $WATCHDOG_PID" >> "$LOGFILE"

# start venv
source /home/logan/Desktop/WebCamViewer/myvenv/bin/activate

# run webcam cycler
python /home/logan/Desktop/WebCamViewer/main.py >> "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"
echo "python file opened with PID $(cat "$PIDFILE")" | tee -a "$LOGFILE"

# open chromium full screen 
chromium-browser --start-fullscreen --incognito --app http://localhost:5050 &

## -- this section has things for local streaming. Workflow is flask hosting of webpage, ffmpeg to watch (record) the browser, threadfin serves to plex
# restart threadfin 
lxterminal -e /home/logan/threadfin/threadfin &
lxterminal -e bash -c /home/logan/Desktop/WebCamViewer/ffmpeg.sh &
lxterminal -e bash -c /home/logan/Desktop/WebCamViewer/httpserver.sh &

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
	if kill -0 "$WATCHDOG_PID" 2>/dev/null; then
		kill "$WATCHDOG_PID"
		wait "$WATCHDOG_PID" 2>/dev/null
	fi
	pkill chromium
	pkill ffmpeg
	pkill threadfin
	if [[ -f "$PIDFILE" ]]; then
		APP_PID="$(cat "$PIDFILE")"
		APP_COMMAND=''
		if [[ "$APP_PID" =~ ^[0-9]+$ ]] && [[ -r "/proc/$APP_PID/cmdline" ]]; then
			APP_COMMAND="$(tr '\0' ' ' < "/proc/$APP_PID/cmdline")"
		fi
		if [[ "$APP_COMMAND" == *'/home/logan/Desktop/WebCamViewer/main.py'* ]] && kill -0 "$APP_PID" 2>/dev/null; then
			kill "$APP_PID"
		fi
		rm -f "$PIDFILE"
	fi
}

trap cleanup SIGINT
trap cleanup SIGTSTP

read HoldOpen
