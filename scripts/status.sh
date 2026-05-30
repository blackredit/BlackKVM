#!/bin/bash
# BlackVM – Status & Diagnostics  |  Usage: bvm-status
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
sep() { echo -e "${CYAN}──────────────────────────────────────────${NC}"; }
echo -e "${BOLD}${CYAN}  BlackVM – Status${NC}"; sep
echo -e "${BOLD}KVM${NC}"
[ -c /dev/kvm ] \
    && echo -e "  ${GREEN}[✔]${NC} /dev/kvm present (perms: $(stat -c '%a' /dev/kvm))" \
    || echo -e "  ${RED}[✘]${NC} /dev/kvm missing – no hardware acceleration"
grep -qE 'vmx|svm' /proc/cpuinfo \
    && echo -e "  ${GREEN}[✔]${NC} CPU virtualisation flags detected" \
    || echo -e "  ${RED}[✘]${NC} vmx/svm not in /proc/cpuinfo"
sep
echo -e "${BOLD}QEMU${NC}"
if pgrep -x qemu-system-x86 > /dev/null 2>&1; then
    QPID=$(pgrep -x qemu-system-x86)
    echo -e "  ${GREEN}[✔]${NC} QEMU running (pid: $QPID)"
    echo -e "       RSS: $(awk '/VmRSS/{print $2" "$3}' /proc/$QPID/status 2>/dev/null || echo n/a)"
else
    echo -e "  ${YELLOW}[–]${NC} QEMU is not running"
fi
sep
echo -e "${BOLD}noVNC${NC}"
pgrep -f websockify > /dev/null 2>&1 \
    && echo -e "  ${GREEN}[✔]${NC} websockify running (pid: $(pgrep -f websockify))" \
    || echo -e "  ${RED}[✘]${NC} websockify not running"
sep
echo -e "${BOLD}Disks${NC}"
for f in /home/container/*.qcow2; do
    [ -f "$f" ] || continue
    VSIZE=$(qemu-img info "$f" 2>/dev/null | awk '/virtual size/{print $3,$4}')
    ASIZE=$(qemu-img info "$f" 2>/dev/null | awk '/disk size/{print $3,$4}')
    SNAPS=$(qemu-img snapshot -l "$f" 2>/dev/null | grep -c 'snap' || echo 0)
    echo -e "  ${GREEN}●${NC} $(basename $f)  virtual:$VSIZE  on-disk:$ASIZE  snapshots:$SNAPS"
done
sep
echo -e "${BOLD}Host Resources${NC}"
echo -e "  CPUs  : $(nproc) logical"
echo -e "  Memory: $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) MB free / $(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo) MB total"
echo ""
