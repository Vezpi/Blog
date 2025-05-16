---
title: Welcome to My Homelab
layout: page
description: The story behind my homelab project
showToc: true
menu:
  main:
    weight: 20
    params:
      icon: flask
---
## Introduction

My homelab journey began in 2013 with a humble Raspberry Pi, the very first model. I was needing a cheap machine for my first step into the world of Linux. It helped me a lot to dive into this technology and served me as a basic NAS, thank you Vezpibox (shitty name, I know) 

In 2015, I upgraded to a Raspberry Pi 2, seeking better performance to run multiple applications like XBMC (the old Kodi's name), CouchPotato, SickBeard, you name it...

By 2018, the need for more RAM led me to a Raspberry Pi 3, allowing me to run even more applications. My 3 little machines were running happily together, in a quite ordered mess.

Finally, in 2019, my new job made me discover the virtualization, with virtual machines and above all Docker. I wanted to try that at home, I took a significant step forward with a compact yet powerful headless PC that laid the foundation of my homelab.
## Why a Homelab ?

I wanted my own playground, a space where breaking things was not just okay, but encouraged. It’s the best way to learn how to fix them and, more importantly, to really understand how they work.

My single server was great, but testing anything risky on it became a problem. It was running critical services like home automation and DNS, and believe me, having no lights or internet is a major incident in my household. The server had become indispensable. When it was down, everything was down. Not so fun anymore.

The first big challenge I set for myself was building a Kubernetes cluster. Sure, I could run one on a single node, but what’s the point of a cluster with only one node? You could argue that running Kubernetes to control my shutters is overkill, and you’d be right. But that wasn’t the point.

I also wanted to spawn new virtual machines at will, rebuild them from scratch, and apply Infrastructure as Code principles. I could have done all of that in the cloud, but I wanted full control.

Initially, my goal was to provide high availability for my existing services. One server wasn’t enough. So, I wanted a second node. But in most HA setups, three nodes are the sweet spot. And just like that, I was on my way to building what would become my homelab.
## Shaping the Lab
### Blueprint

First, I needed to define what my homelab was actually supposed to do. I wanted it to host my existing services reliably, but that wasn’t enough, I wanted a true playground, capable of simulating a more complex enterprise environment.

That meant:
- **High Availability:** Three nodes to ensure that no single point of failure would bring everything down.
- **Distributed Storage:** Data redundancy across nodes, not just for uptime but also to learn how enterprise-grade storage systems work.
- **Network Segmentation:** Multiple VLANs to mimic real-world network topologies, isolate services, and practice advanced networking.

Basically, I wanted to build a tiny datacenter in a closet.
### Constraints

Of course, reality doesn’t always align with ambitions. Here’s what I was up against:
- **Space:** My lab needed to fit in a small, hidden service enclosure in the middle of my apartment. Not exactly a server room.
- **Noise:** Silence was crucial. This wasn’t going to be tucked away in a garage or basement, it was right in the middle of our living space.
- **Power Draw:** Running 24/7, the power consumption had to be kept in check. I couldn’t afford to triple my electric bill just to tinker with VMs.
- **Budget:** I wasn’t going to drop thousands on enterprise-grade hardware. The balance was finding reliable, second-hand gear that wouldn’t break the bank.
- Temperature: I’m not gonna lie, I forgot about it.. Mini PCs don’t generate much heat, but network gear? That’s a different story. Lesson learned.
## Infrastructure Overview
### Rack

What is a datacenter without a rack? Honestly, I didn’t think one would fit in my limited space, until I discovered the [DeskPi RackMate T1](https://deskpi.com/products/deskpi-rackmate-t1-2).

This beauty was the perfect match. The size was spot-on, the build quality impressive, and the modular design allowed me to add some extra accessories, like a power strip and shelves, to complete the setup.
### Servers

I already had one server that served as the cornerstone of my homelab, and I wanted to keep it. But it had two major drawbacks:
- **Single Network Interface:** I wanted at least two NICs for network segmentation and redundancy.
- **Aging Hardware:** It was over five years old, and its compatibility options were becoming limited.

For the missing NIC, I considered a USB adapter but then stumbled upon a better solution: using the internal M.2 port, originally meant for a WiFi module, to connect a 2.5Gbps adapter. It was a perfect fit.

Regarding hardware, my existing server was powered by an AM4 Ryzen 3 2200G with 16GB of RAM DDR4. To keep things consistent and simplify compatibility, I decided to stick with the AM4 socket for all nodes.

The specifications for the two additional nodes were clear: an AM4 socket for consistency, low power consumption, dual NICs with at least one 2.5Gbps, and sufficient storage options, at least one M.2 NVMe slot and a 2.5" drive bay. Since AM4 is somewhat dated, newer models were off the table, a good news for my budget, as I was able to buy second-hand mini PCs.

Here is the breakdown of my nodes:

| **Node**  | **Vertex**              | **Apex**                | **Zenith**               |
| --------- | ----------------------- | ----------------------- | ------------------------ |
| **Model** | ASRock DeskMini A300    | Minisforum HM50         | T-bao MN57               |
| **CPU**   | AMD Ryzen 3 2200G 4C/4T | AMD Ryzen 5 4500U 6C/6T | AMD Ryzen 7 5700U 8C/16T |
| **TDP**   | 65W                     | 15W                     | 15W                      |
| **RAM**   | 16GB                    | 16GB                    | 32GB                     |
| **NIC**   | 1Gbps (+ 2.5Gbps)       | 1Gbps + 2.5Gbps         | 1Gbps + 2.5Gbps          |
| **M.2**   | 2                       | 1                       | 1                        |
| **2,5"**  | 2                       | 2                       | 1                        |
### Network

### Cooling
### Photos
## Software Stack
### Hypervisor
### Network
### Application
#### Docker
#### Kubernetes
## Roadmap for my Lab
### Building my Homelab
- building the first proxmox node
- migrating from my headless PC to a VM
- building the second proxmox node with HDDs
- Install the rack
- Create the network
- Installating OPNsense
- Switching routing from my freebox to OPNsense
- Reconfigure my WiFi clients
- Build the third Proxmox node
- Externalize my HDDs
- Deploy VLAN
- Setup Proxmox Cluster
- Setup Ceph Storage
- Install fans
- Install ADguard Home along Unbound DNS
- Setup IPAM
- Install a bastion
### Let's Play
- Deploy a VM with Terraform
- Create a Terraform module
- Deploy Terraform infrastructure using Ansible
- Create a Blog





Welcome to my homelab — a space where I explore new technologies, break things on purpose, and learn by doing. What started as a few old machines has grown into a modest but powerful setup that I use for self-hosting, automation, testing infrastructure tools, and running personal projects.



## 1. Hardware

I currently run a 3-node cluster built with energy-efficient mini PCs and repurposed desktops. Here's a breakdown:

- **Node 1**: AMD Ryzen 4C/4T, 16GB RAM  
- **Node 2**: AMD Ryzen 6C/6T, 16GB RAM  
- **Node 3**: AMD Ryzen 8C/16T, 64GB RAM  
- **Storage**: Ceph-based distributed storage across all nodes  
- **Network**: 1Gbps LAN with 2.5Gbps NICs for Ceph replication traffic  
- **Rack**: Compact 10" rack with managed switch and PDU

## 2. Software

- **Proxmox VE**: Used for virtualization and clustering  
- **Ceph**: Distributed storage for VM disks  
- **Kubernetes (K3s)**: For orchestrating containerized apps  
- **Gitea**: Self-hosted Git with CI/CD via Gitea Actions  
- **OPNsense**: Firewall, VLANs, and DNS (with AdGuard + Unbound)  
- **Monitoring**: Grafana, Prometheus, Node Exporter

## 3. Projects

Some of the ongoing and past projects I've worked on:

- CI/CD automation using Gitea Actions  
- GitOps pipeline for Kubernetes using ArgoCD  
- Hugo-based personal blog hosted with Docker  
- Home automation with Zigbee2MQTT and Home Assistant  
- VPN and remote access via WireGuard  
- Infrastructure as Code with Terraform and Ansible

---

If you're curious about any part of the stack or want to know how I built something specific, feel free to check the related blog posts!

