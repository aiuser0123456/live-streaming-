# Dockerfile - nginx + nginx-rtmp + ffmpeg (Ubuntu base)
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential git wget ca-certificates libpcre3 libpcre3-dev zlib1g-dev libssl-dev \
    pkg-config autoconf automake libtool yasm nasm \
    ffmpeg curl python3 \
  && rm -rf /var/lib/apt/lists/*

# Build nginx + nginx-rtmp-module
ARG NGINX_VERSION=1.24.0
WORKDIR /opt

RUN wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
 && tar xzf "nginx-${NGINX_VERSION}.tar.gz"

RUN git clone --depth 1 https://github.com/arut/nginx-rtmp-module.git

WORKDIR /opt/nginx-${NGINX_VERSION}
RUN ./configure \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --with-http_ssl_module \
    --with-threads \
    --with-http_v2_module \
    --add-module=/opt/nginx-rtmp-module \
 && make -j"$(nproc)" \
 && make install

# copy configs and scripts
COPY nginx.conf /etc/nginx/nginx.conf
COPY stream_transcode.sh /usr/local/bin/stream_transcode.sh
RUN chmod +x /usr/local/bin/stream_transcode.sh

# create hls folder
RUN mkdir -p /var/www/hls && chown -R www-data:www-data /var/www/hls

EXPOSE 1935/tcp 8080/tcp 80/tcp

# Start nginx in foreground
CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
