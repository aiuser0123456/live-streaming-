#!/usr/bin/env bash
set -euo pipefail

# Run as root or with sudo
# Usage: sudo bash install_nginx_rtmp_ffmpeg.sh

NGINX_VERSION="1.24.0"
WORKDIR="/tmp/nginx-build"
RTMP_REPO="https://github.com/arut/nginx-rtmp-module.git"

echo "==> Installing prerequisites..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y build-essential libpcre3 libpcre3-dev zlib1g-dev libssl-dev git wget ca-certificates pkg-config

echo "==> Installing ffmpeg (static build if available)..."
# Try apt first (fast). If not recent enough, you may install from static builds manually.
apt install -y ffmpeg || true

# Build NGINX with nginx-rtmp-module
echo "==> Preparing build dir..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "==> Downloading nginx..."
wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
tar xzf "nginx-${NGINX_VERSION}.tar.gz"

echo "==> Cloning nginx-rtmp-module..."
git clone --depth 1 "$RTMP_REPO" nginx-rtmp-module

echo "==> Configuring & building nginx..."
cd "nginx-${NGINX_VERSION}"
./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --with-http_ssl_module \
  --with-threads \
  --with-http_v2_module \
  --add-module=../nginx-rtmp-module
make -j"$(nproc)"
make install

echo "==> Creating www folder for HLS..."
mkdir -p /var/www/hls
chown -R www-data:www-data /var/www/hls
chmod -R 755 /var/www/hls

echo "==> Installing systemd service for nginx..."
cat >/lib/systemd/system/nginx.service <<'EOF'
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=/usr/sbin/nginx -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx
systemctl restart nginx || true

echo "==> Copying helper script location (/usr/local/bin/stream_transcode.sh)..."
cat >/usr/local/bin/stream_transcode.sh <<'EOF'
#!/usr/bin/env bash
# stream_transcode.sh <stream_key>
set -euo pipefail
NAME="$1"
BASE="/var/www/hls/${NAME}"
mkdir -p "${BASE}/720p" "${BASE}/480p" "${BASE}/360p"
chown -R www-data:www-data "${BASE}"
chmod -R 755 "${BASE}"

# Create / update master playlist; paths are relative so served client sees them correctly.
cat > "${BASE}/master.m3u8" <<MASTER
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480
480p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360p/index.m3u8
MASTER

# Logging
LOG="/var/log/stream_transcode_${NAME}.log"
exec >> "${LOG}" 2>&1

echo "Starting ffmpeg for stream ${NAME} at $(date)"

# Parameters
HLS_TIME=4                   # segment length in seconds
# For 3 hours DVR -> 3*3600 / HLS_TIME segments
HLS_LIST_SIZE=$((3*3600 / HLS_TIME))

# Start ffmpeg - transcode into 3 HLS outputs
ffmpeg -hide_banner -loglevel warning \
  -i "rtmp://127.0.0.1:1935/live/${NAME}" \
  -preset veryfast -g 48 -sc_threshold 0 \
  \
  -map v:0 -map a:0 -c:v:0 libx264 -b:v:0 2500k -s:v:0 1280x720 -c:a:0 aac -b:a:0 128k \
  -f hls -hls_time ${HLS_TIME} -hls_list_size ${HLS_LIST_SIZE} -hls_flags delete_segments -hls_segment_filename "${BASE}/720p/seg_%05d.ts" "${BASE}/720p/index.m3u8" \
  \
  -map v:0 -map a:0 -c:v:1 libx264 -b:v:1 1200k -s:v:1 854x480 -c:a:1 aac -b:a:1 96k \
  -f hls -hls_time ${HLS_TIME} -hls_list_size ${HLS_LIST_SIZE} -hls_flags delete_segments -hls_segment_filename "${BASE}/480p/seg_%05d.ts" "${BASE}/480p/index.m3u8" \
  \
  -map v:0 -map a:0 -c:v:2 libx264 -b:v:2 600k -s:v:2 640x360 -c:a:2 aac -b:a:2 64k \
  -f hls -hls_time ${HLS_TIME} -hls_list_size ${HLS_LIST_SIZE} -hls_flags delete_segments -hls_segment_filename "${BASE}/360p/seg_%05d.ts" "${BASE}/360p/index.m3u8"
EOF

chmod +x /usr/local/bin/stream_transcode.sh

echo "==> Creating log dir..."
mkdir -p /var/log
touch /var/log/stream_transcode.log
chown -R www-data:www-data /var/log

echo "==> Done. Please edit /etc/nginx/nginx.conf (we provide a recommended config) and restart nginx."
