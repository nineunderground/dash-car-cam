#!/usr/bin/env python3
"""
Dash Car Cam - OLED Status Display (optional)
Requires: I2C OLED display (SSD1306 128x64)
Wiring: SDA → GPIO 2 (pin 3), SCL → GPIO 3 (pin 5), VCC → 3.3V, GND → GND
"""

import time
import subprocess
import os
import signal
import sys

# Graceful shutdown
def signal_handler(sig, frame):
    if disp:
        disp.fill(0)
        disp.show()
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# Load config
CONFIG = {}
CONFIG_PATH = "/etc/dashcam/dashcam.conf"

def load_config():
    global CONFIG
    CONFIG = {}
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    CONFIG[key.strip()] = val.strip().strip('"')

load_config()

RECORD_DIR = CONFIG.get("RECORD_DIR", "/home/pi/recordings")
REFRESH_SECONDS = int(CONFIG.get("OLED_REFRESH_SECONDS", "3"))
I2C_ADDRESS = int(CONFIG.get("OLED_I2C_ADDRESS", "0x3C"), 16)
DISPLAY_WIDTH = int(CONFIG.get("OLED_WIDTH", "128"))
DISPLAY_HEIGHT = int(CONFIG.get("OLED_HEIGHT", "64"))

# --- Display setup ---
try:
    import board
    import busio
    import adafruit_ssd1306
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("[oled-status] Missing dependencies. Run: sudo apt-get install python3-pip && pip3 install adafruit-circuitpython-ssd1306 Pillow")
    sys.exit(1)

i2c = busio.I2C(board.SCL, board.SDA)
disp = adafruit_ssd1306.SSD1306_I2C(DISPLAY_WIDTH, DISPLAY_HEIGHT, i2c, addr=I2C_ADDRESS)

# Clear on start
disp.fill(0)
disp.show()

# Load font
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 10)
    font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 9)
except:
    font = ImageFont.load_default()
    font_small = font


def run_cmd(cmd):
    """Run a shell command and return stdout."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except:
        return ""


def is_service_active(name):
    return run_cmd(f"systemctl is-active {name} 2>/dev/null") == "active"


def get_disk_usage():
    """Returns (percent_used, free_human, total_human)."""
    line = run_cmd(f"df -h '{RECORD_DIR}' | tail -1")
    if line:
        parts = line.split()
        return parts[4], parts[3], parts[1]  # percent, free, total
    return "?%", "?", "?"


def get_recording_count():
    return run_cmd(f"find '{RECORD_DIR}' -name 'dashcam_*.mp4' -type f 2>/dev/null | wc -l")


def get_ip():
    return run_cmd("hostname -I | awk '{print $1}'") or "no network"


def get_uptime():
    raw = run_cmd("uptime -p")
    # Shorten: "up 2 hours, 15 minutes" → "2h 15m"
    raw = raw.replace("up ", "").replace(" hours", "h").replace(" hour", "h")
    raw = raw.replace(" minutes", "m").replace(" minute", "m")
    raw = raw.replace(" days", "d").replace(" day", "d")
    raw = raw.replace(",", "")
    return raw


def get_resolution():
    return CONFIG.get("RESOLUTION", "?")


def draw_frame():
    """Draw one status frame to the OLED."""
    image = Image.new("1", (DISPLAY_WIDTH, DISPLAY_HEIGHT))
    draw = ImageDraw.Draw(image)

    recording = is_service_active("dashcam-record")
    streaming = is_service_active("dashcam-stream")
    disk_pct, disk_free, disk_total = get_disk_usage()
    file_count = get_recording_count()
    ip = get_ip()
    uptime = get_uptime()
    resolution = get_resolution()

    y = 0
    LINE_H = 11

    # Row 1: Title + recording indicator
    rec_icon = "● REC" if recording else "○ IDLE"
    draw.text((0, y), f"DASHCAM {rec_icon}", font=font, fill=255)
    y += LINE_H

    # Row 2: Resolution + stream status
    stream_txt = "STREAM:ON" if streaming else "STREAM:OFF"
    draw.text((0, y), f"{resolution}  {stream_txt}", font=font_small, fill=255)
    y += LINE_H

    # Row 3: Disk bar
    try:
        pct_int = int(disk_pct.replace("%", ""))
    except:
        pct_int = 0
    bar_width = 80
    bar_x = 46
    draw.text((0, y), f"DISK", font=font_small, fill=255)
    draw.rectangle([bar_x, y + 1, bar_x + bar_width, y + 8], outline=255)
    fill_w = int(bar_width * pct_int / 100)
    if fill_w > 0:
        draw.rectangle([bar_x, y + 1, bar_x + fill_w, y + 8], fill=255)
    y += LINE_H

    # Row 4: Disk details
    draw.text((0, y), f"{disk_pct} used  {disk_free} free", font=font_small, fill=255)
    y += LINE_H

    # Row 5: File count + uptime
    draw.text((0, y), f"{file_count} clips  up {uptime}", font=font_small, fill=255)
    y += LINE_H

    # Row 6: IP address
    draw.text((0, y), f"IP: {ip}", font=font_small, fill=255)

    # Send to display
    disp.image(image)
    disp.show()


# --- Main loop ---
print(f"[oled-status] Display started ({DISPLAY_WIDTH}x{DISPLAY_HEIGHT} @ 0x{I2C_ADDRESS:02X})")
print(f"[oled-status] Refreshing every {REFRESH_SECONDS}s")

while True:
    try:
        draw_frame()
    except Exception as e:
        print(f"[oled-status] Error: {e}")
    time.sleep(REFRESH_SECONDS)
