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
    echo "  profile    1080p|720p - Switch recording profile"
    echo "  oled       on|off - Toggle OLED display"
    echo "  config     Show current configuration"
}

case "${1:-}" in
    status)
        echo "=== Dash Car Cam Status ==="
        REC_STATUS=$(systemctl is-active dashcam-record 2>/dev/null || true)
        STREAM_STATUS=$(systemctl is-active dashcam-stream 2>/dev/null || true)
        OLED_STATUS=$(systemctl is-active dashcam-oled 2>/dev/null || true)
        echo "Recording: ${REC_STATUS:-inactive}"
        echo "Streaming: ${STREAM_STATUS:-inactive}"
        echo "OLED:      ${OLED_STATUS:-inactive}"
        echo ""
        echo "Recordings: $(find "$RECORD_DIR" -name '*.mp4' 2>/dev/null | wc -l) files"
        echo "Disk: $(df -h "$RECORD_DIR" | tail -1 | awk '{print $5 " used (" $4 " free)"}')"
        ;;
    record)
        case "${2:-}" in
            on)  sudo systemctl enable --now dashcam-record; echo "Recording started" ;;
            off)
                sudo systemctl stop dashcam-record
                sudo systemctl disable dashcam-record
                sudo systemctl reset-failed dashcam-record 2>/dev/null || true
                echo "Recording stopped"
                ;;
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
                sudo systemctl stop dashcam-stream
                sudo systemctl disable dashcam-stream
                sudo systemctl reset-failed dashcam-stream 2>/dev/null || true
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
    profile)
        case "${2:-}" in
            1080p|720p|usb-1080p|usb-720p)
                PROF="/etc/dashcam/dashcam-${2}.conf"
                if [ -f "$PROF" ]; then
                    sudo cp "$PROF" /etc/dashcam/dashcam.conf
                    sudo systemctl restart dashcam-record 2>/dev/null || true
                    echo "Switched to ${2} profile. Recording restarted."
                else
                    echo "Profile not found: $PROF"
                fi
                ;;
            *)
                CURRENT_RES=$(grep "^RESOLUTION=" /etc/dashcam/dashcam.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
                CURRENT_CAM=$(grep "^CAMERA_TYPE=" /etc/dashcam/dashcam.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
                echo "Current: ${CURRENT_CAM} @ ${CURRENT_RES}"
                echo ""
                echo "Available profiles:"
                echo "  1080p       CSI camera, 1080p (~8h on 32GB)"
                echo "  720p        CSI camera, 720p  (~16h on 32GB)"
                echo "  usb-1080p   USB webcam, 1080p (~8h on 32GB)"
                echo "  usb-720p    USB webcam, 720p  (~16h on 32GB)"
                echo ""
                echo "Usage: dashcam-ctl profile <name>"
                ;;
        esac
        ;;
    oled)
        case "${2:-}" in
            on)
                sudo systemctl enable --now dashcam-oled
                echo "OLED display enabled"
                ;;
            off)
                sudo systemctl disable --now dashcam-oled
                echo "OLED display disabled"
                ;;
            *)
                echo "OLED: $(systemctl is-active dashcam-oled 2>/dev/null || echo inactive)"
                echo "Usage: dashcam-ctl oled on|off"
                ;;
        esac
        ;;
    config)
        cat /etc/dashcam/dashcam.conf
        ;;
    *)
        usage
        ;;
esac
