---
title: Welcome to My Homelab
layout: page
description: The story behind my homelab project
showToc: true
menu:
  main:
    name: Homelab
    weight: 20
    params:
      icon: flask
---
## Introduction

My homelab journey began in 2013 with a humble Raspberry Pi, the very first model. I was needing a cheap machine for my first step into the world of Linux. It helped me a lot to dive into this technology and served me as a basic NAS, thank you Vezpibox (shitty name, I know) 

In 2015, I upgraded to a Raspberry Pi 2, seeking better performance to run multiple applications like XBMC (the old Kodi's name), CouchPotato, SickBeard, you name it...

By 2018, the need for more RAM led me to a Raspberry Pi 3, allowing me to run even more applications. My 3 little machines were running happily together, in a quite ordered mess.

Finally, in 2019, my new job made me discover the virtualization, with virtual machines and above all Docker. I wanted to try that at home, I took a significant step forward with a compact yet powerful headless PC that laid the foundation of my homelab.

---
## Why a Homelab ?

I wanted my own playground, a space where breaking things was not just okay, but encouraged. It’s the best way to learn how to fix them and, more importantly, to really understand how they work.

My single server was great, but testing anything risky on it became a problem. It was running critical services like home automation and DNS, and believe me, having no lights or internet is a major incident in my household. The server had become indispensable. When it was down, everything was down. Not so fun anymore.

The first big challenge I set for myself was building a Kubernetes cluster. Sure, I could run one on a single node, but what’s the point of a cluster with only one node? You could argue that running Kubernetes to control my shutters is overkill, and you’d be right. But that wasn’t the point.

I also wanted to spawn new virtual machines at will, rebuild them from scratch, and apply Infrastructure as Code principles. I could have done all of that in the cloud, but I wanted full control.

Initially, my goal was to provide high availability for my existing services. One server wasn’t enough. So, I wanted a second node. But in most HA setups, three nodes are the sweet spot. And just like that, I was on my way to building what would become my homelab.

---
## Shaping the Lab

First, I needed to define what my homelab was actually supposed to do. I wanted it to host my existing services reliably, but that wasn’t enough, I wanted a true playground, capable of simulating a more complex enterprise environment.
### Blueprint

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
- **Temperature**: I’m not gonna lie, I forgot about it.. Mini PCs don’t generate much heat, but network gear? That’s a different story. Lesson learned.

---
## Infrastructure Overview

Let’s break down the components that make up my homelab.
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

Here is the layout of my nodes:

| **Node**  | **Vertex**              | **Apex**                | **Zenith**               |
| --------- | ----------------------- | ----------------------- | ------------------------ |
| **Model** | ASRock DeskMini A300    | Minisforum HM50         | T-bao MN57               |
| **CPU**   | AMD Ryzen 3 2200G 4C/4T | AMD Ryzen 5 4500U 6C/6T | AMD Ryzen 7 5700U 8C/16T |
| **TDP**   | 65W                     | 15W                     | 15W                      |
| **RAM**   | 16GB                    | 16GB                    | 32GB                     |
| **NIC**   | 1Gbps (+ 2.5Gbps)       | 1Gbps + 2.5Gbps         | 1Gbps + 2.5Gbps          |
| **M.2**   | 2                       | 1                       | 1                        |
| **2,5"**  | 2                       | 2                       | 1                        |

Each node follows the same disk layout: a 256GB SSD in the 2.5" bay for the operating system and a 1TB NVMe drive for data storage.
### Network

For the network, I had two main objectives: implement VLANs for network segmentation and manage my firewall for more granular control. Since my nodes were equipped with 2.5Gbps NICs, I needed switches that could handle those speeds, and a few Power over Ethernet (PoE) ports for my Zigbee antenna and what could come after.

Initially, I was drawn to MikroTik hardware, great for learning, but their switch layouts didn’t quite align with my setup. On the other hand, Ubiquiti's UniFi line was the easy route with their with a sleek UI and impressive hardware aesthetics.

For the router, I opted against the UniFi gateway. I wanted something more customizable, something I could get my hands dirty with. After some research, I settled on OPNsense over pfSense, it was said to be a bit more beginner-friendly, and so far, I haven’t regretted it.

Here is the final network setup:
- **Router:** OPNsense running on a fanless Topton box with an Intel N100, 16GB RAM, and 4x 2.5Gbps ports.
- **Switch:** [UniFi Switch Lite 16 PoE](https://eu.store.ui.com/eu/en/category/switching-utility/products/usw-lite-16-poe), 8x 1Gbps PoE ports and 8x non-PoE ports.
- **Switch:** [UniFi Flex Mini 2.5G](https://eu.store.ui.com/eu/en/category/switching-utility/products/usw-flex-2-5g-5), 5x 2.5Gbps ports, with one PoE-in port.
- **Access Point:** [UniFi U7 Pro Wall](https://eu.store.ui.com/eu/en/category/all-wifi/products/u7-pro-wall), Wi-Fi 7, 2.5Gbps PoE+ in.
### Cooling

I quickly learned that my network gear was turning my closet into a mini furnace. Fortunately, I started the build in December, so the heat wasn’t too noticeable, but come summer, it was bound to become a real problem.

Options were limited, there was no way I was going to convince my wife that our servers needed a cooling system. Plus, it had to be silent. Not an easy combo.

The best solution I came up with was to drill two 40mm holes above the kitchen cabinet. I ran PVC pipes through the wall and installed two small fans, each cushioned with foam to minimize vibrations and keep noise down.

Inside the rack, I also added two 80mm fans to help with airflow. To keep everything quiet, I hooked up a PWM controller to regulate fan speeds, striking a balance between airflow and silence.
### Photos

Here what is look like

![homelab-rack-legend.png](img/homelab-rack-legend.png)
![homelab-enclore-open-closed.png](img/homelab-enclore-open-closed.png)

---
## Software Stack

With the hardware foundation set, the next step was to decide what software would orchestrate everything, the real engine behind every experiment, deployment, and learning opportunity.
### Hypervisor

At the core of my setup is a 3-node Proxmox VE 8 cluster, a KVM-based hypervisor that also supports LXC containers. Built on Debian, it provides essential features like live migration, HA, and seamless Ceph integration right out of the box.

For now, I’m primarily running just one VM and one LXC container. The VM is essentially a clone of my old physical server, hosting most of my applications as Docker containers. The LXC container serves as a simple jump server.
### Network

The objective for the network was to implement VLANs and manage the firewall rules myself. I'm running OPNsense on a dedicated fanless box, relegating my ISP router in bridge mode.

The brain
My entire home network is handl


by a couple of UniFi switches, managed by a self-hosted UniFi controller. This allows me to simply configure my L2 network on a sleek and simplified UI.

For the router and firewall, I wanted more control, I've chosen to go with OPNsense. As it replaced my ISP router, it serves as DHCP and DNS server. Initially I wanted to implement VLANs, to learn more on how to work with them and toy with firewalling. 
OPNsense offers the possibility to add plugins, 

OPNsense is capable 
VLAN
DNS
DHCP
VPN

| Description | ID   | Network      | Mask | Gateway      | Comments                     |
| ----------- | ---- | ------------ | ---- | ------------ | ---------------------------- |
| User        | 13   | 192.168.13.0 | 24   | 192.168.13.1 | Home network                 |
| IoT         | 37   | 192.168.37.0 | 24   | 192.168.37.1 | IoT and untrusted equipments |
| DMZ         | 55   | 192.168.55.0 | 24   | 192.168.55.1 | Internet facing              |
| Lab         | 66   | 192.168.66.0 | 24   | 192.168.66.1 | Lab network, trusted         |
| Heartbeat   | 77   | 192.168.77.0 | 24   |              | Proxmox cluster heartbeat    |
| Mgmt        | 88   | 192.168.88.0 | 24   | 192.168.88.1 | Management                   |
| Ceph        | 99   | 192.168.99.0 | 24   |              | Ceph                         |
| VPN         | 1337 | 10.13.37.0   | 24   | 10.13.37.1   | Wireguard network            |


### Storage


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

---

If you're curious about any part of the stack or want to know how I built something specific, feel free to check the related blog posts!

