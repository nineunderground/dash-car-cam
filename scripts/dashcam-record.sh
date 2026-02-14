#!/usr/bin/env bash
# Dash Car Cam - Recording Script
# Supports both CSI cameras (libcamera) and USB webcams (V4L2)
set -euo pipefail

source /etc/dashcam/dashcam.conf

mkdir -p "$RECORD_DIR"

SEGMENT_SECONDS=$((SEGMENT_MINUTES * 60))
CAMERA_TYPE="${CAMERA_TYPE:-csi}"
USB_DEVICE="${USB_DEVICE:-/dev/video0}"

if [ "$CAMERA_TYPE" = "usb" ]; then
    echo "[dashcam] Camera: USB ($USB_DEVICE)"
else
    echo "[dashcam] Camera: CSI (libcamera)"
fi
echo "[dashcam] Recording: ${RESOLUTION}@${FPS}fps, ${SEGMENT_MINUTES}min segments"
echo "[dashcam] Saving to: $RECORD_DIR"

record_csi() {
    local outfile="$1"

    libcamera-vid \
        --width "${RESOLUTION%x*}" \
        --height "${RESOLUTION#*x}" \
        --framerate "$FPS" \
        --bitrate "$BITRATE" \
        --codec "$CODEC" \
        --timeout "$((SEGMENT_SECONDS * 1000))" \
        --nopreview \
        --rotation "$ROTATION" \
        -o - 2>/dev/null | \
    ffmpeg -y \
        -i - \
        -c:v copy \
        -f mp4 \
        -movflags +frag_keyframe+empty_moov+default_base_moof \
        "$outfile" 2>/dev/null
}

record_usb() {
    local outfile="$1"

    ffmpeg -y \
        -f v4l2 \
        -input_format mjpeg \
        -video_size "$RESOLUTION" \
        -framerate "$FPS" \
        -i "$USB_DEVICE" \
        -c:v libx264 \
        -preset ultrafast \
        -b:v "$BITRATE" \
        -t "$SEGMENT_SECONDS" \
        -f mp4 \
        -movflags +frag_keyframe+empty_moov+default_base_moof \
        "$outfile" 2>/dev/null
}

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    OUTFILE="${RECORD_DIR}/dashcam_${TIMESTAMP}.mp4"

    echo "[dashcam] Recording segment: $OUTFILE"

    case "$CAMERA_TYPE" in
        csi)  record_csi "$OUTFILE" ;;
        usb)  record_usb "$OUTFILE" ;;
        *)
            echo "[dashcam] ERROR: Unknown CAMERA_TYPE='$CAMERA_TYPE'. Use 'csi' or 'usb'."
            exit 1
            ;;
    esac

    echo "[dashcam] Segment complete: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
done
