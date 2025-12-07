#!/bin/bash

# setup same logfile 
cd /home/logan/Desktop/WebCamViewer
LOGFILE='/home/logan/Desktop/WebCamViewer/logs/logfile.txt'

echo "rpiScheduledReboots.sh running @ $(date "+%r")" >> "$LOGFILE"

# run on main display 
export DISPLAY=:0

# reboot every 6h
RESETTIME="$(date -d "+6 hour")"
echo "Rebooting in 6h, at $RESETTIME" | tee -a "$LOGFILE"

# do the actual waiting here
sleep 6h
echo "Done Sleeping. Current time $(date "+%r"). Rebooting now" | tee -a "$LOGFILE"
sudo reboot