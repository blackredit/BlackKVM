#!/bin/bash
# =============================================================================
#  BlackVM – Entrypoint
#  github.com/blackredit/blackvm
#
#  QEMU command is built HERE from environment variables.
#  The egg startup is just: /bin/bash /entrypoint.sh
#  → no eval of an external $STARTUP string, no quoting hell.
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✔]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✘]${NC} $*"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${PURPLE}${BOLD}"
cat << 'BANNER'

░████████   ░██                       ░██       ░██     ░██ ░██    ░██ ░███     ░███ 
░██    ░██  ░██                       ░██       ░██    ░██  ░██    ░██ ░████   ░████ 
░██    ░██  ░██  ░██████    ░███████  ░██    ░██░██   ░██   ░██    ░██ ░██░██ ░██░██ 
░████████   ░██       ░██  ░██    ░██ ░██   ░██ ░███████    ░██    ░██ ░██ ░████ ░██ 
░██     ░██ ░██  ░███████  ░██        ░███████  ░██   ░██    ░██  ░██  ░██  ░██  ░██ 
░██     ░██ ░██ ░██   ░██  ░██    ░██ ░██   ░██ ░██    ░██    ░██░██   ░██       ░██ 
░█████████  ░██  ░█████░██  ░███████  ░██    ░██░██     ░██    ░███    ░██       ░██ 

    BlackKVM  ·  by blackredit  ·  github.com/blackredit/blackvm
BANNER
echo -e "${NC}"

# ── Env defaults ──────────────────────────────────────────────────────────────
SERVER_PORT="${SERVER_PORT:-8080}"
VNC_PASSWORD="${VNC_PASSWORD:-black1234}"
RAM="${RAM:-2048}"
CPU_SOCKETS="${CPU_SOCKETS:-1}"
CPU_CORES="${CPU_CORES:-2}"
CPU_THREADS="${CPU_THREADS:-1}"
MACHINE_TYPE="${MACHINE_TYPE:-q35}"
USE_KVM="${USE_KVM:-1}"
USE_UEFI="${USE_UEFI:-1}"
DISK_FILE="${DISK_FILE:-disk.qcow2}"
DISK_CACHE="${DISK_CACHE:-none}"
SECONDARY_DISK="${SECONDARY_DISK:-}"
ISO_FILE="${ISO_FILE:-netboot.xyz.iso}"
SECONDARY_ISO="${SECONDARY_ISO:-}"
SHARED_DIR="${SHARED_DIR:-}"
USE_VIRTIO="${USE_VIRTIO:-0}"
USE_VIRTIO_NET="${USE_VIRTIO_NET:-0}"
FORWARD_PORTS="${FORWARD_PORTS:-hostfwd=tcp::8080-:80,hostfwd=tcp::2222-:22,hostfwd=tcp::3389-:3389}"
USE_GPU="${USE_GPU:-0}"
SOUND_ENABLED="${SOUND_ENABLED:-0}"
ENABLE_USB3="${ENABLE_USB3:-1}"
BALLOON_MEMORY="${BALLOON_MEMORY:-0}"
ENABLE_GUEST_AGENT="${ENABLE_GUEST_AGENT:-0}"
ENABLE_MONITOR_SOCKET="${ENABLE_MONITOR_SOCKET:-0}"
MONITOR_SOCKET="${MONITOR_SOCKET:-/tmp/blackvm.sock}"
ENABLE_QMP="${ENABLE_QMP:-0}"
QMP_SOCKET="${QMP_SOCKET:-/tmp/blackvm-qmp.sock}"
RTC_BASE="${RTC_BASE:-utc}"
BOOT_ORDER="${BOOT_ORDER:-dc}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

# ── Working directory & temp ──────────────────────────────────────────────────
cd /home/container
export TMPDIR=/home/container/tmp
mkdir -p "$TMPDIR" shared

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  1. Copy firmware & ISOs from image if not already present
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
info "Checking firmware & ISO assets..."

copy_asset() {
    local src="$1" dst="$2" label="$3"
    if [ -f "$src" ] && [ ! -f "$dst" ]; then
        cp "$src" "$dst" && chmod 666 "$dst"
        ok "Copied $label → $(basename "$dst")"
    elif [ -f "$dst" ]; then
        info "$label already present – keeping existing file"
    else
        warn "Source not found, skipping $label ($src)"
    fi
}

copy_asset /opt/blackvm/firmware/OVMF.fd    /home/container/OVMF.fd          "OVMF (UEFI)"
copy_asset /opt/blackvm/firmware/bios.bin   /home/container/bios.bin          "Legacy BIOS"
copy_asset /opt/blackvm/iso/netboot.xyz.iso /home/container/netboot.xyz.iso   "netboot.xyz ISO"

if [ "${SECONDARY_ISO}" = "virtio-win.iso" ] && [ ! -f /home/container/virtio-win.iso ]; then
    copy_asset /opt/blackvm/iso/virtio-win.iso /home/container/virtio-win.iso "VirtIO-Win ISO"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  2. VNC password file
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ ! -f /home/container/qemu_cmd.txt ]; then
    warn "qemu_cmd.txt missing – creating with VNC password from env"
    printf 'change vnc password\n%s\n' "${VNC_PASSWORD}" > /home/container/qemu_cmd.txt
    chmod 600 /home/container/qemu_cmd.txt
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  3. KVM check
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ "${USE_KVM}" = "1" ]; then
    if [ -c /dev/kvm ]; then
        ok "/dev/kvm present → hardware acceleration enabled"
    else
        warn "/dev/kvm NOT found → falling back to TCG software emulation (slow)"
        warn "Mount /dev/kvm on this node or set USE_KVM=0 to suppress this warning"
        USE_KVM="0"
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  4. Build QEMU command  (array → no quoting issues)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QEMU=()
QEMU+=( qemu-system-x86_64 )

# ── Machine & acceleration ───────────────────────────────────────────────────
if [ "${USE_KVM}" = "1" ]; then
    QEMU+=( -enable-kvm -machine "${MACHINE_TYPE},accel=kvm" -cpu host )
else
    QEMU+=( -machine "${MACHINE_TYPE},accel=tcg"
            -cpu max
            -accel tcg,thread=multi,tb-size=128,split-wx=on )
fi

# ── CPU topology ─────────────────────────────────────────────────────────────
QEMU+=( -smp "sockets=${CPU_SOCKETS},cores=${CPU_CORES},threads=${CPU_THREADS}" )

# ── Memory ───────────────────────────────────────────────────────────────────
QEMU+=( -m "${RAM}" )
[ "${BALLOON_MEMORY}" = "1" ] && QEMU+=( -device virtio-balloon-pci )

# ── RTC ──────────────────────────────────────────────────────────────────────
QEMU+=( -rtc "base=${RTC_BASE}" )

# ── BIOS / UEFI ──────────────────────────────────────────────────────────────
if [ "${USE_UEFI}" = "1" ] && [ -f OVMF.fd ]; then
    QEMU+=( -drive "if=pflash,format=raw,readonly=on,file=OVMF.fd" )
elif [ -f bios.bin ]; then
    QEMU+=( -bios bios.bin )
else
    warn "Neither OVMF.fd nor bios.bin found – QEMU will use its built-in BIOS"
fi

# ── Primary disk ─────────────────────────────────────────────────────────────
if [ ! -f "${DISK_FILE}" ]; then
    warn "Primary disk '${DISK_FILE}' not found – creating 100G placeholder"
    qemu-img create -f qcow2 "${DISK_FILE}" 100G
fi

if [ "${USE_VIRTIO}" = "1" ]; then
    QEMU+=( -drive "file=${DISK_FILE},format=qcow2,if=virtio,aio=native,cache.direct=on" )
else
    QEMU+=( -drive "file=${DISK_FILE},format=qcow2,if=ide,index=0,cache=${DISK_CACHE}" )
fi

# ── Secondary disk ────────────────────────────────────────────────────────────
if [ -n "${SECONDARY_DISK}" ] && [ -f "${SECONDARY_DISK}" ]; then
    QEMU+=( -drive "file=${SECONDARY_DISK},format=qcow2,if=virtio,index=1" )
    info "Secondary disk attached: ${SECONDARY_DISK}"
fi

# ── Primary ISO ───────────────────────────────────────────────────────────────
if [ -n "${ISO_FILE}" ] && [ -f "${ISO_FILE}" ]; then
    QEMU+=( -cdrom "${ISO_FILE}" )
fi

# ── Secondary ISO ─────────────────────────────────────────────────────────────
if [ -n "${SECONDARY_ISO}" ] && [ -f "${SECONDARY_ISO}" ]; then
    QEMU+=( -drive "file=${SECONDARY_ISO},media=cdrom,if=ide,readonly=on" )
    info "Secondary ISO attached: ${SECONDARY_ISO}"
fi

# ── Shared directory ─────────────────────────────────────────────────────────
if [ -n "${SHARED_DIR}" ] && [ -d "${SHARED_DIR}" ]; then
    QEMU+=( -drive "file=fat:rw:${SHARED_DIR},format=vvfat,label=SHARED" )
fi

# ── Network ──────────────────────────────────────────────────────────────────
if [ "${USE_VIRTIO_NET}" = "1" ]; then
    QEMU+=( -device "virtio-net-pci,netdev=n0" -netdev "user,id=n0,${FORWARD_PORTS}" )
else
    QEMU+=( -net nic -net "user,${FORWARD_PORTS}" )
fi

# ── Display / GPU ─────────────────────────────────────────────────────────────
if [ "${USE_GPU}" = "1" ]; then
    QEMU+=( -device virtio-gpu-gl-pci,max_hostmem=256M -display egl-headless )
else
    QEMU+=( -vga std )
fi

# ── Sound ────────────────────────────────────────────────────────────────────
[ "${SOUND_ENABLED}" = "1" ] && QEMU+=( -device ich9-intel-hda -device hda-output )

# ── USB ──────────────────────────────────────────────────────────────────────
if [ "${ENABLE_USB3}" = "1" ]; then
    QEMU+=( -device qemu-xhci -device usb-tablet )
else
    QEMU+=( -device usb-tablet )
fi

# ── QEMU Guest Agent ─────────────────────────────────────────────────────────
if [ "${ENABLE_GUEST_AGENT}" = "1" ]; then
    QEMU+=( -chardev "socket,path=/tmp/qga.sock,server=on,wait=off,id=qga0"
            -device virtio-serial-pci
            -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0" )
fi

# ── Monitor socket ────────────────────────────────────────────────────────────
if [ "${ENABLE_MONITOR_SOCKET}" = "1" ]; then
    QEMU+=( -monitor "unix:${MONITOR_SOCKET},server,nowait" )
else
    QEMU+=( -monitor stdio )
fi

# ── QMP socket ───────────────────────────────────────────────────────────────
[ "${ENABLE_QMP}" = "1" ] && QEMU+=( -qmp "unix:${QMP_SOCKET},server,nowait" )

# ── Boot order & VNC ─────────────────────────────────────────────────────────
QEMU+=( -boot "order=${BOOT_ORDER},menu=on,splash-time=5000" )
QEMU+=( -vnc "0.0.0.0:1,password=on" )

# ── Extra user args (parsed safely word-by-word) ─────────────────────────────
if [ -n "${EXTRA_ARGS}" ]; then
    read -ra EXTRA_ARR <<< "${EXTRA_ARGS}"
    QEMU+=( "${EXTRA_ARR[@]}" )
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  5. Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║           BlackVM  ·  Starting up               ║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "noVNC port:"    "${SERVER_PORT}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "VNC:"           "0.0.0.0:5901 (display :1)"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Guest RAM:"     "${RAM} MB"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Machine:"       "${MACHINE_TYPE}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "KVM:"           "$([ "${USE_KVM}" = "1" ] && echo 'Yes (hardware)' || echo 'No (TCG fallback)')"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "UEFI:"          "$([ "${USE_UEFI}" = "1" ] && echo 'Yes (OVMF)' || echo 'No (Legacy BIOS)')"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "CPU:"           "${CPU_SOCKETS}s × ${CPU_CORES}c × ${CPU_THREADS}t"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Primary disk:"  "${DISK_FILE}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Boot ISO:"      "${ISO_FILE:-none}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "VirtIO disk:"   "$([ "${USE_VIRTIO}" = "1" ] && echo Yes || echo No)"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "VirtIO net:"    "$([ "${USE_VIRTIO_NET}" = "1" ] && echo Yes || echo No)"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  6. Start noVNC / websockify (background)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
info "Starting noVNC on port ${SERVER_PORT}..."
cd /opt/novnc
./utils/websockify/run \
    --web /opt/novnc \
    "0.0.0.0:${SERVER_PORT}" \
    "localhost:5901" \
    > /home/container/tmp/novnc.log 2>&1 &
NOVNC_PID=$!
sleep 2
if kill -0 "${NOVNC_PID}" 2>/dev/null; then
    ok "noVNC running (pid ${NOVNC_PID})"
    ok "Open: http://YOUR-NODE-IP:${SERVER_PORT}"
else
    warn "noVNC failed – check /home/container/tmp/novnc.log"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  7. Launch QEMU  (exec replaces shell, array avoids all quoting issues)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cd /home/container
echo ""
ok "Launching QEMU..."
echo -e "${CYAN}${BOLD}Command: ${NC}${QEMU[*]}"
echo -e "${CYAN}─────────────────────────────────────────────────────${NC}"

# Feed VNC password via stdin, keep stdin open so QEMU doesn't get EOF
exec "${QEMU[@]}" < <(cat qemu_cmd.txt; tail -f /dev/null)
