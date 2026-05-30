#!/bin/bash
# BlackVM – Disk Resize  (/scripts/resize-disk.sh)
# Beispiel: /scripts/resize-disk.sh disk.qcow2 +50G
DISK="${1:-/home/container/disk.qcow2}"
SIZE="${2:-}"
Y='\033[1;33m'; G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'

[ -z "${SIZE}" ] && { echo -e "${C}Nutzung: $0 <disk> <größe>  (z.B. +50G oder 200G)${N}"; exit 0; }
[ ! -f "${DISK}" ] && { echo -e "${R}[✘] Disk nicht gefunden: ${DISK}${N}"; exit 1; }

echo -e "${C}Aktuelle Größe:${N}"; qemu-img info "${DISK}" | grep -E "virtual size|disk size"
echo -e "${Y}[~] Ändere Größe auf '${SIZE}' – VM muss gestoppt sein!${N}"
qemu-img resize "${DISK}" "${SIZE}" \
    && echo -e "${G}[✔] Erledigt – Partition im Gast noch anpassen (z.B. GParted)${N}" \
    || echo -e "${R}[✘] Fehlgeschlagen${N}"