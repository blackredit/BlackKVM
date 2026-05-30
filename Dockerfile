FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="BlackVM"
LABEL org.opencontainers.image.description="KVM/QEMU virtual machines on Pterodactyl – by blackredit"
LABEL org.opencontainers.image.source="https://github.com/blackredit/blackvm"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# ── 1. System packages ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # QEMU / KVM
        qemu-system-x86 \
        qemu-utils \
        ovmf \
        # Network tools
        iproute2 \
        net-tools \
        socat \
        # General utilities
        bash \
        curl \
        wget \
        ca-certificates \
        git \
        procps \
        # noVNC dependencies
        python3 \
        python3-numpy \
        python3-websockify \
        # Resource management
        cpulimit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── 2. noVNC ──────────────────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/novnc/noVNC        /opt/novnc \
 && git clone --depth 1 https://github.com/novnc/websockify   /opt/novnc/utils/websockify \
 && cp /opt/novnc/vnc.html /opt/novnc/index.html

# ── 3. OVMF + Legacy BIOS (baked into the image – no download at runtime) ────
#    OVMF is installed by the 'ovmf' package above; we also bundle a legacy
#    SeaBIOS binary so both boot modes work without any external download.
RUN mkdir -p /opt/blackvm/firmware \
 # Copy OVMF from the system package
 && cp /usr/share/OVMF/OVMF.fd /opt/blackvm/firmware/OVMF.fd \
 # SeaBIOS (comes with qemu-system-x86)
 && cp /usr/share/seabios/bios.bin /opt/blackvm/firmware/bios.bin \
 && chmod 644 /opt/blackvm/firmware/*

# ── 4. Scripts & entrypoint ───────────────────────────────────────────────────
COPY entrypoint.sh  /entrypoint.sh
COPY scripts/       /scripts/
RUN chmod +x /entrypoint.sh /scripts/*.sh

# ── 5. Container user & runtime dirs ─────────────────────────────────────────
RUN useradd -m -d /home/container container \
 && mkdir -p /home/container/shared \
             /home/container/snapshots \
             /home/container/tmp \
 && chmod 777 /home/container/shared \
              /home/container/snapshots \
              /home/container/tmp

USER container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]