# make sure files are saved in project folder
# give execute perms to the script
chmod +x stream_transcode.sh

# build and run (requires docker & docker-compose available in your environment)
docker compose build
docker compose up -d


docker compose logs -f rtmp
# or check ffmpeg logs
ls -la ./logs
tail -f ./logs/stream_transcode_test.log   # when streamkey is test


rtmp://<HOST_IP_OR_LOCALHOST>:1935/live
