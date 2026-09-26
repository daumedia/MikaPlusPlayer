#!/bin/bash
set -e
M=$(dirname "$0")/qa-media; mkdir -p $M/hls
V="-hide_banner -loglevel error -y -f lavfi -i testsrc2=size=480x270:rate=25"
E="-an -c:v libx264 -preset veryfast -b:v 400k -g 50"
nice -n 5 ffmpeg $V -t 360 $E -f hls -hls_time 2 -hls_list_size 0 -hls_segment_filename $M/hls/seg%03d.ts $M/hls/vod.m3u8
nice -n 5 ffmpeg $V -t 360 $E -f mpegts $M/stream.ts
for f in $M/stream.ts $M/hls/seg000.ts $M/hls/seg100.ts; do echo "$(basename $f) audio=[$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 $f)] video=[$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 $f)]"; done
ls $M/hls | wc -l; du -sh $M
