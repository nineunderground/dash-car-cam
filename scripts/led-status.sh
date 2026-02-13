#!/usr/bin/env bash
# Dash Car Cam - LED Status Indicator (optional)
# Requires: GPIO LEDs on pins 17 (red) and 27 (green)
set -euo pipefail

source /etc/dashcam/dashcam.conf

if [ "$LED_ENABLED" != "true" ]; then
    exit 0
fi

GPIO_BASE="/sys/class/gpio"

setup_pin() {
    local pin=$1
    if [ ! -d "$GPIO_BASE/gpio$pin" ]; then
        echo "$pin" > "$GPIO_BASE/export"
        sleep 0.1
    fi
    echo "out" > "$GPIO_BASE/gpio$pin/direction"
}

set_led() {
    local pin=$1 state=$2
    echo "$state" > "$GPIO_BASE/gpio$pin/value"
}

setup_pin "$LED_RED_PIN"
setup_pin "$LED_GREEN_PIN"

while true; do
    RECORDING=$(systemctl is-active dashcam-record 2>/dev/null || true)
    STREAMING=$(systemctl is-active dashcam-stream 2>/dev/null || true)
    DISK_PERCENT=$(df "$RECORD_DIR" | tail -1 | awk '{print $5}' | tr -d '%')

    # Red LED: recording status
    if [ "$RECORDING" = "active" ]; then
        if [ "$DISK_PERCENT" -ge 80 ]; then
            # Blink red when storage is high
            set_led "$LED_RED_PIN" 1; sleep 0.5
            set_led "$LED_RED_PIN" 0; sleep 0.5
            continue
        else
            set_led "$LED_RED_PIN" 1
        fi
    else
        set_led "$LED_RED_PIN" 0
    fi

    # Green LED: streaming status
    if [ "$STREAMING" = "active" ]; then
        set_led "$LED_GREEN_PIN" 1
    else
        set_led "$LED_GREEN_PIN" 0
    fi

    sleep 2
done
