#!/usr/bin/env bash
# stream_transcode.sh <stream_key>
set -euo pipefail

NAME="$1"
BASE="/var/www/hls/${NAME}"
mkdir -p "${BASE}/480p"
chown -R www-data:www-data "${BASE}"
chmod -R 755 "${BASE}"

LOG="/var/log/stream_transcode_${NAME}.log"
exec >> "${LOG}" 2>&1

echo "[$(date)] Starting ffmpeg for stream ${NAME}"

HLS_TIME=4                       # 4s segments
HLS_DVR_MINUTES=20               # 20 minutes DVR
HLS_LIST_SIZE=$((HLS_DVR_MINUTES*60 / HLS_TIME))

# Single 480p output (you asked to keep 480p only for now)
ffmpeg -hide_banner -loglevel warning \
  -i "rtmp://127.0.0.1:1935/live/${NAME}" \
  -preset veryfast -g 48 -sc_threshold 0 \
  -map v:0 -map a:0 -c:v libx264 -b:v 1200k -s 854x480 -c:a aac -b:a 96k \
  -f hls -hls_time ${HLS_TIME} -hls_list_size ${HLS_LIST_SIZE} -hls_flags delete_segments \
  -hls_segment_filename "${BASE}/480p/seg_%05d.ts" "${BASE}/480p/index.m3u8" &

# create master playlist that points to 480p only
cat > "${BASE}/master.m3u8" <<MASTER
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480
480p/index.m3u8
MASTER

wait
