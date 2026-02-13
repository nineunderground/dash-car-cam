#!/usr/bin/env bash
# Dash Car Cam - Storage Cleanup
# Deletes oldest recordings when disk usage exceeds threshold
set -euo pipefail

source /etc/dashcam/dashcam.conf

DISK_PERCENT=$(df "$RECORD_DIR" | tail -1 | awk '{print $5}' | tr -d '%')
FREE_MB=$(df -m "$RECORD_DIR" | tail -1 | awk '{print $4}')

if [ "$DISK_PERCENT" -lt "$MAX_DISK_PERCENT" ] && [ "$FREE_MB" -gt "$MIN_FREE_MB" ]; then
    exit 0
fi

echo "[dashcam-cleanup] Disk at ${DISK_PERCENT}% (${FREE_MB}MB free). Cleaning up..."

# Delete oldest files first
DELETED=0
while [ "$DISK_PERCENT" -ge "$MAX_DISK_PERCENT" ] || [ "$FREE_MB" -le "$MIN_FREE_MB" ]; do
    OLDEST=$(find "$RECORD_DIR" -name "dashcam_*.mp4" -type f -printf '%T+ %p\n' 2>/dev/null | sort | head -1 | cut -d' ' -f2-)

    if [ -z "$OLDEST" ]; then
        echo "[dashcam-cleanup] No more files to delete!"
        break
    fi

    SIZE=$(du -h "$OLDEST" | cut -f1)
    rm -f "$OLDEST"
    echo "[dashcam-cleanup] Deleted: $(basename "$OLDEST") ($SIZE)"
    DELETED=$((DELETED + 1))

    DISK_PERCENT=$(df "$RECORD_DIR" | tail -1 | awk '{print $5}' | tr -d '%')
    FREE_MB=$(df -m "$RECORD_DIR" | tail -1 | awk '{print $4}')
done

echo "[dashcam-cleanup] Done. Removed $DELETED files. Disk now at ${DISK_PERCENT}%"
