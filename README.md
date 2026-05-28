# Ubuntu LTS Support for Liquid Galaxy 

## 1. What is Liquid Galaxy?

Liquid Galaxy is an open-source project, originally created by Google, that creates a synchronized panoramic display across multiple screens driven by multiple computers. It is most commonly used with **Google Earth Pro**, allowing users to experience immersive, wide-angle geographic visualizations.

Liquid Galaxy is not limited to Google Earth, We can freely design and deploy a wide variety of open-source applications, including tools that visualize custom GIS data, live dashboards, sensor outputs, robotic controls, and more.


### The Problem

Ubuntu 16.04 LTS reached End of Life in April 2021. Every Liquid Galaxy installation in the world has been running **without OS security** patches since then. 

---

## 2. System Architecture

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

---
