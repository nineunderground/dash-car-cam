#!/usr/bin/env bash
# Dash Car Cam - RTSP Streaming Script
# Streams camera feed via mediamtx RTSP server
set -euo pipefail

source /etc/dashcam/dashcam.conf

if [ "$STREAM_ENABLED" != "true" ]; then
    echo "[dashcam-stream] Streaming is disabled in config. Exiting."
    exit 0
fi

MEDIAMTX_BIN="/usr/local/bin/mediamtx"
MEDIAMTX_CONF="/etc/dashcam/mediamtx.yml"

# Generate mediamtx config if not present
if [ ! -f "$MEDIAMTX_CONF" ]; then
    cat > "$MEDIAMTX_CONF" <<EOF
rtspAddress: :${RTSP_PORT}
paths:
  dashcam:
    source: publisher
    sourceOnDemand: no
EOF
fi

echo "[dashcam-stream] Starting RTSP server on port $RTSP_PORT"

# Start mediamtx in background
$MEDIAMTX_BIN "$MEDIAMTX_CONF" &
MEDIAMTX_PID=$!
sleep 2

echo "[dashcam-stream] Streaming: rtsp://$(hostname -I | awk '{print $1}'):${RTSP_PORT}/dashcam"

# Feed camera into mediamtx via ffmpeg → RTSP
libcamera-vid \
    --width "${STREAM_RESOLUTION%x*}" \
    --height "${STREAM_RESOLUTION#*x}" \
    --framerate "$STREAM_FPS" \
    --bitrate "$STREAM_BITRATE" \
    --codec h264 \
    --inline \
    --nopreview \
    --rotation "$ROTATION" \
    --timeout 0 \
    -o - 2>/dev/null | \
ffmpeg -re \
    -i - \
    -c:v copy \
    -f rtsp \
    "rtsp://127.0.0.1:${RTSP_PORT}/dashcam" 2>/dev/null

# Cleanup
kill $MEDIAMTX_PID 2>/dev/null || true
