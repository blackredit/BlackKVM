#!/bin/bash
# BlackVM – QEMU Monitor Helper  |  Usage: bvm-monitor "command"
# Requires EXTRA_ARGS to contain: -monitor unix:/tmp/bvm.sock,server,nowait
SOCK="/tmp/bvm.sock"; CMD="${*:-help}"
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
if [ ! -S "$SOCK" ]; then
    echo -e "${RED}[✘] No monitor socket at $SOCK${NC}"
    echo -e "    Add to EXTRA_ARGS: -monitor unix:/tmp/bvm.sock,server,nowait"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo "  info status          – running state"
    echo "  savevm <name>        – live snapshot (VM running)"
    echo "  loadvm <name>        – restore live snapshot"
    echo "  system_powerdown     – ACPI graceful shutdown"
    echo "  system_reset         – hard reset"
    echo "  change vnc password  – change VNC password live"
    echo "  screendump out.png   – screenshot"
    echo "  quit                 – kill QEMU immediately"
    exit 1
fi
echo -e "${GREEN}[→]${NC} ${CMD}"
echo "$CMD" | socat - UNIX-CONNECT:"$SOCK"
