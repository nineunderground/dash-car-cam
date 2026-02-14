#!/usr/bin/env bash
# ============================================================
# Dash Car Cam - One-Shot Setup Script
# Raspberry Pi 4 + NoIR Camera V2
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[dashcam]${NC} $*"; }
warn() { echo -e "${YELLOW}[dashcam]${NC} $*"; }
err()  { echo -e "${RED}[dashcam]${NC} $*" >&2; }

# -----------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    err "Don't run as root. Run as your normal user (pi). The script uses sudo where needed."
    exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
    warn "Unexpected architecture: $ARCH. This script is designed for Raspberry Pi."
    read -rp "Continue anyway? [y/N] " CONT < /dev/tty
    [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
fi

PI_USER=$(whoami)
RECORD_DIR="/home/$PI_USER/recordings"

# Always clone latest repo to ensure all files are present
REPO_DIR="/tmp/dash-car-cam-setup"
log "Cloning latest dash-car-cam repo..."
rm -rf "$REPO_DIR"
sudo apt-get install -y -qq git 2>/dev/null || true
git clone --depth 1 https://github.com/nineunderground/dash-car-cam.git "$REPO_DIR"

log "Setting up Dash Car Cam for user: $PI_USER"
log "Repo directory: $REPO_DIR"

# -----------------------------------------------------------
# 1. System update
# -----------------------------------------------------------
log "Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# -----------------------------------------------------------
# 2. Install dependencies
# -----------------------------------------------------------
log "Installing dependencies..."
sudo apt-get install -y -qq \
    libcamera-apps \
    ffmpeg \
    python3-picamera2 \
    v4l-utils \
    git \
    jq

# -----------------------------------------------------------
# 3. Enable camera interface
# -----------------------------------------------------------
log "Ensuring camera interface is enabled..."

# For newer Pi OS (Bookworm+), libcamera is default
# For older (Bullseye), ensure dtoverlay is set
BOOT_CONFIG="/boot/firmware/config.txt"
[ -f "$BOOT_CONFIG" ] || BOOT_CONFIG="/boot/config.txt"

if ! grep -q "^start_x=1" "$BOOT_CONFIG" 2>/dev/null; then
    # Bookworm uses libcamera by default, but ensure gpu_mem is adequate
    if ! grep -q "^gpu_mem=" "$BOOT_CONFIG"; then
        echo "gpu_mem=256" | sudo tee -a "$BOOT_CONFIG" > /dev/null
        log "Set gpu_mem=256"
    fi
fi

# Ensure camera_auto_detect is enabled (Bookworm)
if ! grep -q "^camera_auto_detect=1" "$BOOT_CONFIG" 2>/dev/null; then
    echo "camera_auto_detect=1" | sudo tee -a "$BOOT_CONFIG" > /dev/null
    log "Enabled camera_auto_detect"
fi

# -----------------------------------------------------------
# 4. Install mediamtx (RTSP server) for streaming
# -----------------------------------------------------------
MEDIAMTX_VERSION="1.9.3"
MEDIAMTX_BIN="/usr/local/bin/mediamtx"

if [ ! -f "$MEDIAMTX_BIN" ]; then
    log "Installing mediamtx v${MEDIAMTX_VERSION} (RTSP server)..."

    if [ "$ARCH" = "aarch64" ]; then
        MTX_ARCH="arm64v8"
    else
        MTX_ARCH="armv7"
    fi

    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    curl -fsSL "https://github.com/bluenviron/mediamtx/releases/download/v${MEDIAMTX_VERSION}/mediamtx_v${MEDIAMTX_VERSION}_linux_${MTX_ARCH}.tar.gz" -o mediamtx.tar.gz
    tar xzf mediamtx.tar.gz
    sudo mv mediamtx "$MEDIAMTX_BIN"
    sudo chmod +x "$MEDIAMTX_BIN"
    cd -
    rm -rf "$TMP_DIR"

    log "mediamtx installed"
else
    log "mediamtx already installed"
fi

# -----------------------------------------------------------
# 5. Create configuration
# -----------------------------------------------------------
log "Installing configuration..."
sudo mkdir -p /etc/dashcam

# Install config (preserve existing)
if [ ! -f /etc/dashcam/dashcam.conf ]; then
    echo ""
    echo "  Select camera type:"
    echo "    1) CSI  — Raspberry Pi Camera (ribbon cable)  (default)"
    echo "    2) USB  — USB webcam (Voxicon, Logitech, etc.)"
    echo ""
    read -rp "  Camera [1]: " CAM_CHOICE < /dev/tty
    CAM_CHOICE="${CAM_CHOICE:-1}"

    echo ""
    echo "  Select recording profile:"
    echo "    1) 1080p — higher quality, ~8h on 32GB  (default)"
    echo "    2) 720p  — lighter storage, ~16h on 32GB"
    echo ""
    read -rp "  Profile [1]: " PROFILE_CHOICE < /dev/tty
    PROFILE_CHOICE="${PROFILE_CHOICE:-1}"

    if [ "$CAM_CHOICE" = "2" ]; then
        CAM_PREFIX="usb-"
        log "Using USB webcam"
    else
        CAM_PREFIX=""
        log "Using CSI camera"
    fi

    case "$PROFILE_CHOICE" in
        2) PROFILE_FILE="dashcam-${CAM_PREFIX}720p.conf"; log "Using 720p profile" ;;
        *) PROFILE_FILE="dashcam-${CAM_PREFIX}1080p.conf"; log "Using 1080p profile" ;;
    esac

    sudo cp "$REPO_DIR/config/$PROFILE_FILE" /etc/dashcam/dashcam.conf
    sudo sed -i "s|/home/pi|/home/$PI_USER|g" /etc/dashcam/dashcam.conf
    log "Config installed: /etc/dashcam/dashcam.conf"
else
    warn "Config already exists, skipping (edit /etc/dashcam/dashcam.conf manually)"
fi

# Copy all profiles for reference
for prof in dashcam-1080p.conf dashcam-720p.conf dashcam-usb-1080p.conf dashcam-usb-720p.conf; do
    sudo cp "$REPO_DIR/config/$prof" "/etc/dashcam/$prof"
done
log "All profiles available in /etc/dashcam/ for switching later"

# -----------------------------------------------------------
# 5b. Optional: OLED display setup
# -----------------------------------------------------------
OLED_INSTALLED=false
echo ""
OLED_CHOICE="n"
read -rp "  Install OLED display support (I2C SSD1306)? [y/N] " OLED_CHOICE < /dev/tty || OLED_CHOICE="n"

if [ "$OLED_CHOICE" = "y" ] || [ "$OLED_CHOICE" = "Y" ]; then
    log "Installing OLED dependencies..."
    sudo apt-get install -y -qq python3-pip python3-pil i2c-tools
    pip3 install --break-system-packages adafruit-circuitpython-ssd1306 2>/dev/null || pip3 install adafruit-circuitpython-ssd1306 || true

    # Enable I2C
    if ! grep -q "^dtparam=i2c_arm=on" "$BOOT_CONFIG" 2>/dev/null; then
        echo "dtparam=i2c_arm=on" | sudo tee -a "$BOOT_CONFIG" > /dev/null
        log "Enabled I2C in boot config"
    fi

    # Enable OLED in config
    sudo sed -i 's/OLED_ENABLED=false/OLED_ENABLED=true/' /etc/dashcam/dashcam.conf

    OLED_INSTALLED=true
    log "OLED display support installed"
fi

# -----------------------------------------------------------
# 6. Install scripts
# -----------------------------------------------------------
log "Installing scripts..."

for script in dashcam-record.sh dashcam-stream.sh dashcam-ctl.sh storage-cleanup.sh led-status.sh oled-status.py; do
    sudo cp "$REPO_DIR/scripts/$script" "/usr/local/bin/$script"
    sudo chmod +x "/usr/local/bin/$script"
done

# Create convenience symlink
sudo ln -sf /usr/local/bin/dashcam-ctl.sh /usr/local/bin/dashcam-ctl

# Fix user paths in scripts
sudo sed -i "s|/home/pi|/home/$PI_USER|g" /usr/local/bin/dashcam-*.sh /usr/local/bin/storage-cleanup.sh 2>/dev/null || true

# -----------------------------------------------------------
# 7. Install systemd services
# -----------------------------------------------------------
log "Installing systemd services..."

for unit in dashcam-record.service dashcam-stream.service dashcam-cleanup.service dashcam-cleanup.timer dashcam-oled.service; do
    sudo cp "$REPO_DIR/config/$unit" "/etc/systemd/system/$unit"
    # Adjust user
    sudo sed -i "s/User=pi/User=$PI_USER/" "/etc/systemd/system/$unit"
done

sudo systemctl daemon-reload

# Enable recording on boot (starts after reboot)
sudo systemctl enable dashcam-record.service
sudo systemctl enable dashcam-cleanup.timer

# Streaming is disabled by default
sudo systemctl disable dashcam-stream.service 2>/dev/null || true

# OLED display (if installed)
if [ "${OLED_INSTALLED:-false}" = "true" ]; then
    sudo systemctl enable dashcam-oled.service
    log "OLED display service enabled"
else
    sudo systemctl disable dashcam-oled.service 2>/dev/null || true
fi

log "Services installed"

# -----------------------------------------------------------
# 8. Recordings storage
# -----------------------------------------------------------
echo ""
echo "  Storage for recordings:"
echo "    1) Same partition as OS (simpler, default)"
echo "    2) Dedicated partition (recommended — protects OS if disk fills up)"
echo ""
read -rp "  Storage [1]: " STORAGE_CHOICE < /dev/tty

if [ "${STORAGE_CHOICE:-1}" = "2" ]; then
    log "Running partition setup..."
    sudo bash "$REPO_DIR/scripts/partition-setup.sh"
    # Reload config (partition script updates RECORD_DIR)
    source /etc/dashcam/dashcam.conf
else
    mkdir -p "$RECORD_DIR"
fi
log "Recordings directory: $RECORD_DIR"

# -----------------------------------------------------------
# 9. Camera test
# -----------------------------------------------------------
log "Testing camera..."
if libcamera-hello --list-cameras 2>&1 | grep -q "Available cameras"; then
    log "✅ Camera detected!"
    # Quick test capture
    libcamera-still --nopreview --timeout 2000 -o "$RECORD_DIR/test_capture.jpg" 2>/dev/null && \
        log "✅ Test capture saved: $RECORD_DIR/test_capture.jpg" || \
        warn "Camera detected but test capture failed (may need reboot)"
else
    warn "⚠️  No camera detected. Check:"
    warn "   1. Ribbon cable is properly connected"
    warn "   2. Blue side faces USB/Ethernet ports"
    warn "   3. Reboot after setup completes"
fi

# -----------------------------------------------------------
# Done
# -----------------------------------------------------------
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Dash Car Cam setup complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Config:     /etc/dashcam/dashcam.conf"
echo "  Recordings: $RECORD_DIR"
echo "  Control:    dashcam-ctl status|record|stream|snapshot|disk"
echo ""
echo "  Recording starts automatically on next boot."
echo "  To start now:  sudo systemctl start dashcam-record"
echo "  To stream:     dashcam-ctl stream on"
echo ""
echo -e "${YELLOW}  Reboot recommended: sudo reboot${NC}"
echo ""
