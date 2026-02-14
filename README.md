# Dash Car Cam 🚗📹

A Raspberry Pi 4 + NoIR Camera V2 dash cam that auto-records on boot with local storage and optional RTSP streaming.

## Hardware

| Component | Model |
|-----------|-------|
| Board | Raspberry Pi 4 (2GB+ RAM recommended) |
| Camera (option A) | Raspberry Pi NoIR Camera Board V2, 8MP (CSI) |
| Camera (option B) | USB webcam — e.g. Voxicon 1080p, Logitech C920 (UVC-compliant) |
| Storage | MicroSD 32GB+ (Class 10 / A2 recommended) |
| Power | 5V 3A USB-C (car adapter or power bank) |
| Case | Any Pi 4 case with camera slot (or 3D-printed mount) |

### Wiring

1. Power off the Pi
2. Locate the **CSI camera port** (between HDMI and audio jack)
3. Lift the plastic clip on the CSI connector
4. Insert the camera ribbon cable with **blue side facing the USB/Ethernet ports**
5. Push the clip down to secure

## Quick Start

```bash
# 1. Flash Raspberry Pi OS Lite (64-bit) to SD card using Raspberry Pi Imager
#    - Enable SSH in imager settings
#    - Set username/password
#    - Configure WiFi (optional, for streaming)

# 2. Boot the Pi, SSH in, then:
curl -fsSL https://raw.githubusercontent.com/nineunderground/dash-car-cam/main/setup.sh | bash

# 3. Reboot
sudo reboot
```

After reboot, recording starts automatically. That's it.

## What the Setup Does

1. Updates the system
2. Enables the camera interface via `libcamera`
3. Installs recording dependencies (`libcamera-apps`, `ffmpeg`, `mediakit`)
4. Installs optional RTSP streaming server (`mediamtx`)
5. Creates the recording service (systemd) — auto-starts on boot
6. Creates the streaming service (systemd) — disabled by default
7. Sets up log rotation and storage management (auto-deletes oldest files when disk is >85% full)

## Configuration

Edit `/etc/dashcam/dashcam.conf` after setup:

```bash
# Recording
RECORD_DIR="/home/pi/recordings"    # Where clips are saved
SEGMENT_MINUTES=5                    # Split into N-minute files
RESOLUTION="1920x1080"               # 1080p (max for V2 camera)
FPS=30                               # Framerate
BITRATE="8000000"                    # 8 Mbps H.264
ROTATION=0                           # 0, 90, 180, 270

# Storage management
MAX_DISK_PERCENT=85                  # Auto-delete oldest when exceeded
MIN_FREE_MB=1000                     # Keep at least 1GB free

# Streaming (when enabled)
STREAM_ENABLED=false
RTSP_PORT=8554
STREAM_RESOLUTION="1280x720"        # Lower res for streaming
STREAM_FPS=25
STREAM_BITRATE="4000000"
```

## Modes

### Mode 1: Local Recording Only (default)

Records H.264 video in segments to the SD card. Oldest files auto-purge when storage fills up.

```bash
# Check status
sudo systemctl status dashcam-record

# View recordings
ls -lah ~/recordings/

# Stop recording
sudo systemctl stop dashcam-record
```

### Mode 2: Recording + RTSP Streaming

Simultaneously records locally AND streams via RTSP.

```bash
# Enable streaming
sudo dashcam-ctl stream on
# or manually:
sudo systemctl enable --now dashcam-stream

# Connect from any RTSP player (VLC, etc):
# rtsp://<PI_IP>:8554/dashcam
```

### Mode 3: Stream Only (no local storage)

```bash
sudo dashcam-ctl record off
sudo dashcam-ctl stream on
```

### Switching Profiles

```bash
dashcam-ctl profile              # Show current + available profiles
dashcam-ctl profile 1080p        # CSI camera, 1080p
dashcam-ctl profile 720p         # CSI camera, 720p
dashcam-ctl profile usb-1080p    # USB webcam, 1080p
dashcam-ctl profile usb-720p     # USB webcam, 720p
```

All profiles are stored in `/etc/dashcam/` for easy switching.

### USB Webcam Notes

Any UVC-compliant USB webcam works (Voxicon, Logitech, etc.). Just plug it into a USB port on the Pi.

```bash
# Verify the webcam is detected
lsusb
v4l2-ctl --list-devices

# Check supported formats
v4l2-ctl -d /dev/video0 --list-formats-ext

# If the device isn't /dev/video0, update USB_DEVICE in the config
```

USB webcams use `ffmpeg` + V4L2 for capture (software H.264 encoding via `libx264`), vs CSI cameras which use hardware-accelerated `libcamera`. USB works great but uses slightly more CPU.

## Useful Commands

```bash
dashcam-ctl status          # Show recording/streaming status
dashcam-ctl record on|off   # Toggle recording
dashcam-ctl stream on|off   # Toggle streaming
dashcam-ctl snapshot        # Take a still photo
dashcam-ctl disk            # Show storage usage
dashcam-ctl tail            # Follow the dashcam log
dashcam-ctl ip              # Show Pi's IP (for RTSP URL)
```

## Storage Partition (recommended)

By default, recordings go on the same partition as the OS. If recordings fill the disk, you lose SSH access and the OS can become unstable.

The setup script offers to create a **dedicated partition** for recordings:

```
/dev/mmcblk0p1  → /boot      (256MB)
/dev/mmcblk0p2  → /          (OS, ~8GB)
/dev/mmcblk0p3  → /mnt/dashcam  (rest of SD card, recordings only)
```

Benefits:
- **OS stays healthy** even if recordings hit 100%
- SSH always works for remote access
- Cleanup script only manages the recordings partition
- `nofail` fstab flag = OS boots even if partition is damaged

To set up after initial install:
```bash
sudo bash /usr/local/bin/partition-setup.sh
```

> **Tip:** When flashing the SD card with Raspberry Pi Imager, disable "Expand filesystem" in advanced settings. This leaves free space for the recordings partition. If the rootfs already fills the card, you'll need to re-flash or use a USB drive instead.

## Accessing Recordings

### Over the network (SCP)
```bash
scp pi@<PI_IP>:~/recordings/*.mp4 ./
```

### USB transfer
Plug the SD card into any computer — recordings are in `/home/pi/recordings/`

### SMB share (optional)
The setup script can optionally install Samba to expose recordings as a network drive.

## OLED Status Display (optional)

Supports I2C SSD1306 OLED displays (128×64). Shows real-time status on a small screen mounted alongside the camera.

### Wiring

| OLED Pin | Pi Pin |
|----------|--------|
| SDA | GPIO 2 (pin 3) |
| SCL | GPIO 3 (pin 5) |
| VCC | 3.3V (pin 1) |
| GND | GND (pin 6) |

### What It Shows

```
┌──────────────────────┐
│ DASHCAM  ● REC       │
│ 1920x1080  STREAM:OFF│
│ DISK ████████░░░░░░  │
│ 72% used  8.2G free  │
│ 142 clips  up 3h 20m │
│ IP: 192.168.1.42     │
└──────────────────────┘
```

- Recording status (● REC / ○ IDLE)
- Current resolution + streaming on/off
- Disk usage bar + percentage
- Clip count + system uptime
- IP address (for RTSP connection)

Refreshes every 3 seconds (configurable via `OLED_REFRESH_SECONDS`).

### Control

```bash
dashcam-ctl oled on    # Enable display
dashcam-ctl oled off   # Disable display
```

### Verify I2C Connection

```bash
sudo i2cdetect -y 1
# Should show device at 0x3C (default)
```

## LED Behavior

| LED | Meaning |
|-----|---------|
| 🔴 Red (steady) | Recording |
| 🔴 Red (blinking) | Storage >80% |
| 🟢 Green (steady) | Streaming active |
| ⚫ Off | Idle |

> LED control requires a connected LED on GPIO 17 (red) and GPIO 27 (green). Optional.

## Estimated Storage

| Resolution | Bitrate | Per Minute | Per Hour | 32GB card |
|------------|---------|-----------|----------|-----------|
| 1080p | 8 Mbps | ~60 MB | ~3.5 GB | ~8 hours |
| 720p | 4 Mbps | ~30 MB | ~1.8 GB | ~16 hours |

## Troubleshooting

```bash
# Check if camera is detected
libcamera-hello --list-cameras

# Test capture
libcamera-still -o test.jpg

# Check service logs
journalctl -u dashcam-record -f

# If "no cameras available":
# 1. Check ribbon cable connection
# 2. Ensure camera is enabled: sudo raspi-config → Interface → Camera
# 3. Check /boot/config.txt has: start_x=1 and gpu_mem=128
```

## Project Structure

```
├── setup.sh              # One-shot installer
├── scripts/
│   ├── dashcam-record.sh # Recording loop
│   ├── dashcam-stream.sh # RTSP streaming
│   ├── dashcam-ctl.sh    # Control utility
│   ├── storage-cleanup.sh# Auto-purge old files
│   ├── partition-setup.sh # Dedicated recordings partition
│   ├── led-status.sh     # Optional LED control
│   └── oled-status.py    # Optional OLED display
├── config/
│   ├── dashcam.conf      # Default configuration
│   ├── dashcam-1080p.conf     # CSI 1080p profile
│   ├── dashcam-720p.conf      # CSI 720p profile
│   ├── dashcam-usb-1080p.conf # USB webcam 1080p
│   ├── dashcam-usb-720p.conf  # USB webcam 720p
│   ├── dashcam-record.service
│   ├── dashcam-oled.service
│   ├── dashcam-stream.service
│   └── dashcam-cleanup.timer
└── README.md
```

## License

MIT — see [LICENSE](LICENSE)
