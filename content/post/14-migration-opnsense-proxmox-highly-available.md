---
slug:
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - high-availability
  - proxmox
categories:
---

## Intro

In my previous [post]({{< ref "post/12-opnsense-virtualization-highly-available" >}}), I've set up a PoC to validate the possibility to create a cluster of 2 **OPNsense** VMs in **Proxmox VE** and make the firewall highly available.

This time, I will cover the creation of my future OPNsense cluster from scratch, plan the cut over and finally migrate from my current physical box.

---
## Build the Foundation

For the real thing, I'll have to connect the WAN, coming from my ISP box, to my main switch. For that I have to add a VLAN to transport this flow to my Proxmox nodes.

### UniFi

The first thing I do is to configure my layer 2 network which is managed by UniFi. There I need to create two VLANs:
- *WAN* (20): transport the WAN between my ISP box and my Proxmox nodes.
- *pfSync* (44), communication between my OPNsense nodes.

In the UniFi controller, in `Settings` > `Networks`, I add a `New Virtual Network`. I name it `WAN` and give it the VLAN ID 20:
![unifi-add-vlan-for-wan.png](img/unifi-add-vlan-for-wan.png)

I do the same thing again for the `pfSync` VLAN with the VLAN ID 44.

I will plug my ISP box on the port 15 of my switch, which is disabled for now. I set it as active, set the native VLAN on the newly created one `WAN (20)` and disable trunking:
![unifi-enable-port-wan-vlan.png](img/unifi-enable-port-wan-vlan.png)

Once this setting applied, I make sure that only the ports where are connected my Proxmox nodes propagate these VLAN on their trunk. 

We are done with UniFi configuration.

### Proxmox SDN

Now that the VLAN can reach my nodes, I want to handle it in the Proxmox SDN.

In `Datacenter` > `SDN` > `VNets`, I create a new VNet, name it `vlan20` to follow my own naming convention, give it the *WAN* alias and use the tag (ID) 20:
![proxmox-sdn-new-vnet-wan.png](img/proxmox-sdn-new-vnet-wan.png)

I also create the `vlan44` for the *pfSync* VLAN, then I apply this configuration and we are done with the SDN.

---
## Create the VMs

Now that the VLAN configuration is done, I can start buiding the virtual machines on Proxmox.

The first VM is named `cerbere-head1` (I didn't tell you? My current firewall is named `cerbere`, it makes even more sense now!) Here are the settings:
- OS type: Linux
- Machine type: `q35`
- BIOS: `OVMF (UEFI)`
- Disk: 20 GiB on Ceph storage
- CPU/RAM: 2 vCPU, 4 GiB RAM
- NICs:
	1. `vmbr0` (*Mgmt*)
	2. `vlan20` (*WAN*)
	3. `vlan13` *(User)*
	4. `vlan37` *(IoT)*
	5. `vlan44` *(pfSync)*
	6. `vlan55` *(DMZ)*
	7. `vlan66` *(Lab)*
![proxmox-cerbere-vm-settings.png](img/proxmox-cerbere-vm-settings.png)

ℹ️ Now I clone that VM to create `cerbere-head2`, then I proceed with OPNsense installation. I don't want to go into much details about OPNsense installation, I already documented it in the previous [post]({{< ref "post/12-opnsense-virtualization-highly-available" >}}).

After the installation of both OPNsense instances, I give to each of them their IP in the *Mgmt* network:
- `cerbere-head1`: `192.168.88.2/24`
- `cerbere-head2`: `192.168.88.3/24`

While these routers are not managing the networks, I give them my current OPNsense routeur as gateway (`192.168.88.1`) to able to reach them from my PC in another VLAN.

---
## Configure OPNsense




## TODO

HA in proxmox
Make sure VM start at proxmox boot

## Switch

Configure DHCP on both instance
Enable DHCP
Change VIP
Replicate configuration
## Verify


Basic (dhcp, dns, internet)
Firewall
All sites
mDNS (chromecast)
VPN
TV

Vérifier tous les devices

DNS blocklist

Failover

Test proxmox full shutdown