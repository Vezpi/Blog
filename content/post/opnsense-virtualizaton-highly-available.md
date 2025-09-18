---
slug: opnsense-virtualizaton-highly-available
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - proxmox
categories:
  - homelab
---
## Intro

I recently encountered my first real problem, my physical OPNsense box crashed because of a kernel panic, I've detailed what happened in that [post]({{< ref "post/10-opnsense-crash-disk-panic" >}}).

After this event, I came up with an idea to enhance the stability of the lab: **Virtualize OPNsense**.

The idea is pretty simple on paper, create an OPNsense VM on the **Proxmox** cluster and replace the current physical box by this VM. The challenge would be to have both the LAN and the WAN on the same physical link, involving true network segregation.

Having only one OPNsense VM would not solve my problem. I want to implement High Availability, the bare minimum would be to have 2 OPNsense instances, as active/passive.

---
## Current Setup

Currently, I have my ISB box, a *Freebox*, in bridge mode which is connected to the port `igc0` of my OPNsense box, the **WAN**. On `igc1`, my **LAN** is connected to my main switch on a trunk port with the VLAN1 as native, my management network.

Connected to that switch are my 3 Proxmox nodes, on trunk port as well with the same native VLAN. Each of my Proxmox nodes have 2 NICs, but the other is dedicated for the Ceph storage network, on a dedicated 2.5GB switch.

The layout changed a little since the OPNsense crash, I dropped the LACP link which was not giving any value:
![homelan-current-physical-layout.png](img/homelan-current-physical-layout.png)

---
## Target Layout

As I said in the intro, the plan is simple, replace the OPNsense box by a couple of VM in Proxmox. Basically, I will plug my ISB box directly to the main switch, but the native VLAN will have to change, I will create a VLAN dedicated for my WAN communication.

The real challenge will be located on the Proxmox networking, with only one NIC to support communication of LAN, WAN and even cluster, all of that on a 1Gbps port, I'm not sure of the outcome.

### Proxmox Networking

My Proxmox networking was quite dumb until really recently. Initially I only configured the network on each nodes. In that [article]({{< ref "post/11-proxmox-cluster-networking-sdn" >}}), I configured my VLANs in the Proxmox SDN.

Additionally, I have to add extra VLANs for this project, one for the WAN and the other for pfSync.

## Proof of Concept

Before rushing into a migration, I want to experiment the high availability setup for OPNsense. The idea would be to:
1. Add some VLANs on the Proxmox SDN
2. Create Fake ISP box
3. Build two OPNsense VMs
4. Configure the high availabilty
5. Create another client VM
6. Shutdown the active OPNsense node
7. See what happen!

### Add VLANs in the Homelab

For this experiment, I add extra VLANs:
- 101: POC WAN 
- 102: POC LAN
- 103: POC pfSync

In the Proxmox UI, I navigate to `Datacenter` > `SDN` > `VNets` and I click `Create`:
![Create POC VLANs in the Proxmox SDN](img/proxmox-sdn-create-poc-vlans.png)

Once the 3 new VLAN have been created, I apply the configuration.

### Create Fake ISP Box VM


![Pasted_image_20250917205522.png](img/Pasted_image_20250917205522.png)

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.101.0.254/24
    enp6s19:
      dhcp4: true
```

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

sudo apt install iptables-persistent -y
sudo netfilter-persistent save

Install dnsmasq

```bash
sudo apt install dnsmasq -y
```

```bash
sudo systemctl restart dnsmasq
```