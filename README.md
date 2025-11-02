# WHAT IS THIS?
This is a webcam cycler that flips through webcams of places that I like. 

The conceptual idea comes from a live photo frame that I was recently gifted by my family. The live photo frame flips through photos added by family members, like a slideshow.

This project flips through various live web cameras in places that I like.

# How is auto-boot setup?
Basic instructions from: https://www.youtube.com/watch?v=-L1TetCc-oc
                        https://fuzzthepiguy.tech/browser-gui/


added a startup line to /etc/xdg/lxsession/LXDE-pi/autostart

# Hardware
Display: Raspberry Pi 7" touchscreen
Computer: Raspberry Pi 3B+ Bullseye

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


# TODO: 
    - Convert the current .csv to .db and extract video locations, time offsets, URLs with SQL query.
    - Make a frame for RPI + screen.
    - Add touchscreen buttons to go forward and backwards in recent videos