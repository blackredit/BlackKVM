#!/bin/bash
# BlackVM – Status & Diagnose  (/scripts/status.sh)
C='\033[0;36m'; G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[1m'; N='\033[0m'
sep() { echo -e "${C}────────────────────────────────────────${N}"; }

echo -e "${B}${C}  BlackVM – Systemstatus${N}"; sep

echo -e "${B}KVM / Virtualisierung${N}"
[ -c /dev/kvm ] \
    && echo -e "  ${G}[✔]${N} /dev/kvm vorhanden (Rechte: $(stat -c '%a' /dev/kvm))" \
    || echo -e "  ${R}[✘]${N} /dev/kvm fehlt – KVM nicht verfügbar"
grep -qE 'vmx|svm' /proc/cpuinfo \
    && echo -e "  ${G}[✔]${N} CPU-Virtualisierungsflags erkannt (vmx/svm)" \
    || echo -e "  ${R}[✘]${N} Keine vmx/svm-Flags – Nested Virt deaktiviert?"
sep

echo -e "${B}QEMU-Prozess${N}"
if pgrep -x qemu-system-x86 > /dev/null 2>&1; then
    PID=$(pgrep -x qemu-system-x86)
    RSS=$(awk '/VmRSS/{print $2" "$3}' /proc/"${PID}"/status 2>/dev/null || echo "?")
    echo -e "  ${G}[✔]${N} QEMU läuft (pid: ${PID}, RSS: ${RSS})"
else
    echo -e "  ${Y}[–]${N} QEMU läuft nicht"
fi
sep

echo -e "${B}noVNC${N}"
pgrep -f websockify > /dev/null 2>&1 \
    && echo -e "  ${G}[✔]${N} websockify läuft (pid: $(pgrep -f websockify))" \
    || echo -e "  ${R}[✘]${N} websockify läuft nicht"
sep

echo -e "${B}Disk-Images${N}"
for f in /home/container/*.qcow2; do
    [ -f "${f}" ] || continue
    VSIZE=$(qemu-img info "${f}" 2>/dev/null | awk '/virtual size/{print $3,$4}')
    DSIZE=$(qemu-img info "${f}" 2>/dev/null | awk '/disk size/{print $3,$4}')
    SNAPS=$(qemu-img snapshot -l "${f}" 2>/dev/null | grep -c TAG || echo 0)
    echo -e "  ${G}●${N} $(basename "${f}") – Virtuell: ${VSIZE} | Belegt: ${DSIZE} | Snaps: ${SNAPS}"
done
sep

echo -e "${B}Host-Ressourcen${N}"
echo -e "  CPUs  : $(nproc) logisch"
echo -e "  RAM   : $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) MB frei / $(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo) MB gesamt"
sep
echo -e "  noVNC-Log: $(tail -1 /tmp/novnc.log 2>/dev/null || echo 'kein Log')"
echo ""