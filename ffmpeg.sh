#!/bin/bash

mkdir -p ~/hls_stream

ffmpeg -re \
-f x11grab \
-video_size 800x480 \
-framerate 30 \
-i :0.0 \
-c:v libx264 \
-preset ultrafast \
-tune zerolatency \
-pix_fmt yuv420p \
-f hls \
-hls_time 1 \
-hls_list_size 5 \
-hls_flags delete_segments \
~/hls_stream/stream.m3u8