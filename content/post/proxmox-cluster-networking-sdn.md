---
slug: proxmox-cluster-networking-sdn
title: Template
description:
date:
draft: true
tags:
  - proxmox
categories:
  - homelab
---

## Intro

When I created my **Proxmox VE 8** cluster, I didn't really pay attention to the cluster networking, I wanted to quickly deploy a VM to replace the physical server I was using. I only configured each of my 3 nodes with the same config, created the cluster and that's it:
![Proxmox node network configuration](img/proxmox-node-network-configuration.png)

As I want to use my cluster to host my router, I need to have proper network configured. To achieve that, I will use the Proxmox SDN functionality.

---
## My Homelab Network

By default, each node has its own zone, called `localnetwork`, with the Linux bridge `vmbr0` as VNet inside:

![Proxmox default localnetwork zones](img/proxmox-default-localnetwork-zone.png)

But at the cluster level, nothing is defined. I don't need something fancy, only to declare the VLANs in use in my network, to make it easier to connect VM onto them. here the list of the VLANs declared on my network:

| Name      | ID   | Purpose                      |
| --------- | ---- | ---------------------------- |
| Mgmt      | 1    | Management                   |
| User      | 13   | Home network                 |
| IoT       | 37   | IoT and untrusted equipments |
| DMZ       | 55   | Internet facing              |
| Lab       | 66   | Lab network, trusted         |
| Heartbeat | 77   | Proxmox cluster heartbeat    |
| Ceph      | 99   | Ceph                         |
| VPN       | 1337 | Wireguard network            |

## Proxmox networking with SDN

The **S**oftware-**D**efined **N**etwork (SDN) feature in Proxmox VE enables the creation of virtual zones and networks. This functionality simplifies advanced networking configurations and multitenancy setup.

The Proxmox VE Software-Defined Network implementation uses standard Linux networking as much as possible. The reason for this is that modern Linux networking provides almost all needs for a feature full SDN implementation and avoids adding external dependencies and reduces the overall amount of components that can break.

The Proxmox VE SDN configurations are located in `/etc/pve/sdn`, which is shared with all other cluster nodes. 

New changes are not immediately applied but recorded as pending first. You can then apply a set of different changes all at once in the main SDN overview panel on the web interface. This system allows to roll-out various changes as single atomic one.

The SDN tracks the rolled-out state through the _.running-config_ and _.version_ files located in `/etc/pve/sdn`.

### Zone

A zone defines a virtually separated network. Zones are restricted to specific nodes and assigned permissions, in order to restrict users to a certain zone and its contained VNets.

Different zone types can be used for separation:
- **Simple**: Isolated Bridge. A simple layer 3 routing bridge (NAT)
- **VLAN**: Virtual LANs are the classic method of subdividing a LAN
- **QinQ**: Stacked VLAN (IEEE 802.1ad)
- **VXLAN**: Layer 2 VXLAN network via a UDP tunnel
- **EVPN**: VXLAN with BGP to establish Layer 3 routing

My home network uses VLAN, naturally I create a VLAN zone which I name `homelan`, `vmbr0` for the bridge and I don't specify any node to select them all:
![Create a VLAN zone in the Proxmox SDN](img/proxmox-create-vlan-zone-homelan.png)

### VNet

VNet are virtual networks which are part of a zone, for a VLAN zone, this is corresponding to a VLAN ID, I create a first VNet `vlan55` in my new zone for my DMZ VLAN with the tag 55:
![Create a VNet for the VLAN 55 in the homelan zone](img/proxmox-create-vlan-vnet-homelan.png)

I create as VNets all the VLAN which would need to be attached to a VM. My plans are to create an OPNsense in a VM, that's why I add them almost them all:
![All my VLANs created in the Proxmox SDN](img/proxmox-sdn-all-vlan-homelan.png)

Once everything is ready, I can apply the SDN configuration. In `Datacenter` > `SDN`, I click on the `Apply` button, after a few seconds, the new zones appear:
![Apply SDN configuration in Proxmox](img/proxmox-apply-sdn-homelan-configuration.png)

## Test the network configuration

In a old VM which I don't use anymore, I replace the current `vmbr0` with VLAN tag 66 to my new VNet `vlan66`:
![Change the network bridge in a VM](img/proxmox-change-vm-nic-vlan-vnet.png)

After starting it, the VM gets an IP from the DHCP on OPNsense on that VLAN, which sounds good. I also try to ping another machine:
![proxmox-console-ping-vm-vlan-66.png](img/proxmox-console-ping-vm-vlan-66.png)