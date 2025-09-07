#!/bin/bash

# make sure this runs on main display
export DISPLAY=:0

# kill browser
pkill chromium

# open chromium full screen 
chromium-browser --start-fullscreen http://localhost:5000 &

# start venv
source myvenv/bin/activate

# run webcam cycler
python main.py



