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

Initially I thought about restoring my current OPNsense config on the VM. But as I didn't document the configuration process the first time, I take the opportunity to start over.

### System

The system configuration is done on both firewalls. In `System` > `Settings` > `General`, I configure the basic:
- **Hostname**: `cerbere-head1` (`cerbere-head2` for the second one).
- **Domain**: `mgmt.vezpi.com`.
- **Time zone**: `Europe/Paris`.
- **Language**: `English`.
- **Theme**: `opnsense-dark`.
- **Prefer IPv4 over IPv6**: tick the box to prefer IPv4.

Then, in `System` > `Access` > `Users`, I create a new user, I don't like sticking with the defaults `root`. I add this user in the `admins`  group, while removing `root` from it.

In `System` > `Settings` > `Administration`, I change several things:
- **TCP port**: from `443` to `4443`, to free port 443 for the reverse proxy coming next.
-  **Alternate Hostnames**: `cerbere.vezpi.com` which will be the URL to reach the firewall by the reverse proxy.
- **Access log**: enabled.
- **Secure Shell Server**: enabled.
- **Authentication Method:** permit password login (no `root` login).
- **Sudo**: `No password`.
Once I click `Save`, I follow the link given to reach the WebGUI on port `4443`.

Time for updates, in System > Firmware > Status, I click on `Check for updates`.  An update is available, I close the banner, head to the bottom and click on `Update`. I'm warned that this update requires a reboot.

Once updated and rebooted, I go to `System` > `Firmware` > `Plugins`, I tick the box to show community plugins. For now I only install the QEMU guest agent, `os-qemu-guest-agent`, to allow communication between the VM and the Proxmox host. 

This requires a shutdown. On Proxmox, I enable the `QEMU Guest Agent` in the VM options:
![proxmox-opnsense-enable-qemu-guest-agent.png](img/proxmox-opnsense-enable-qemu-guest-agent.png)

Finally I restart the VM. Once started, from the Proxmox WebGUI, I can see the IPs of the VM which confirms the guest agent is working.
### Interfaces

On both firewalls, I assign the remaining NICs to new interfaces adding a description. The VMs have 7 interfaces, I carefully compare the MAC addresses to not mix them up:
![opnsense-assign-interfaces.png](img/opnsense-assign-interfaces.png)