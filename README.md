# BlackVM

> Full KVM/QEMU virtual machines on Pterodactyl — by **blackredit**

![Build & Push](https://github.com/blackredit/blackvm/actions/workflows/docker-publish.yml/badge.svg)

---

## 🚀 Features

| Feature | Details |
|---|---|
| **KVM Acceleration** | Hardware-accelerated VMs via Intel VT-x / AMD-V |
| **Machine Types** | q35 (PCIe, recommended) or pc (legacy i440fx) |
| **UEFI & BIOS** | OVMF UEFI or Legacy BIOS selectable per server |
| **Multi-Disk** | Primary + optional secondary QCOW2 disk |
| **Dual ISO Slots** | Primary boot ISO + secondary (e.g. VirtIO drivers for Windows) |
| **VirtIO Disk** | High-performance VirtIO or safe IDE emulation |
| **VirtIO Network** | VirtIO NIC or legacy Realtek RTL8139 |
| **VirtIO GPU** | Experimental VirtIO GPU with EGL headless |
| **USB 3.0** | xHCI controller + USB tablet for accurate mouse |
| **Sound Card** | Intel HDA (ich9) optional |
| **Memory Balloon** | Dynamic RAM reclaim via VirtIO balloon driver |
| **CPU Topology** | Configurable sockets / cores / threads |
| **CPU Limiter** | `cpulimit`-based host CPU cap |
| **Guest Agent** | virtio-serial device for QEMU Guest Agent |
| **Snapshots** | Offline snapshot save/restore via helper script |
| **noVNC** | Browser-based VNC remote desktop |
| **netboot.xyz** | Pre-installed for network OS installation |
| **VirtIO Drivers** | VirtIO-Win ISO pre-downloaded for Windows guests |
| **Shared Directory** | Host ↔ Guest FAT32 shared folder |

---

## 🛠 Node Setup (Required)

### 1 — Enable KVM on the Host

```bash
# Verify KVM is available
ls -la /dev/kvm

# Fix permissions (run once + add to crontab for persistence)
chmod 666 /dev/kvm
(crontab -l 2>/dev/null; echo "@reboot chmod 666 /dev/kvm") | crontab -
```

### 2 — Replace Wings Binary (BlackVM-compatible Wings)

```bash
cd /opt/pterodactyl
systemctl stop wings
rm wings
curl -L -o wings https://github.com/blackredit/blackvm/releases/latest/download/wings
chmod +x wings
```

`/etc/systemd/system/wings.service`:

```ini
[Unit]
Description=Pterodactyl Wings Daemon (BlackVM)
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

### 3 — Create the /dev/kvm Mount in Pterodactyl

1. **Admin → Mounts → New Mount**
   - Source: `/dev/kvm`
   - Target: `/dev/kvm`
   - Read-only: No
2. Assign the mount to your **Node** and to the **BlackVM Egg**
3. On each BlackVM server: **Server → Mounts → Add /dev/kvm → Restart**

---

## 📦 Installing the Egg

1. **Admin → Nests → Import Egg**
2. Upload `egg/egg-blackvm.json`
3. Set the Docker image to: `ghcr.io/blackredit/blackvm:latest`

---

## ⚙️ Key Variables

| Variable | Default | Description |
|---|---|---|
| `RAM` | `2048` | Guest RAM in MB |
| `USE_KVM` | `1` | Hardware acceleration |
| `MACHINE_TYPE` | `q35` | QEMU machine chipset |
| `USE_UEFI` | `1` | UEFI (OVMF) or Legacy BIOS |
| `DISK_FILE` | `disk.qcow2` | Primary disk image |
| `DISK_SIZE` | `100G` | Disk size (install only) |
| `SECONDARY_DISK` | _(blank)_ | Optional second disk |
| `ISO_FILE` | `netboot.xyz.iso` | Boot ISO |
| `SECONDARY_ISO` | _(blank)_ | Driver ISO (e.g. VirtIO-Win) |
| `VNC_PASSWORD` | `black1234` | noVNC/VNC password |
| `FORWARD_PORTS` | RDP/SSH/HTTP | Guest port forwards |
| `CPU_CORES` | `2` | vCPU cores |
| `CPU_LIMIT` | `0` | Host CPU cap in % (0=unlimited) |
| `USE_VIRTIO` | `0` | VirtIO disk driver |
| `USE_VIRTIO_NET` | `0` | VirtIO network driver |
| `SOUND_ENABLED` | `0` | Intel HDA sound card |
| `ENABLE_USB3` | `1` | USB 3.0 xHCI controller |
| `BALLOON_MEMORY` | `0` | Dynamic memory balloon |
| `ENABLE_GUEST_AGENT` | `0` | QEMU Guest Agent serial port |
| `SNAPSHOT_LOAD` | _(blank)_ | Snapshot name to restore on boot |
| `EXTRA_ARGS` | _(blank)_ | Raw QEMU extra args |

---

## 🪟 Windows Guest Guide

1. Set `USE_VIRTIO=0` and `USE_VIRTIO_NET=0` (IDE/RTL8139 for install)
2. Set `SECONDARY_ISO=virtio-win.iso`
3. Install Windows normally
4. Inside Windows, open the VirtIO ISO and install all drivers
5. Set `USE_VIRTIO=1` and `USE_VIRTIO_NET=1` for maximum performance
6. Minimum `RAM=4096`

---

## 🔧 Helper Scripts

All scripts live at `/scripts/` inside the container:

```bash
# Snapshot management
/scripts/snapshot.sh list
/scripts/snapshot.sh save   my-clean-install  [disk.qcow2]
/scripts/snapshot.sh load   my-clean-install  [disk.qcow2]
/scripts/snapshot.sh delete my-clean-install  [disk.qcow2]
/scripts/snapshot.sh info                     [disk.qcow2]

# Disk resize (VM must be stopped)
/scripts/resize-disk.sh disk.qcow2 +50G

# QEMU monitor (requires EXTRA_ARGS=-monitor unix:/tmp/blackvm-monitor.sock,server,nowait)
/scripts/monitor.sh "info status"
/scripts/monitor.sh "system_powerdown"
/scripts/monitor.sh "savevm live-snap"

# Status / diagnostics
/scripts/status.sh
```

---

## ⚠️ Notes

- **Nested virtualisation** must be enabled on your host node; BlackVM cannot work in a VM without it
- This project is for **development and testing** purposes; it is not a replacement for Proxmox or ESXi
- VirtIO drivers for Windows: always install with VirtIO **disabled** first, then enable after driver installation

---

© 2026 **blackredit** — [github.com/blackredit/blackvm](https://github.com/blackredit/blackvm)
