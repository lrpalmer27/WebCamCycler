#!/bin/bash

cd /home/logan/Desktop/WebCamViewer
LOGFILE='/home/logan/Desktop/WebCamViewer/logs/logfile.txt'

echo 'rpiStart.sh opened' >> "$LOGFILE"

# make sure this runs on main display
export DISPLAY=:0

# kill browser
pkill chromium

#kill existing flask server on port 5050
sudo fuser -k 5050/tcp

# open scheduled reboot tool - this keeps memory useage low, so the browser doesnt crash
lxterminal -e /home/logan/Desktop/WebCamViewer/rpiScheduledReboots.sh &
echo "rpiScheduledReboots.sh opened @ $(date "+%r")" >> "$LOGFILE"

# open chromium full screen 
chromium-browser --start-fullscreen --incognito --app http://localhost:5050 &

# start venv
source /home/logan/Desktop/WebCamViewer/myvenv/bin/activate

# run webcam cycler
python /home/logan/Desktop/WebCamViewer/main.py &
echo "python file opened" | tee -a "$LOGFILE"

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

read HoldOpen

cleanup () {
	echo 'Cleaning up program and shutting down' >> "$LOGFILE"
	pkill chromium
	sudo fuser -k 5050/tcp
}

trap cleanup SIGINT
trap cleanup SIGTSTP

