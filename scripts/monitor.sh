#!/bin/bash
# BlackVM – QEMU Monitor Helper  (/scripts/monitor.sh)
# Voraussetzung: EXTRA_ARGS=-monitor unix:/tmp/blackvm.sock,server,nowait
SOCK="/tmp/blackvm.sock"
CMD="${*:-help}"
C='\033[0;36m'; G='\033[0;32m'; R='\033[0;31m'; N='\033[0m'

if [ ! -S "${SOCK}" ]; then
    echo -e "${R}[✘] Monitor-Socket nicht gefunden: ${SOCK}${N}"
    echo -e "${C}Tipp: EXTRA_ARGS auf -monitor unix:${SOCK},server,nowait setzen${N}"
    echo ""
    echo "Nützliche Monitor-Befehle:"
    echo "  info status          info vnc          info block"
    echo "  system_powerdown     system_reset       quit"
    echo "  savevm <name>        loadvm <name>      delvm <name>"
    echo "  screendump out.ppm   change vnc password"
    exit 1
fi

echo -e "${G}[→]${N} Sende: ${CMD}"
echo "${CMD}" | socat - UNIX-CONNECT:"${SOCK}"