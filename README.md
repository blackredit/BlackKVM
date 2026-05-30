# BlackVM

> **Full KVM/QEMU virtual machines on Pterodactyl** — by [blackredit](https://github.com/blackredit)

[![Build & Push to ghcr.io](https://github.com/blackredit/blackvm/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/blackredit/blackvm/actions/workflows/docker-publish.yml)
[![Release Wings](https://github.com/blackredit/blackvm/actions/workflows/release-wings.yml/badge.svg)](https://github.com/blackredit/blackvm/actions/workflows/release-wings.yml)

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions                                                  │
│                                                                  │
│  docker-publish.yml  →  builds Docker image                      │
│                         downloads OVMF + bios + ISOs ONCE        │
│                         pushes to ghcr.io/blackredit/blackvm    │
│                                                                  │
│  release-wings.yml   →  publishes Wings binary as GitHub Release │
└─────────────────────────────────────────────────────────────────┘
                          │                        │
                          ▼                        ▼
              ┌────────────────────┐   ┌────────────────────────┐
              │  Docker Image      │   │  GitHub Release         │
              │  (ghcr.io)         │   │  wings-latest           │
              │                    │   │  • wings (binary)       │
              │  ✓ QEMU            │   │  • wings.sha256         │
              │  ✓ OVMF.fd         │   └────────────────────────┘
              │  ✓ bios.bin        │
              │  ✓ netboot.xyz.iso │
              │  ✓ virtio-win.iso  │
              │  ✓ noVNC           │
              │  ✓ all scripts     │
              └────────────────────┘
                          │
                          ▼
              ┌────────────────────┐
              │  Pterodactyl Egg   │
              │  (egg-blackvm.json)│
              │                    │
              │  Install script:   │
              │  • qemu-img create │  ← ONLY this, no downloads
              │  • VNC password    │
              │                    │
              │  Startup:          │
              │  • entrypoint.sh   │  ← copies assets from image
              │  • QEMU command    │  ← built from egg variables
              └────────────────────┘
```

**The Docker image contains everything.** The egg installation script only creates the disk and sets the VNC password. No downloads happen at server install time.

---

## 🚀 Features

| Feature | Details |
|---|---|
| **KVM Acceleration** | Intel VT-x / AMD-V hardware virtualisation |
| **Machine Types** | `q35` (modern PCIe) or `pc` (legacy i440fx) |
| **UEFI & BIOS** | OVMF UEFI or Legacy BIOS – selectable per server |
| **Multi-Disk** | Primary + secondary QCOW2 disk |
| **Dual ISO Slots** | Boot ISO + driver ISO (VirtIO-Win pre-installed) |
| **VirtIO Disk** | High-performance VirtIO or IDE emulation |
| **VirtIO Network** | VirtIO NIC or Realtek RTL8139 |
| **VirtIO GPU** | Experimental VirtIO GPU + EGL headless |
| **USB 3.0** | xHCI controller + USB tablet |
| **Sound Card** | Intel HDA (ich9-intel-hda) |
| **Memory Balloon** | Dynamic RAM reclaim via VirtIO |
| **CPU Topology** | Sockets / Cores / Threads |
| **Guest Agent** | QEMU Guest Agent (virtio-serial) |
| **noVNC** | Browser-based VNC remote desktop |
| **netboot.xyz** | Network OS installer (pre-installed in image) |
| **VirtIO Drivers** | VirtIO-Win ISO (pre-installed in image) |
| **Shared Dir** | Host ↔ Guest FAT32 shared folder |
| **Snapshots** | `bvm-snapshot` helper |
| **Disk Resize** | `bvm-resize` helper |
| **Monitor** | `bvm-monitor` QEMU monitor helper |

---

## 🛠 Node Setup

### 1 — Install the BlackVM KVM Wings fork

Download from the [latest KVM Wings release](https://github.com/blackredit/blackvm/releases/tag/wings-latest):

```bash
cd /opt/pterodactyl
systemctl stop wings
rm -f wings
curl -fsSL \
  -o wings \
  https://github.com/blackredit/blackvm/releases/download/wings-latest/wings
chmod +x wings
```

`/etc/systemd/system/wings.service`:

```ini
[Unit]
Description=Pterodactyl Wings Daemon (BlackVM KVM Fork)
After=docker.service
Requires=docker.service

[Service]
User=root
Group=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/opt/pterodactyl/wings
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl restart wings
```

### 2 — Enable /dev/kvm

```bash
# Verify KVM is available
ls -la /dev/kvm

# Fix permissions permanently
chmod 666 /dev/kvm
(crontab -l 2>/dev/null; echo "@reboot chmod 666 /dev/kvm") | crontab -
```

### 3 — Mount /dev/kvm in Pterodactyl

1. **Admin → Mounts → Create Mount**
   - Source: `/dev/kvm`
   - Target: `/dev/kvm`
   - Read-only: No
2. Assign the mount to your **Node** and to the **BlackVM Egg**
3. Per server: **Server → Mounts → Add /dev/kvm → Restart**

---

## 📦 Import the Egg

1. **Admin → Nests → Import Egg**
2. Upload `egg/egg-blackvm.json`
3. Docker image is already set to: `ghcr.io/blackredit/blackvm:latest`

---

## ⚙️ Egg Variables

| Variable | Default | Description |
|---|---|---|
| `SERVER_PORT` | `8080` | noVNC web port |
| `VNC_PASSWORD` | `black1234` | VNC / noVNC password |
| `RAM` | `2048` | Guest RAM in MB |
| `USE_KVM` | `1` | Hardware acceleration |
| `MACHINE_TYPE` | `q35` | QEMU chipset |
| `USE_UEFI` | `1` | UEFI or Legacy BIOS |
| `DISK_FILE` | `disk.qcow2` | Primary disk filename |
| `DISK_SIZE` | `100G` | Disk size (install only) |
| `DISK_CACHE` | `writeback` | Disk I/O cache mode |
| `SECONDARY_DISK` | _(blank)_ | Optional second disk |
| `SECONDARY_DISK_SIZE` | `50G` | Second disk size |
| `ISO_FILE` | `netboot.xyz.iso` | Primary boot ISO |
| `SECONDARY_ISO` | _(blank)_ | Driver ISO slot |
| `USE_VIRTIO` | `0` | VirtIO disk driver |
| `USE_VIRTIO_NET` | `0` | VirtIO network driver |
| `FORWARD_PORTS` | RDP/SSH/HTTP | Guest port forwards |
| `CPU_SOCKETS` | `1` | vCPU sockets |
| `CPU_CORES` | `2` | vCPU cores |
| `CPU_THREADS` | `1` | vCPU threads |
| `BALLOON_MEMORY` | `0` | Memory balloon |
| `USE_GPU` | `0` | VirtIO GPU |
| `SOUND_ENABLED` | `0` | Intel HDA sound |
| `ENABLE_USB3` | `1` | USB 3.0 xHCI |
| `ENABLE_GUEST_AGENT` | `0` | QEMU Guest Agent |
| `SHARED_DIR` | _(blank)_ | Shared folder path |
| `EXTRA_ARGS` | _(blank)_ | Extra QEMU args |

---

## 🪟 Windows Guest Guide

1. Set `USE_VIRTIO=0` and `USE_VIRTIO_NET=0` (IDE + Realtek for install)
2. Set `SECONDARY_ISO=virtio-win.iso` (already in the image, just set this)
3. Install Windows normally via netboot.xyz or custom ISO
4. After install, open the VirtIO ISO inside Windows and install all drivers
5. Set `USE_VIRTIO=1` and `USE_VIRTIO_NET=1` for maximum performance
6. Minimum: `RAM=4096`

---

## 🔧 Helper Scripts (inside the container)

```bash
# Snapshots (VM must be stopped for offline snapshots)
bvm-snapshot list
bvm-snapshot save   my-snapshot  [disk.qcow2]
bvm-snapshot load   my-snapshot  [disk.qcow2]
bvm-snapshot delete my-snapshot  [disk.qcow2]

# Live snapshots via QEMU monitor (VM running)
# First add to EXTRA_ARGS: -monitor unix:/tmp/bvm.sock,server,nowait
bvm-monitor "savevm live-snap"
bvm-monitor "loadvm live-snap"
bvm-monitor "system_powerdown"

# Disk resize (stop VM first)
bvm-resize disk.qcow2 +50G

# Diagnostics
bvm-status
```

---

## ⚠️ Requirements & Notes

- **Nested virtualisation** must be enabled on the host node (`/dev/kvm` must exist)
- **VirtIO drivers**: always install Windows with VirtIO *disabled*, enable after driver install
- This egg is intended for development/testing – not a replacement for Proxmox/ESXi

---

© 2026 **blackredit** — [github.com/blackredit/blackvm](https://github.com/blackredit/blackvm)
