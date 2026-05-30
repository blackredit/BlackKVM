#!/bin/bash
# =============================================================================
#  BlackVM – Entrypoint
#  github.com/blackredit/blackvm
#
#  This script:
#   1. Copies firmware & ISOs from the image (/opt/blackvm/) to /home/container/
#      if they don't already exist (so user-supplied files are never overwritten)
#   2. Starts noVNC / websockify in the background
#   3. Evals the QEMU startup command passed by Pterodactyl via $STARTUP
# =============================================================================

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✔]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

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

# ── Environment ───────────────────────────────────────────────────────────────
cd /home/container
export TMPDIR=/home/container/tmp
mkdir -p "$TMPDIR" shared

# ── 1. Copy firmware from image (never overwrite existing user files) ─────────
info "Checking firmware & ISO assets..."

copy_asset() {
    local src="$1"
    local dst="$2"
    local label="$3"
    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        chmod 666 "$dst"
        ok "Copied $label → $(basename "$dst")"
    else
        info "$label already present – keeping existing file"
    fi
}

copy_asset /opt/blackvm/firmware/OVMF.fd   /home/container/OVMF.fd       "OVMF (UEFI)"
copy_asset /opt/blackvm/firmware/bios.bin  /home/container/bios.bin       "Legacy BIOS"
copy_asset /opt/blackvm/iso/netboot.xyz.iso /home/container/netboot.xyz.iso "netboot.xyz ISO"

# virtio-win.iso only if user enabled it via SECONDARY_ISO env var
if [ "${SECONDARY_ISO:-}" = "virtio-win.iso" ] && [ ! -f /home/container/virtio-win.iso ]; then
    copy_asset /opt/blackvm/iso/virtio-win.iso /home/container/virtio-win.iso "VirtIO-Win ISO"
fi

# ── 2. VNC password file (written by install script, but guard here too) ──────
if [ ! -f /home/container/qemu_cmd.txt ]; then
    warn "qemu_cmd.txt missing – creating with default VNC password"
    VNC_PASSWORD="${VNC_PASSWORD:-black1234}"
    echo 'change vnc password' > /home/container/qemu_cmd.txt
    echo "${VNC_PASSWORD}"    >> /home/container/qemu_cmd.txt
    chmod 600 /home/container/qemu_cmd.txt
fi

# ── 3. KVM availability ───────────────────────────────────────────────────────
if [ -c /dev/kvm ]; then
    ok "/dev/kvm present → hardware acceleration available"
else
    warn "/dev/kvm NOT found → KVM disabled, TCG fallback will be used (slow)"
    warn "See README: create /dev/kvm mount in Pterodactyl or set USE_KVM=0"
    USE_KVM=0
fi

# ── 4. Status summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║           BlackVM  ·  Starting up               ║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "noVNC port:"   "${SERVER_PORT:-8080}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "VNC display:"  ":1  (port 5901)"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Guest RAM:"    "${RAM:-2048} MB"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "KVM:"          "$([ -c /dev/kvm ] && echo 'Yes (hardware)' || echo 'No (TCG fallback)')"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "UEFI:"         "${USE_UEFI:-1}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Disk:"         "${DISK_FILE:-disk.qcow2}"
printf "${CYAN}║${NC}  %-22s %-24s ${CYAN}║${NC}\n" "Boot ISO:"     "${ISO_FILE:-netboot.xyz.iso}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ── 5. Start noVNC / websockify (background) ──────────────────────────────────
info "Starting noVNC on port ${SERVER_PORT:-8080}..."
cd /opt/novnc
./utils/websockify/run \
    --web /opt/novnc \
    0.0.0.0:"${SERVER_PORT:-8080}" \
    localhost:5901 \
    > /home/container/tmp/novnc.log 2>&1 &
NOVNC_PID=$!
sleep 2
if kill -0 "$NOVNC_PID" 2>/dev/null; then
    ok "noVNC running (pid ${NOVNC_PID})"
    ok "Connect via: http://YOUR-NODE-IP:${SERVER_PORT:-8080}"
else
    warn "noVNC failed to start – check /home/container/tmp/novnc.log"
fi

# ── 6. Launch QEMU via Pterodactyl STARTUP command ────────────────────────────
cd /home/container
echo ""
ok "Handing off to QEMU..."
echo -e "${CYAN}─────────────────────────────────────────────────────${NC}"

# Convert Pterodactyl {{VARIABLE}} → ${VARIABLE} and eval
MODIFIED_STARTUP=$(printf '%s' "${STARTUP}" | tr -d '\r' | sed -e 's/{{/${/g' -e 's/}}/}/g' -e 's/--enable-kvm/-enable-kvm/g')
# Older imported eggs may still render an invalid IDE cache value. Rewrite the
# exact IDE drive option to a safe cache mode so stale imports still work.
MODIFIED_STARTUP=$(printf '%s' "$MODIFIED_STARTUP" | perl -0pe 's|-drive file=([^ ]+),format=qcow2,if=ide,index=0,cache=[^ ]+|-drive file=$1,format=qcow2,if=ide,index=0,cache=none|g')
# Feed the initial monitor commands, then keep stdin open so QEMU does not
# receive EOF and exit immediately with code 0.
eval "exec ${MODIFIED_STARTUP}" < <(cat qemu_cmd.txt; tail -f /dev/null)
