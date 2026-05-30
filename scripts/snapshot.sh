#!/bin/bash
# BlackVM – Snapshot Manager  (/scripts/snapshot.sh)
DISK="${3:-/home/container/disk.qcow2}"
ACTION="${1:-list}"
NAME="${2:-}"
C='\033[0;36m'; G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; N='\033[0m'

usage() {
    echo -e "${C}BlackVM Snapshot Manager${N}"
    echo "  list   [disk]         – alle Snapshots anzeigen"
    echo "  save   <name> [disk]  – neuen Snapshot erstellen"
    echo "  load   <name> [disk]  – Snapshot wiederherstellen (VM gestoppt!)"
    echo "  delete <name> [disk]  – Snapshot löschen"
    echo "  info         [disk]   – Disk-Infos anzeigen"
    exit 0
}

[ ! -f "${DISK}" ] && { echo -e "${R}[✘] Disk nicht gefunden: ${DISK}${N}"; exit 1; }

case "${ACTION}" in
    list)   qemu-img snapshot -l "${DISK}" ;;
    save)   [ -z "${NAME}" ] && usage
            echo -e "${Y}[~] Erstelle Snapshot '${NAME}'...${N}"
            qemu-img snapshot -c "${NAME}" "${DISK}" \
                && echo -e "${G}[✔] Snapshot '${NAME}' gespeichert${N}" ;;
    load)   [ -z "${NAME}" ] && usage
            echo -e "${Y}[~] Stelle Snapshot '${NAME}' wieder her...${N}"
            qemu-img snapshot -a "${NAME}" "${DISK}" \
                && echo -e "${G}[✔] Wiederhergestellt – VM neu starten${N}" ;;
    delete) [ -z "${NAME}" ] && usage
            qemu-img snapshot -d "${NAME}" "${DISK}" \
                && echo -e "${G}[✔] Snapshot '${NAME}' gelöscht${N}" ;;
    info)   qemu-img info "${DISK}" ;;
    *)      usage ;;
esac