#!/bin/bash
# BlackVM – Disk Resize  |  Usage: bvm-resize [disk] [size]
DISK="${1:-/home/container/disk.qcow2}"; SIZE="${2:-}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -z "$SIZE" ] && { echo -e "${CYAN}Usage: bvm-resize <disk> <size>  e.g. bvm-resize disk.qcow2 +50G${NC}"; exit 0; }
[ ! -f "$DISK" ] && { echo -e "${RED}[✘] Disk not found: $DISK${NC}"; exit 1; }
echo -e "${YELLOW}⚠  Stop the VM before resizing!${NC}"
qemu-img info "$DISK" | grep -E "virtual size|disk size|format"
echo ""
qemu-img resize "$DISK" "$SIZE" \
    && echo -e "${GREEN}[✔] Resized – expand the partition inside the VM (GParted/growpart)${NC}" \
    || echo -e "${RED}[✘] Resize failed${NC}"
