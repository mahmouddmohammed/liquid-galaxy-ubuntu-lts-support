<div align="center">
  <img src="docs/imgs/ubuntu-lts-support.png" alt="Liquid Galaxy Ubuntu LTS Support" height="200" />

  # Ubuntu LTS Support for Liquid Galaxy

  **Automated installer bringing Liquid Galaxy to modern, currently-supported Ubuntu LTS releases**

  [![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_%7C_26.04_LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
  [![Bash](https://img.shields.io/badge/Bash-Installer-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
  [![Google Earth](https://img.shields.io/badge/Google_Earth-Pro-4285F4?logo=googleearth&logoColor=white)](https://www.google.com/earth/versions/)
  [![Liquid Galaxy](https://img.shields.io/badge/Liquid_Galaxy-Compatible-34A853?logo=googleearth&logoColor=white)](https://www.liquidgalaxy.eu)
  
  *A Google Summer of Code 2026 project under [Liquid Galaxy LAB](https://www.liquidgalaxy.eu)*
</div>

---

## What is Liquid Galaxy?

Liquid Galaxy is an open-source project, originally created by Google, that creates a synchronized panoramic display across multiple screens driven by multiple computers. It is most commonly used with **Google Earth Pro**, allowing users to experience immersive, wide-angle geographic visualizations.

Liquid Galaxy is not limited to Google Earth, We can freely design and deploy a wide variety of open-source applications, including tools that visualize custom GIS data, live dashboards, sensor outputs, robotic controls, and more.


### The Problem

Every existing Liquid Galaxy rig runs on **Ubuntu 16.04**, which reached End of Life in 2021 — meaning every installation has been running without OS security patches ever since.

This project is a from-scratch installer that deploys the full Liquid Galaxy stack — Google Earth, ViewSync panorama sync, the `lg-*` toolset, the web control interface — on **Ubuntu 24.04 / 26.04 LTS**, rebuilding every piece of OS glue that broke along the way: display manager, init system, networking, and firewall.

---

## System Architecture

### Master / Slave Distributed System

Liquid Galaxy operates as a **master/slave cluster** where one machine (always `lg1`) coordinates all the others.

### How the Panorama Works

1. **The master (lg1)** runs Google Earth Pro and accepts input from a SpaceNavigator 3D joystick or mouse.
2. **Google Earth continuously broadcasts its camera state** via UDP on port **45678** (the ViewSync protocol). The camera state packet contains:
   - Latitude and Longitude (geographic position)
   - Altitude (height above the ground)
   - Heading (compass direction, 0–360°)
   - Tilt (camera angle up/down from vertical)
   - Roll (camera rotation around the line of sight)
3. **Each slave machine** receives this UDP packet and renders Google Earth at the same position, but with a fixed angular offset applied. The offset is defined per-slave in `myplaces.kml`.
4. **Result:** each screen shows an adjacent section of the panorama. Together they form one continuous wide-angle view.

### Network Topology

All machines are connected on a private subnet. The third octet of the IP address is the **cluster identifier** (octet), chosen to be unique per installation:

```
10.42.<OCTET>.1   → lg1 (master)
10.42.<OCTET>.2   → lg2
10.42.<OCTET>.3   → lg3
...
10.42.<OCTET>.7   → lg7
```

The subnet mask is `/24`, so the **full cluster** lives on `10.42.<OCTET>.0/24`.

### Key Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 45678 | UDP | **ViewSync**  camera state broadcast from master to slaves |
| 22 | TCP | **SSH**  master-to-slave command execution and file sync |
| 3128 | TCP | **Squid proxy**  Google Earth tile caching |

```
ubuntu-lts-support-gsoc2026/
├── install.sh              # Phase 1 — interactive setup
├── install-phase-two.sh    # Phase 2 — runs after reboot
├── precheck.sh             # OS / user validation
├── lib/                    # network, display, packages, google_earth, ssh
├── earth/                  # Earth launch scripts & KML templates
├── gnu_linux/              # Files deployed to /etc, /home/lg, /usr
└── php-interface/          # Web control panel (master only)
```

---

## 📸 Screenshots

<div align="center">
<table>
  <tr>
    <td align="center">
      <img src="docs\imgs\lg-earth.png" alt="Download & extract"/><br/>
    </td>
   </tr>
   <tr>
    <td align="center">
      <img src="docs\imgs\lg-egypt-1.png" alt="Download & extract"/><br/>
    </td>
   </tr>
   <tr>
    <td align="center">
      <img src="docs\imgs\lg-egypt-2.png" alt="Download & extract"/><br/>
    </td>
   </tr>
   <tr>
    <td align="center">
      <img src="docs\imgs\lg-tour-eiffel.png" alt="Download & extract"/><br/>
    </td>
   </tr>
</table>
</div>

Please, Check [Demo Video](https://youtu.be/FQ3C5q1QJJU?t=2029)

---

## 🚀 Getting Started

### Requirements
- Clean **Ubuntu 24.04 / 26.04 LTS**, 64-bit, on every node
- A local user `lg` with home directory `/home/lg`
- Installer unpacked directly into `/home/lg/liquid-galaxy-ubuntu-lts-support`
- All nodes on the same LAN, with internet access

### Install the Master (`lg1`) first

```bash
cd ~/liquid-galaxy-ubuntu-lts-support
chmod +x install.sh
./install.sh
```
Enter machine id `1`, total machine count, and a shared **octet** (cluster number). Choose **lightdm** when prompted. The machine reboots twice on its own — don't touch it in between. **Save the printed IP address.**

### Install each Slave

```bash
./install.sh
```
Enter its machine id (`2`, `3`, …), the master's IP and password, and the **same** total machine count and octet used on the master.

> [!IMPORTANT]
> **Total machine count and octet must match exactly on every node** — a mismatch breaks frame ordering and cluster sync.

📄 Full step-by-step guide: **[`docs/installation-guide.pdf`](docs/installation-guide.pdf)**

---

## 🛠️ Key Scripts

| Script | Description |
|--------|-------------|
| [`install.sh`](install.sh) | Interactive setup — role, packages, Google Earth, display stack switch |
| [`install-phase-two.sh`](install-phase-two.sh) | Unattended finish — network, firewall, SSH, autostart, self-destructs after run |
| [`lib/ssh.sh`](lib/ssh.sh) | Generates/distributes SSH keys master → slaves for passwordless control |
| [`lib/google_earth.sh`](lib/google_earth.sh) | Adds Google's signed APT repo, installs Earth Pro |
| [`lib/network.sh`](lib/network.sh) | Detects default route, interface, and MAC address |

---

## 🐞 Known Issues & Future Work

- No `clean.sh` rollback script — a failed install currently requires reinstalling the OS
- Logo send/clear on the web interface needs `lg-relaunch` to refresh reliably
- Squid tile-caching config under review for compatibility with the latest Google Earth
- Decision pending: migrate firewall fully to `nftables`

---

## 👨‍💻 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch and open a Pull Request

---

## 📜 License

This project is developed as part of **Google Summer of Code 2026** under the **Liquid Galaxy LAB** organization.

---

