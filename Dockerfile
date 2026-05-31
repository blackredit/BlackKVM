FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="BlackVM"
LABEL org.opencontainers.image.description="KVM/QEMU virtual machines on Pterodactyl – by blackredit"
LABEL org.opencontainers.image.source="https://github.com/blackredit/blackvm"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  1. System packages  (everything baked in – no internet access at runtime)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-system-x86 \
        qemu-utils \
        ovmf \
        iproute2 \
        net-tools \
        socat \
        bash \
        curl \
        wget \
        ca-certificates \
        git \
        jq \
        procps \
        pciutils \
        cpulimit \
        python3 \
        python3-numpy \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  2. noVNC
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN git clone --depth 1 https://github.com/novnc/noVNC      /opt/novnc \
 && git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify \
 && cp /opt/novnc/vnc.html /opt/novnc/index.html

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  3. Firmware  (copy from installed packages – no external download needed)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN mkdir -p /opt/blackvm/firmware /opt/blackvm/iso \
    \
    # ── OVMF (UEFI) – installed by the 'ovmf' apt package ─────────────────
 && OVMF_SRC=$(find /usr/share/OVMF /usr/share/ovmf -name 'OVMF.fd' 2>/dev/null | head -1) \
 && if [ -n "$OVMF_SRC" ]; then \
        echo "[+] Copying OVMF from $OVMF_SRC"; \
        cp "$OVMF_SRC" /opt/blackvm/firmware/OVMF.fd; \
    else \
        echo "[!] OVMF.fd not found in /usr/share – check 'ovmf' package"; \
        exit 1; \
    fi \
    \
    # ── Legacy BIOS – installed by 'qemu-system-x86' ───────────────────────
 && BIOS_SRC=$(find /usr/share/qemu /usr/share/seabios -name 'bios.bin' 2>/dev/null | head -1) \
 && if [ -n "$BIOS_SRC" ]; then \
        echo "[+] Copying bios.bin from $BIOS_SRC"; \
        cp "$BIOS_SRC" /opt/blackvm/firmware/bios.bin; \
    else \
        echo "[!] bios.bin not found in /usr/share – check 'qemu-system-x86' package"; \
        exit 1; \
    fi \
    \
    # ── netboot.xyz (~400 KB) ──────────────────────────────────────────────
 && echo "[+] Downloading netboot.xyz..." \
 && wget -q --show-progress --tries=3 --timeout=30 \
        -O /opt/blackvm/iso/netboot.xyz.iso \
        "https://boot.netboot.xyz/ipxe/netboot.xyz.iso" \
    \
    # virtio-win.iso is ~500 MB – baking it in doubles the image size.
    # The entrypoint downloads it on first use if SECONDARY_ISO=virtio-win.iso
    # and it is not already present in /home/container/.
    \
 && echo "[+] Firmware & ISO assets ready:" \
 && ls -lh /opt/blackvm/firmware/ /opt/blackvm/iso/

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  4. Scripts & entrypoint
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY scripts/      /opt/blackvm/scripts/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/blackvm/scripts/*.sh \
 && ln -sf /opt/blackvm/scripts/snapshot.sh    /usr/local/bin/bvm-snapshot \
 && ln -sf /opt/blackvm/scripts/resize-disk.sh /usr/local/bin/bvm-resize \
 && ln -sf /opt/blackvm/scripts/monitor.sh     /usr/local/bin/bvm-monitor \
 && ln -sf /opt/blackvm/scripts/status.sh      /usr/local/bin/bvm-status

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  5. Runtime user & directories
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN useradd -m -d /home/container container \
 && mkdir -p /home/container/shared /home/container/tmp \
 && chmod 777 /home/container/shared /home/container/tmp

USER container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
