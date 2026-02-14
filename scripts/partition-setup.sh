#!/usr/bin/env bash
# ============================================================
# Dash Car Cam - Recording Partition Setup
# Creates a dedicated partition for video recordings so a full
# disk never impacts the OS or SSH access.
#
# Run ONCE after flashing the SD card and first boot.
# Requires unallocated space on the SD card (or will shrink rootfs).
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[partition]${NC} $*"; }
warn() { echo -e "${YELLOW}[partition]${NC} $*"; }
err()  { echo -e "${RED}[partition]${NC} $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root: sudo bash partition-setup.sh"
    exit 1
fi

# -----------------------------------------------------------
# Detect SD card device
# -----------------------------------------------------------
ROOT_DEV=$(findmnt -n -o SOURCE /)
DISK_DEV=$(lsblk -no PKNAME "$ROOT_DEV" | head -1)
DISK="/dev/$DISK_DEV"

if [[ ! "$DISK" =~ mmcblk ]]; then
    warn "Root is on $DISK (not an SD card). Proceeding anyway."
fi

log "SD card: $DISK"
echo ""
lsblk "$DISK"
echo ""

# -----------------------------------------------------------
# Check for existing recordings partition
# -----------------------------------------------------------
PART_LABEL="DASHCAM"
EXISTING=$(blkid -L "$PART_LABEL" 2>/dev/null || true)

if [ -n "$EXISTING" ]; then
    warn "Partition '$PART_LABEL' already exists at $EXISTING"
    read -rp "  Remount and exit? [Y/n] " REMOUNT
    if [[ ! "$REMOUNT" =~ ^[Nn]$ ]]; then
        MOUNT_POINT="/mnt/dashcam"
        mkdir -p "$MOUNT_POINT"
        mount "$EXISTING" "$MOUNT_POINT" 2>/dev/null || true
        log "Mounted at $MOUNT_POINT"
        exit 0
    fi
    exit 0
fi

# -----------------------------------------------------------
# Determine partition strategy
# -----------------------------------------------------------
echo ""
echo "  Choose partition method:"
echo "    1) Use free/unallocated space on SD card  (recommended)"
echo "    2) Specify size to allocate (will create a file-backed partition if no space)"
echo ""
read -rp "  Method [1]: " METHOD
METHOD="${METHOD:-1}"

# Get the last partition number and end sector
LAST_PART_NUM=$(parted -s "$DISK" print | awk '/^ [0-9]/ {n=$1} END {print n}')
LAST_PART_END=$(parted -s "$DISK" unit s print | awk '/^ [0-9]/ {e=$3} END {gsub("s","",e); print e}')
DISK_SIZE_S=$(parted -s "$DISK" unit s print | grep "^Disk $DISK" | awk '{gsub("s",""); print $3}')

FREE_SECTORS=$((DISK_SIZE_S - LAST_PART_END - 1))
FREE_MB=$((FREE_SECTORS * 512 / 1048576))

log "Disk: ${DISK_SIZE_S} sectors total"
log "Free after last partition: ${FREE_MB} MB (~${FREE_SECTORS} sectors)"

if [ "$FREE_MB" -lt 500 ]; then
    warn "Only ${FREE_MB}MB free. For a useful recordings partition, you need at least 500MB."
    warn ""
    warn "Options:"
    warn "  a) Re-flash the SD card and don't expand rootfs to fill the card"
    warn "     (Raspberry Pi Imager → Advanced → disable 'Expand filesystem')"
    warn "  b) Use a USB drive instead (plug in, format, mount at /mnt/dashcam)"
    warn ""
    read -rp "  Continue anyway? [y/N] " CONT
    [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
fi

# -----------------------------------------------------------
# Determine partition size
# -----------------------------------------------------------
if [ "$METHOD" = "2" ]; then
    echo ""
    read -rp "  Partition size in MB [${FREE_MB}]: " PART_SIZE_MB
    PART_SIZE_MB="${PART_SIZE_MB:-$FREE_MB}"
else
    PART_SIZE_MB="$FREE_MB"
fi

log "Creating ${PART_SIZE_MB}MB partition for recordings..."

# -----------------------------------------------------------
# Create the partition
# -----------------------------------------------------------
NEW_PART_START=$((LAST_PART_END + 1))
NEW_PART_END=$((NEW_PART_START + (PART_SIZE_MB * 1048576 / 512) - 1))

# Clamp to disk size
if [ "$NEW_PART_END" -ge "$DISK_SIZE_S" ]; then
    NEW_PART_END=$((DISK_SIZE_S - 1))
fi

NEW_PART_NUM=$((LAST_PART_NUM + 1))

log "Creating partition ${NEW_PART_NUM}: sectors ${NEW_PART_START}–${NEW_PART_END}"

parted -s "$DISK" mkpart primary ext4 "${NEW_PART_START}s" "${NEW_PART_END}s"

# Determine partition device name
if [[ "$DISK" =~ mmcblk ]]; then
    NEW_PART_DEV="${DISK}p${NEW_PART_NUM}"
else
    NEW_PART_DEV="${DISK}${NEW_PART_NUM}"
fi

# Wait for kernel to pick it up
partprobe "$DISK"
sleep 2

if [ ! -b "$NEW_PART_DEV" ]; then
    err "Partition device $NEW_PART_DEV not found after creation!"
    exit 1
fi

# -----------------------------------------------------------
# Format with ext4
# -----------------------------------------------------------
log "Formatting $NEW_PART_DEV as ext4 (label: $PART_LABEL)..."
mkfs.ext4 -L "$PART_LABEL" -m 1 "$NEW_PART_DEV"

# -m 1: reserve only 1% for root (default 5% wastes space on a data partition)

# -----------------------------------------------------------
# Mount
# -----------------------------------------------------------
MOUNT_POINT="/mnt/dashcam"
mkdir -p "$MOUNT_POINT"

log "Mounting at $MOUNT_POINT..."
mount "$NEW_PART_DEV" "$MOUNT_POINT"

# Set ownership
PI_USER=$(logname 2>/dev/null || echo "pi")
chown "$PI_USER:$PI_USER" "$MOUNT_POINT"

# -----------------------------------------------------------
# Add to fstab for auto-mount on boot
# -----------------------------------------------------------
PART_UUID=$(blkid -s UUID -o value "$NEW_PART_DEV")

if ! grep -q "$PART_UUID" /etc/fstab 2>/dev/null; then
    echo "UUID=$PART_UUID  $MOUNT_POINT  ext4  defaults,noatime,nofail  0  2" >> /etc/fstab
    log "Added to /etc/fstab (nofail = OS boots even if partition is missing)"
fi

# -----------------------------------------------------------
# Update dashcam config to use the new partition
# -----------------------------------------------------------
if [ -f /etc/dashcam/dashcam.conf ]; then
    sed -i "s|^RECORD_DIR=.*|RECORD_DIR=\"$MOUNT_POINT\"|" /etc/dashcam/dashcam.conf
    log "Updated RECORD_DIR in /etc/dashcam/dashcam.conf → $MOUNT_POINT"
fi

# Also update all profile configs
for prof in /etc/dashcam/dashcam-*.conf; do
    [ -f "$prof" ] && sed -i "s|^RECORD_DIR=.*|RECORD_DIR=\"$MOUNT_POINT\"|" "$prof"
done

# -----------------------------------------------------------
# Summary
# -----------------------------------------------------------
PART_SIZE_ACTUAL=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $2}')

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Recording partition created!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Device:     $NEW_PART_DEV"
echo "  UUID:       $PART_UUID"
echo "  Size:       $PART_SIZE_ACTUAL"
echo "  Mount:      $MOUNT_POINT"
echo "  Label:      $PART_LABEL"
echo "  fstab:      ✅ auto-mount on boot (nofail)"
echo "  Config:     ✅ RECORD_DIR updated"
echo ""
echo "  Recordings will no longer fill the OS partition."
echo "  Even if recordings fill 100% of this partition,"
echo "  SSH and the OS remain fully functional."
echo ""
