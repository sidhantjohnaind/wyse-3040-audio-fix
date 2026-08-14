#!/usr/bin/env bash
# ==============================================================================
# Dell Wyse 3040 Audio Driver DKMS Setup Script
# Automatically builds and installs audio drivers for all future kernel upgrades
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   Dell Wyse 3040 DKMS Auto-Rebuild Setup            ${NC}"
echo -e "${BLUE}======================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (or with sudo).${NC}"
    echo "Usage: sudo ./dkms-install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/usr/src/linux-source-6.12"
DKMS_DIR="/usr/src/wyse-3040-audio-1.0.0"

# Check if dkms is installed
if ! command -v dkms >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing dkms and build dependencies...${NC}"
    apt-get update
    apt-get install -y dkms build-essential
fi

echo -e "${YELLOW}Setting up DKMS source at $DKMS_DIR...${NC}"

# Remove existing dkms registration if present
dkms remove -m wyse-3040-audio -v 1.0.0 --all 2>/dev/null || true
rm -rf "$DKMS_DIR"

mkdir -p "$DKMS_DIR/sound/soc/intel"
cp -r "$SRC_DIR/sound/soc/intel/boards" "$DKMS_DIR/sound/soc/intel/"
cp -r "$SRC_DIR/sound/soc/intel/atom" "$DKMS_DIR/sound/soc/intel/"
cp "$SCRIPT_DIR/dkms.conf" "$DKMS_DIR/"

echo -e "${YELLOW}Registering and building DKMS module...${NC}"
dkms add -m wyse-3040-audio -v 1.0.0
dkms build -m wyse-3040-audio -v 1.0.0
dkms install -m wyse-3040-audio -v 1.0.0 --force

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN} ✓ DKMS Setup Complete!                              ${NC}"
echo -e "${GREEN} The audio driver will now automatically compile and ${NC}"
echo -e "${GREEN} install whenever Debian updates to a new kernel!    ${NC}"
echo -e "${GREEN}======================================================${NC}"
