#!/usr/bin/env bash
# Dash Car Cam - RTSP Streaming Script
# Supports both CSI cameras (libcamera) and USB webcams (V4L2)
set -euo pipefail

source /etc/dashcam/dashcam.conf

if [ "$STREAM_ENABLED" != "true" ]; then
    echo "[dashcam-stream] Streaming is disabled in config. Exiting."
    exit 0
fi

CAMERA_TYPE="${CAMERA_TYPE:-csi}"
USB_DEVICE="${USB_DEVICE:-/dev/video0}"
MEDIAMTX_BIN="/usr/local/bin/mediamtx"
MEDIAMTX_CONF="/tmp/dashcam-mediamtx.yml"

# Always regenerate mediamtx config (no root permissions needed)
cat > "$MEDIAMTX_CONF" <<EOF
rtspAddress: :${RTSP_PORT}
paths:
  dashcam:
    source: publisher
    sourceOnDemand: no
EOF

echo "[dashcam-stream] Starting RTSP server on port $RTSP_PORT"
echo "[dashcam-stream] Camera: $CAMERA_TYPE"

# Start mediamtx in background
$MEDIAMTX_BIN "$MEDIAMTX_CONF" &
MEDIAMTX_PID=$!
sleep 2

RTSP_URL="rtsp://127.0.0.1:${RTSP_PORT}/dashcam"
echo "[dashcam-stream] Streaming: rtsp://$(hostname -I | awk '{print $1}'):${RTSP_PORT}/dashcam"

case "$CAMERA_TYPE" in
    csi)
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
            "$RTSP_URL" 2>/dev/null
        ;;
    usb)
        ffmpeg -re \
            -f v4l2 \
            -input_format mjpeg \
            -video_size "$STREAM_RESOLUTION" \
            -framerate "$STREAM_FPS" \
            -i "$USB_DEVICE" \
            -c:v libx264 \
            -preset ultrafast \
            -tune zerolatency \
            -pix_fmt yuv420p \
            -profile:v baseline \
            -level 4.0 \
            -b:v "$STREAM_BITRATE" \
            -f rtsp \
            "$RTSP_URL" 2>/dev/null
        ;;
    *)
        echo "[dashcam-stream] ERROR: Unknown CAMERA_TYPE='$CAMERA_TYPE'."
        kill $MEDIAMTX_PID 2>/dev/null || true
        exit 1
        ;;
esac

# Cleanup
kill $MEDIAMTX_PID 2>/dev/null || true
