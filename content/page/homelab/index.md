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
want to spawn VM, build kubernetes cluster
evolution of my setup
experiment
privacy
experience
## Shaping the Lab
### Specifications
what I want to be able to do :
- host my current services
- simulate enterprise environment
- 3 nodes
- distributed storage
- network / vlan
### Constraints
- space
- noise
- power
- budget
## Infrastructure Overview
### Rack
### Servers
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

