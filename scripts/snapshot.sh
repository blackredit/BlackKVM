#!/bin/bash
# BlackVM – Snapshot Manager
# Usage: bvm-snapshot <list|save|load|delete|info> [name] [disk]
DISK="${3:-/home/container/${DISK_FILE:-disk.qcow2}}"
ACTION="${1:-list}"
SNAP="${2:-}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

usage() {
    echo -e "${CYAN}bvm-snapshot <list|save|load|delete|info> [name] [disk]${NC}"; exit 0
}

[ ! -f "$DISK" ] && { echo -e "${RED}[✘] Disk not found: $DISK${NC}"; exit 1; }

case "$ACTION" in
    list)   echo -e "${CYAN}Snapshots in $DISK:${NC}"; qemu-img snapshot -l "$DISK" ;;
    save)   [ -z "$SNAP" ] && usage
            echo -e "${YELLOW}[~] Saving snapshot '$SNAP'...${NC}"
            qemu-img snapshot -c "$SNAP" "$DISK" && echo -e "${GREEN}[✔] Saved${NC}" ;;
    load)   [ -z "$SNAP" ] && usage
            echo -e "${YELLOW}[~] Restoring '$SNAP' – VM must be stopped!${NC}"
            qemu-img snapshot -a "$SNAP" "$DISK" && echo -e "${GREEN}[✔] Restored – restart the VM${NC}" ;;
    delete) [ -z "$SNAP" ] && usage
            qemu-img snapshot -d "$SNAP" "$DISK" && echo -e "${GREEN}[✔] Deleted '$SNAP'${NC}" ;;
    info)   qemu-img info "$DISK" ;;
    *)      usage ;;
esac
