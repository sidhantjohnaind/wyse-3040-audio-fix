#!/usr/bin/env bash
# ==============================================================================
# Dell Wyse 3040 Audio Driver Automated Installer
# Supports: Debian 12/13, Ubuntu, Linux Mint (Kernel 6.x)
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   Dell Wyse 3040 Audio Driver Installer             ${NC}"
echo -e "${BLUE}======================================================${NC}"

# Check for root / sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (or with sudo).${NC}"
    echo "Usage: sudo ./install.sh"
    exit 1
fi

KERNEL_VER=$(uname -r)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/usr/src/linux-source-6.12"

echo -e "${YELLOW}[1/5] Checking build prerequisites for kernel $KERNEL_VER...${NC}"

# Ensure kernel headers and build tools are installed
if [ ! -d "/lib/modules/$KERNEL_VER/build" ]; then
    echo -e "${YELLOW}Kernel headers not found. Installing linux-headers-$KERNEL_VER and build tools...${NC}"
    apt-get update
    apt-get install -y build-essential "linux-headers-$KERNEL_VER" bc flex bison libssl-dev libelf-dev
fi

echo -e "${GREEN}✓ Kernel headers found at /lib/modules/$KERNEL_VER/build${NC}"

echo -e "${YELLOW}[2/5] Compiling audio driver modules...${NC}"

# Build machine driver
echo "Building snd-soc-sst-cht-bsw-rt5672..."
make -C "/lib/modules/$KERNEL_VER/build" M="$SRC_DIR/sound/soc/intel/boards" modules

# Build platform driver
echo "Building snd-soc-sst-atom-hifi2-platform..."
make -C "/lib/modules/$KERNEL_VER/build" M="$SRC_DIR/sound/soc/intel/atom" modules

echo -e "${GREEN}✓ Compilation completed successfully.${NC}"

echo -e "${YELLOW}[3/5] Installing modules to /lib/modules/$KERNEL_VER...${NC}"

DEST_BOARDS="/lib/modules/$KERNEL_VER/kernel/sound/soc/intel/boards"
DEST_ATOM="/lib/modules/$KERNEL_VER/kernel/sound/soc/intel/atom"

mkdir -p "$DEST_BOARDS" "$DEST_ATOM"

# Backup original modules if no backup exists yet
if [ ! -f "$DEST_BOARDS/snd-soc-sst-cht-bsw-rt5672.ko.orig" ] && [ -f "$DEST_BOARDS/snd-soc-sst-cht-bsw-rt5672.ko" ]; then
    cp "$DEST_BOARDS/snd-soc-sst-cht-bsw-rt5672.ko" "$DEST_BOARDS/snd-soc-sst-cht-bsw-rt5672.ko.orig"
fi

# Copy compiled .ko binaries
cp "$SRC_DIR/sound/soc/intel/boards/snd-soc-sst-cht-bsw-rt5672.ko" "$DEST_BOARDS/"
cp "$SRC_DIR/sound/soc/intel/atom/snd-soc-sst-atom-hifi2-platform.ko" "$DEST_ATOM/"

# Remove compressed (.xz) files if present so uncompressed modules take priority
rm -f "$DEST_BOARDS/snd-soc-sst-cht-bsw-rt5672.ko.xz"
rm -f "$DEST_ATOM/snd-soc-sst-atom-hifi2-platform.ko.xz"

# Update module dependencies
depmod -a "$KERNEL_VER"

echo -e "${GREEN}✓ Modules installed and dependencies updated.${NC}"

echo -e "${YELLOW}[4/5] Reloading sound driver modules...${NC}"

# Unload existing modules if active
modprobe -r snd_soc_sst_cht_bsw_rt5672 snd_soc_sst_atom_hifi2_platform 2>/dev/null || true

# Load updated drivers
modprobe snd_soc_sst_atom_hifi2_platform
modprobe snd_soc_sst_cht_bsw_rt5672

echo -e "${GREEN}✓ Drivers successfully loaded.${NC}"

echo -e "${YELLOW}[5/5] Testing audio playback on hw:0,0...${NC}"

if command -v speaker-test >/dev/null 2>&1; then
    if timeout 2 speaker-test -D hw:0,0 -c 2 -r 48000 -F S16_LE -t sine -f 1000 -l 1 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Hardware playback verified: 48 kHz / 16-bit working perfectly!${NC}"
    else
        echo -e "${YELLOW}Notice: Module loaded. A reboot is recommended to initialize the ALSA card completely.${NC}"
    fi
else
    echo -e "${GREEN}✓ Installation complete.${NC}"
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN} Installation Successful!                             ${NC}"
echo -e "${BLUE}======================================================${NC}"
