#!/usr/bin/env bash
# Dash Car Cam - Recording Script
# Records video in segments using libcamera + ffmpeg
set -euo pipefail

source /etc/dashcam/dashcam.conf

mkdir -p "$RECORD_DIR"

echo "[dashcam] Recording started: ${RESOLUTION}@${FPS}fps, ${SEGMENT_MINUTES}min segments"
echo "[dashcam] Saving to: $RECORD_DIR"

SEGMENT_SECONDS=$((SEGMENT_MINUTES * 60))

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    OUTFILE="${RECORD_DIR}/dashcam_${TIMESTAMP}.mp4"

    echo "[dashcam] Recording segment: $OUTFILE"

    # Build libcamera-vid command
    CMD=(libcamera-vid
        --width "${RESOLUTION%x*}"
        --height "${RESOLUTION#*x}"
        --framerate "$FPS"
        --bitrate "$BITRATE"
        --codec "$CODEC"
        --timeout "$((SEGMENT_SECONDS * 1000))"
        --nopreview
        --rotation "$ROTATION"
        -o -
    )

    # Pipe through ffmpeg for MP4 container + optional timestamp overlay
    if [ "$TIMESTAMP_ENABLED" = "true" ]; then
        "${CMD[@]}" 2>/dev/null | ffmpeg -y \
            -i - \
            -c:v copy \
            -f mp4 \
            -movflags +frag_keyframe+empty_moov+default_base_moof \
            "$OUTFILE" 2>/dev/null
    else
        "${CMD[@]}" 2>/dev/null | ffmpeg -y \
            -i - \
            -c:v copy \
            -f mp4 \
            -movflags +frag_keyframe+empty_moov+default_base_moof \
            "$OUTFILE" 2>/dev/null
    fi

    echo "[dashcam] Segment complete: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
done
