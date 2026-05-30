#!/bin/bash
# =============================================================================
#  BlackVM – Entrypoint
#  Alles nötige ist bereits im Image. Dieses Script liest nur die
#  Pterodactyl-Env-Variablen und startet QEMU + noVNC.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✔]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✘]${NC} $*"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${PURPLE}${BOLD}"
cat << 'EOF'
  ____  _            _  ___     ____  __ 
 | __ )| | __ _  ___| |/ /\ \ / /  \/  |
 |  _ \| |/ _` |/ __| ' /  \ V /| |\/| |
 | |_) | | (_| | (__| . \   | | | |  | |
 |____/|_|\__,_|\___|_|\_\  |_| |_|  |_|
                        by blackredit
EOF
echo -e "${NC}"

# ── Defaults für alle Pterodactyl-Variablen ───────────────────────────────────
SERVER_PORT="${SERVER_PORT:-8080}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
VNC_PORT="$((5900 + VNC_DISPLAY))"
VNC_PASSWORD="${VNC_PASSWORD:-black1234}"

RAM="${RAM:-2048}"
CPU_SOCKETS="${CPU_SOCKETS:-1}"
CPU_CORES="${CPU_CORES:-2}"
CPU_THREADS="${CPU_THREADS:-1}"
CPU_LIMIT="${CPU_LIMIT:-0}"

MACHINE_TYPE="${MACHINE_TYPE:-q35}"
USE_KVM="${USE_KVM:-1}"
USE_UEFI="${USE_UEFI:-1}"

DISK_FILE="${DISK_FILE:-disk.qcow2}"
DISK_CACHE="${DISK_CACHE:-writeback}"
SECONDARY_DISK="${SECONDARY_DISK:-}"

ISO_FILE="${ISO_FILE:-netboot.xyz.iso}"
SECONDARY_ISO="${SECONDARY_ISO:-}"

FORWARD_PORTS="${FORWARD_PORTS:-hostfwd=tcp::8080-:80}"
USE_VIRTIO="${USE_VIRTIO:-0}"
USE_VIRTIO_NET="${USE_VIRTIO_NET:-0}"
USE_GPU="${USE_GPU:-0}"
SOUND_ENABLED="${SOUND_ENABLED:-0}"
ENABLE_USB3="${ENABLE_USB3:-1}"
BALLOON_MEMORY="${BALLOON_MEMORY:-0}"
ENABLE_GUEST_AGENT="${ENABLE_GUEST_AGENT:-0}"
SHARED_DIR="${SHARED_DIR:-}"
SNAPSHOT_LOAD="${SNAPSHOT_LOAD:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

FIRMWARE_DIR="/opt/blackvm/firmware"

# ── Arbeitsverzeichnis & Temp ─────────────────────────────────────────────────
export TMPDIR=/home/container/tmp
mkdir -p "$TMPDIR" /home/container/shared /home/container/snapshots
cd /home/container

# ── KVM-Prüfung ───────────────────────────────────────────────────────────────
if [ "${USE_KVM}" = "1" ]; then
    if [ -c /dev/kvm ]; then
        ok "KVM aktiv – Hardware-Beschleunigung verfügbar"
    else
        warn "/dev/kvm nicht gefunden – falle auf TCG-Emulation zurück (langsam!)"
        warn "Bitte /dev/kvm als Mount in Pterodactyl einrichten (siehe README)"
        USE_KVM="0"
    fi
fi

# ── Disk-Prüfung ──────────────────────────────────────────────────────────────
if [ ! -f "${DISK_FILE}" ]; then
    warn "Disk '${DISK_FILE}' nicht gefunden – lege 100G Placeholder an..."
    qemu-img create -f qcow2 "${DISK_FILE}" 100G
fi

if [ -n "${SECONDARY_DISK}" ] && [ ! -f "${SECONDARY_DISK}" ]; then
    warn "Sekundäre Disk '${SECONDARY_DISK}' nicht gefunden – lege 50G an..."
    qemu-img create -f qcow2 "${SECONDARY_DISK}" 50G
fi

# ── VNC-Passwort-Datei ────────────────────────────────────────────────────────
info "Schreibe VNC-Passwort..."
{ echo "change vnc password"; echo "${VNC_PASSWORD}"; } > qemu_cmd.txt
chmod 600 qemu_cmd.txt

# ── QEMU-Befehl aufbauen ──────────────────────────────────────────────────────
info "Baue QEMU-Befehl..."
Q="qemu-system-x86_64"

# Maschine + Beschleunigung
if [ "${USE_KVM}" = "1" ]; then
    Q+=" -machine ${MACHINE_TYPE},accel=kvm -cpu host"
else
    Q+=" -machine ${MACHINE_TYPE},accel=tcg -cpu max"
    Q+=" -accel tcg,thread=multi,tb-size=128,split-wx=on"
fi

# CPU-Topologie
Q+=" -smp sockets=${CPU_SOCKETS},cores=${CPU_CORES},threads=${CPU_THREADS}"

# RAM
Q+=" -m ${RAM}"
[ "${BALLOON_MEMORY}" = "1" ] && Q+=" -device virtio-balloon-pci"

# Firmware (OVMF / BIOS – bereits im Image unter /opt/blackvm/firmware/)
if [ "${USE_UEFI}" = "1" ]; then
    Q+=" -drive if=pflash,format=raw,readonly=on,file=${FIRMWARE_DIR}/OVMF.fd"
else
    Q+=" -bios ${FIRMWARE_DIR}/bios.bin"
fi

# Primäre Disk
if [ "${USE_VIRTIO}" = "1" ]; then
    Q+=" -drive file=${DISK_FILE},format=qcow2,if=virtio,aio=native,cache.direct=on"
else
    Q+=" -drive file=${DISK_FILE},format=qcow2,if=ide,index=0,cache=${DISK_CACHE}"
fi

# Sekundäre Disk
[ -n "${SECONDARY_DISK}" ] && [ -f "${SECONDARY_DISK}" ] && \
    Q+=" -drive file=${SECONDARY_DISK},format=qcow2,if=virtio,index=1"

# Primäres ISO / CD-ROM
[ -n "${ISO_FILE}" ] && [ -f "${ISO_FILE}" ] && Q+=" -cdrom ${ISO_FILE}"

# Sekundäres ISO (z.B. VirtIO-Treiber für Windows)
[ -n "${SECONDARY_ISO}" ] && [ -f "${SECONDARY_ISO}" ] && \
    Q+=" -drive file=${SECONDARY_ISO},media=cdrom,if=ide,index=1,readonly=on"

# Shared Directory
[ -n "${SHARED_DIR}" ] && [ -d "${SHARED_DIR}" ] && \
    Q+=" -drive file=fat:rw:${SHARED_DIR},format=vvfat,label=SHARED"

# Netzwerk
if [ "${USE_VIRTIO_NET}" = "1" ]; then
    Q+=" -device virtio-net-pci,netdev=n0 -netdev user,id=n0,${FORWARD_PORTS}"
else
    Q+=" -net nic -net user,${FORWARD_PORTS}"
fi

# Anzeige / GPU
if [ "${USE_GPU}" = "1" ]; then
    Q+=" -device virtio-gpu-gl-pci,max_hostmem=256M -display egl-headless"
else
    Q+=" -vga std"
fi

# Sound
[ "${SOUND_ENABLED}" = "1" ] && Q+=" -device ich9-intel-hda -device hda-output"

# USB
if [ "${ENABLE_USB3}" = "1" ]; then
    Q+=" -device qemu-xhci -device usb-tablet"
else
    Q+=" -usbdevice tablet"
fi

# QEMU Guest Agent
if [ "${ENABLE_GUEST_AGENT}" = "1" ]; then
    Q+=" -chardev socket,path=/tmp/qga.sock,server=on,wait=off,id=qga0"
    Q+=" -device virtio-serial-pci"
    Q+=" -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
fi

# Snapshot laden
[ -n "${SNAPSHOT_LOAD}" ] && Q+=" -loadvm ${SNAPSHOT_LOAD}"

# Boot-Reihenfolge + VNC + Monitor
Q+=" -boot order=dc,menu=on,splash-time=3000"
Q+=" -vnc 0.0.0.0:${VNC_DISPLAY},password=on"
Q+=" -monitor stdio"

# Zusätzliche Argumente (EXTRA_ARGS)
[ -n "${EXTRA_ARGS}" ] && Q+=" ${EXTRA_ARGS}"

# ── Status-Ausgabe ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║              BlackVM  ·  Konfiguration               ║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "Beschleunigung:"  "$([ "${USE_KVM}" = "1" ] && echo "KVM (Hardware)" || echo "TCG (Software-Emulation)")"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "Maschine:"        "${MACHINE_TYPE}"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "CPU:"             "${CPU_SOCKETS}S × ${CPU_CORES}C × ${CPU_THREADS}T"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "RAM:"             "${RAM} MB"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "Boot-Modus:"      "$([ "${USE_UEFI}" = "1" ] && echo "UEFI (OVMF)" || echo "Legacy BIOS")"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "Primäre Disk:"    "${DISK_FILE}"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "ISO:"             "${ISO_FILE:-keins}"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "VirtIO Disk:"     "$([ "${USE_VIRTIO}" = "1" ] && echo "ja" || echo "nein")"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "VirtIO Netzwerk:" "$([ "${USE_VIRTIO_NET}" = "1" ] && echo "ja" || echo "nein")"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "noVNC Port:"      "${SERVER_PORT}"
printf "${CYAN}║${NC}  %-22s %-28s${CYAN}║${NC}\n" "VNC Intern:"      "59${VNC_DISPLAY}${VNC_DISPLAY}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── noVNC starten (Hintergrund) ───────────────────────────────────────────────
info "Starte noVNC auf Port ${SERVER_PORT}..."
cd /opt/novnc
python3 utils/websockify/run \
    --web /opt/novnc \
    0.0.0.0:${SERVER_PORT} \
    localhost:${VNC_PORT} \
    > /tmp/novnc.log 2>&1 &
NOVNC_PID=$!
sleep 2
if kill -0 "${NOVNC_PID}" 2>/dev/null; then
    ok "noVNC läuft  → http://HOST:${SERVER_PORT}  (pid ${NOVNC_PID})"
else
    warn "noVNC konnte nicht starten – siehe /tmp/novnc.log"
fi

# ── CPU-Limiter (optional) ────────────────────────────────────────────────────
if [ "${CPU_LIMIT}" -gt 0 ] 2>/dev/null; then
    info "CPU-Limit: ${CPU_LIMIT}% via cpulimit"
    ( sleep 6 && cpulimit --pid $$ --limit "${CPU_LIMIT}" --background ) &
fi

# ── QEMU starten (Vordergrund – ersetzt die Shell) ────────────────────────────
cd /home/container
echo ""
ok "Starte QEMU..."
echo -e "${YELLOW}──────────────────────────────────────────────────────${NC}"

eval exec ${Q} < qemu_cmd.txt