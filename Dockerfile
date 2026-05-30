FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="BlackVM"
LABEL org.opencontainers.image.description="KVM/QEMU virtual machines on Pterodactyl – by blackredit"
LABEL org.opencontainers.image.source="https://github.com/blackredit/blackvm"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  1. System packages
#     Everything is installed here – the container never needs internet access
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN apt-get update && apt-get install -y --no-install-recommends \
        # QEMU / KVM
        qemu-system-x86 \
        qemu-utils \
        ovmf \
        # Networking
        iproute2 \
        net-tools \
        socat \
        # Scripting & tools
        bash \
        curl \
        wget \
        ca-certificates \
        git \
        jq \
        procps \
        pciutils \
        cpulimit \
        # Python (noVNC websockify)
        python3 \
        python3-numpy \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  2. noVNC  (browser-based VNC client)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN git clone --depth 1 https://github.com/novnc/noVNC         /opt/novnc \
 && git clone --depth 1 https://github.com/novnc/websockify    /opt/novnc/utils/websockify \
 && cp /opt/novnc/vnc.html /opt/novnc/index.html

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  3. Bake in firmware and ISOs
#     These are stored in /opt/blackvm/ inside the image.
#     entrypoint.sh copies them to /home/container/ on first boot.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN mkdir -p /opt/blackvm/firmware /opt/blackvm/iso \
    # ── OVMF (UEFI firmware) – installed via apt, just copy it ──────────────
 && OVMF_SRC="$(find /usr/share -name 'OVMF.fd' 2>/dev/null | head -1)" \
 && if [ -n "$OVMF_SRC" ]; then \
        cp "$OVMF_SRC" /opt/blackvm/firmware/OVMF.fd; \
    else \
        echo "OVMF.fd not found via apt – downloading fallback..."; \
        wget -q -O /opt/blackvm/firmware/OVMF.fd \
            "https://github.com/blackredit/blackvm/releases/download/assets/OVMF.fd"; \
    fi \
    # ── Legacy BIOS – bundled with qemu-system-x86 ──────────────────────────
 && BIOS_SRC="$(find /usr/share/qemu -name 'bios.bin' 2>/dev/null | head -1)" \
 && if [ -n "$BIOS_SRC" ]; then \
        cp "$BIOS_SRC" /opt/blackvm/firmware/bios.bin; \
    else \
        echo "bios.bin not found – downloading fallback..."; \
        wget -q -O /opt/blackvm/firmware/bios.bin \
            "https://github.com/blackredit/blackvm/releases/download/assets/bios.bin"; \
    fi \
    # ── netboot.xyz (network OS installer) ──────────────────────────────────
 && wget -q --show-progress \
        -O /opt/blackvm/iso/netboot.xyz.iso \
        "https://boot.netboot.xyz/ipxe/netboot.xyz.iso" \
    # ── VirtIO drivers for Windows ──────────────────────────────────────────
 && wget -q --show-progress \
        -O /opt/blackvm/iso/virtio-win.iso \
        "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win.iso" \
 && echo "--- Baked assets ---" \
 && ls -lh /opt/blackvm/firmware/ /opt/blackvm/iso/

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  4. Scripts & entrypoint
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COPY scripts/      /opt/blackvm/scripts/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/blackvm/scripts/*.sh \
 && ln -sf /opt/blackvm/scripts/snapshot.sh     /usr/local/bin/bvm-snapshot \
 && ln -sf /opt/blackvm/scripts/resize-disk.sh  /usr/local/bin/bvm-resize \
 && ln -sf /opt/blackvm/scripts/monitor.sh      /usr/local/bin/bvm-monitor \
 && ln -sf /opt/blackvm/scripts/status.sh       /usr/local/bin/bvm-status

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  5. Runtime user & working directory
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN useradd -m -d /home/container container \
 && mkdir -p /home/container/shared /home/container/tmp \
 && chmod 777 /home/container/shared /home/container/tmp

USER container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
