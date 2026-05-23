#!/bin/bash

cd ~/hls_stream
python3 -m http.server 8000 --bind 192.168.1.69 &