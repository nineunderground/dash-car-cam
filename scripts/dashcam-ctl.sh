#!/usr/bin/env bash
# Dash Car Cam - Control Utility
set -euo pipefail

source /etc/dashcam/dashcam.conf 2>/dev/null || true

usage() {
    echo "Usage: dashcam-ctl <command>"
    echo ""
    echo "Commands:"
    echo "  status     Show recording/streaming status"
    echo "  record     on|off - Toggle recording"
    echo "  stream     on|off - Toggle streaming"
    echo "  snapshot   Take a still photo"
    echo "  disk       Show storage usage"
    echo "  tail       Follow dashcam logs"
    echo "  ip         Show Pi's IP address"
    echo "  config     Show current configuration"
}

case "${1:-}" in
    status)
        echo "=== Dash Car Cam Status ==="
        echo -n "Recording: "
        systemctl is-active dashcam-record 2>/dev/null || echo "inactive"
        echo -n "Streaming: "
        systemctl is-active dashcam-stream 2>/dev/null || echo "inactive"
        echo ""
        echo "Recordings: $(find "$RECORD_DIR" -name '*.mp4' 2>/dev/null | wc -l) files"
        echo "Disk: $(df -h "$RECORD_DIR" | tail -1 | awk '{print $5 " used (" $4 " free)"}')"
        ;;
    record)
        case "${2:-}" in
            on)  sudo systemctl enable --now dashcam-record; echo "Recording started" ;;
            off) sudo systemctl disable --now dashcam-record; echo "Recording stopped" ;;
            *)   echo "Usage: dashcam-ctl record on|off" ;;
        esac
        ;;
    stream)
        case "${2:-}" in
            on)
                sudo sed -i 's/STREAM_ENABLED=false/STREAM_ENABLED=true/' /etc/dashcam/dashcam.conf
                sudo systemctl enable --now dashcam-stream
                echo "Streaming started: rtsp://$(hostname -I | awk '{print $1}'):${RTSP_PORT:-8554}/dashcam"
                ;;
            off)
                sudo systemctl disable --now dashcam-stream
                sudo sed -i 's/STREAM_ENABLED=true/STREAM_ENABLED=false/' /etc/dashcam/dashcam.conf
                echo "Streaming stopped"
                ;;
            *)   echo "Usage: dashcam-ctl stream on|off" ;;
        esac
        ;;
    snapshot)
        SNAP="$RECORD_DIR/snapshot_$(date +%Y-%m-%d_%H-%M-%S).jpg"
        libcamera-still --nopreview --rotation "${ROTATION:-0}" -o "$SNAP" 2>/dev/null
        echo "Snapshot saved: $SNAP"
        ;;
    disk)
        echo "=== Storage ==="
        df -h "$RECORD_DIR" | tail -1 | awk '{print "Total: " $2 "\nUsed: " $3 " (" $5 ")\nFree: " $4}'
        echo ""
        echo "Recordings: $(du -sh "$RECORD_DIR" 2>/dev/null | cut -f1) in $(find "$RECORD_DIR" -name '*.mp4' 2>/dev/null | wc -l) files"
        OLDEST=$(find "$RECORD_DIR" -name '*.mp4' -type f -printf '%T+ %f\n' 2>/dev/null | sort | head -1 | cut -d' ' -f2-)
        NEWEST=$(find "$RECORD_DIR" -name '*.mp4' -type f -printf '%T+ %f\n' 2>/dev/null | sort -r | head -1 | cut -d' ' -f2-)
        [ -n "$OLDEST" ] && echo "Oldest: $OLDEST"
        [ -n "$NEWEST" ] && echo "Newest: $NEWEST"
        ;;
    tail)
        journalctl -u dashcam-record -u dashcam-stream -f
        ;;
    ip)
        echo "IP: $(hostname -I | awk '{print $1}')"
        echo "RTSP: rtsp://$(hostname -I | awk '{print $1}'):${RTSP_PORT:-8554}/dashcam"
        ;;
    config)
        cat /etc/dashcam/dashcam.conf
        ;;
    *)
        usage
        ;;
esac
