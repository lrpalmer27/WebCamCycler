# What is this?
This is a webcam cycler that flips through webcams of places that I like. 

The conceptual idea comes from a live photo frame that I was recently gifted by my family. The live photo frame flips through photos added by family members, like a slideshow.

This project flips through various live web cameras in places that I like.

## Running and checking the cameras

### Start locally on Windows

Double-click `run_local.bat` (or run it from Command Prompt). It starts the
viewer at `http://127.0.0.1:5050/`; open that address in Chrome or your preferred
browser. The script uses the project's `.venv` Python if present, or the
`python` command on your PATH. If you need to install dependencies first, open
a terminal in the project folder and run:

```
python -m pip install -r requirements.txt
```

The server runs in a separate minimized console window; close that window to
stop it. If the server is already responding on port `5050`, the command reuses
it. You can also run `python main.py` directly; on Windows that opens the
viewer in your default browser.

The local launcher enables development reload: saving Python files or the
camera CSV restarts the Flask development server automatically, and saving the
viewer template, JavaScript, or CSS refreshes the browser page. Keep the viewer
open while editing; changes normally appear within a second or two. The first
time you switch from an already-running non-development server, close its
server window once and run `run_local.bat` again. Raspberry Pi startup remains
in production mode with development reload disabled.

This local setup runs the same Flask app, camera list, and viewer as the Pi, but
does not launch the Pi startup scripts, kiosk mode, scheduled services, or
hardware-specific mouse automation. Camera video is loaded directly from its
third-party provider, so your PC needs internet access and some feeds may not
be embeddable or available.

### Check the camera list and server

- `http://127.0.0.1:5050/health/` reports whether the app is running and how
  many camera entries it loaded.
- `http://127.0.0.1:5050/cameras/` lists every configured camera name and
  playback type. It is useful for confirming that the entries in
  `WebcamURLs_All.csv` were loaded.
- `http://127.0.0.1:5050/` opens the viewer.

At server startup, the camera list is shuffled once into a random order. The
viewer then advances through every camera in that order before repeating it.
Use the left and right edge click areas (or Left/Right arrow keys) to move
backward or forward within that same order; navigation wraps at both ends.
Restarting the server creates a new random order.

For timed automatic switches, the viewer loads at most one next camera in a
hidden, muted player while the current stream is showing, then crossfades when
it is ready. A timed-out preload is stopped before another candidate is tried;
staging HLS buffers are kept smaller to limit memory use. Each automatic
candidate has up to 12 seconds to become ready; if it doesn't, the viewer skips
it and tries the next camera in the randomized order. Embedded feeds are loaded
in advance, though their providers do not always expose when playback is
actually ready. Manual side-clicks do not wait for preloading: they immediately
select and display the chosen stream. If every feed is unavailable, the current
display is kept and the viewer retries shortly. Preloading uses extra bandwidth
and may not avoid a delay for a slow or unavailable feed.

The camera list is validated at startup. Missing columns, blank values,
unsupported playback types, invalid URLs, and unknown time zones are reported
instead of producing hard-to-diagnose playback errors later. If an HLS feed
fails or stalls, the viewer attempts recovery and then moves on to another
camera. Network and playback errors appear in the overlay and are logged in the
browser console.

Camera feeds are hosted by third parties, so a valid entry in `/cameras/` does
not guarantee that its provider is currently online or permits embedding.
Check the browser console and the provider's page if one specific feed remains
unavailable.

## How is auto-boot setup?
Basic instructions from: https://www.youtube.com/watch?v=-L1TetCc-oc
                        https://fuzzthepiguy.tech/browser-gui/

added a startup line to /etc/xdg/lxsession/LXDE-pi/autostart

```
@lxterminal -e bash /home/logan/Desktop/WebCamCycler/rpiStart.sh &
```

`rpiStart.sh` activates the project's `.venv`, installs or updates dependencies
from `PIRequirements.txt`, starts `main.py`, and opens the kiosk browser and
streaming helpers. Create the virtual environment once before enabling
auto-boot:

```
cd /home/logan/Desktop/WebCamCycler
python3 -m venv .venv
```

The startup script uses the project path shown above; update `APP_DIR` in
`rpiStart.sh` if the project is installed elsewhere.

## Rotate Display
Because of the wiring direction on the pi, I want the screen to be 'upside down'. To flip the display output: 
```
sudo nano /boot/config.txt
```
comment out this line: 
```
# dtoverlay=vc4-kms-vd3
```
add this line, to the bottom of the config.txt file, to flip display 180 degrees: 
```
lcd_rotate=2
```

# Hardware
Computer: Raspberry Pi 3B+ Trixie
Display: Raspberry Pi 7" touchscreen
Display mount: Custom bent 16Ga cold-rolled 1008 carbon steel sheet

## Pictures of final build
<img height="350" src="Pictures/Render1.png"/> <img height="350" src="Pictures/Render3.png"/> 

<img height="350" src="Pictures/IMG_6300.JPG"/> <img height="350" src="Pictures/IMG_6301.JPG"/> 

The mounting method uses 4x M3x0.5x8mm phillips button head bolts, as shown, they are too long for this applicaton, but that is what I had on hand. Instead of buying new bolts, or washers, I decided to make a 'washer' from some cardboard. It doesnt look great, but performs the needed function and is on the 'B' side; no harm, no foul.

<img height="350" src="Pictures/IMG_6302.JPG"/>


## Tests

Run the camera-list and route tests on your PC with:

```
python -m unittest discover -s tests
```