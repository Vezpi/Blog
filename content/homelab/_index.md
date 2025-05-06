---
title: "My Homelab"
layout: "page"
description: "An overview of the hardware, software, and projects powering my personal homelab."
showToc: true
---

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

