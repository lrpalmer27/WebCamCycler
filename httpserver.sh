#!/bin/bash

cd ~/hls_stream
python -m http.server 8000 --bind 192.168.1.69 

read HoldOpen