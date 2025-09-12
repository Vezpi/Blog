---
slug: proxmox-cluster-networking-sdn
title: Simplifying VLAN Management in Proxmox VE with SDN
description: Learn how to centralize VLAN configuration in Proxmox VE using SDN zones and VNets, making VM networking easier and more consistent.
date: 2025-09-12
draft: false
tags:
  - proxmox
categories:
  - homelab
---

## Intro

When I first built my **Proxmox VE 8** cluster, networking wasn’t my main concern. I just wanted to replace an old physical server quickly, so I gave each of my three nodes the same basic config, created the cluster, and started running VMs:
![Configuration réseau d’un nœud Proxmox](img/proxmox-node-network-configuration.png)

That worked fine for a while. But as I plan to virtualize my **OPNsense** router, I need something more structured and consistent. This is where Proxmox **S**oftware-**D**efined **N**etworking (SDN) feature comes in.

---
## My Homelab Network

By default, every Proxmox node comes with its own local zone, called `localnetwork`, which contains the default Linux bridge (`vmbr0`) as a VNet:
![Proxmox default `localnetwork` zones](img/proxmox-default-localnetwork-zone.png)

That’s fine for isolated setups, but at the cluster level nothing is coordinated.

What I want is simple: declare the VLANs I already use in my network, so I can attach VMs to them easily from any node.

Here’s the list of VLANs I use today:

| Name      | ID   | Purpose                      |
| --------- | ---- | ---------------------------- |
| Mgmt      | 1    | Management                   |
| User      | 13   | Home network                 |
| IoT       | 37   | IoT and untrusted equipments |
| DMZ       | 55   | Internet facing              |
| Lab       | 66   | Lab network                  |
| Heartbeat | 77   | Proxmox cluster heartbeat    |
| Ceph      | 99   | Ceph storage                 |
| VPN       | 1337 | Wireguard network            |

---
## Proxmox SDN Overview

Proxmox Software-Defined Networking makes it possible to define cluster-wide virtual zones and networks. Instead of repeating VLAN configs on every node, SDN gives you a central view and ensures consistency.

Under the hood, Proxmox mostly uses standard Linux networking, avoiding extra dependencies and keeping things stable.

SDN configurations are stored in `/etc/pve/sdn`, which is replicated across the cluster. Changes are applied atomically (you prepare them, then hit `Apply` once), making rollouts safer.

### Zones

A **Zone** defines a separate networking domain. Zones can span specific nodes and contain **VNets**.

Proxmox supports several zone types:
- **Simple**: Isolated Bridge. A simple layer 3 routing bridge (NAT)
- **VLAN**: Virtual LANs are the classic method of subdividing a LAN
- **QinQ**: Stacked VLAN (IEEE 802.1ad)
- **VXLAN**: Layer 2 VXLAN network via a UDP tunnel
- **EVPN**: VXLAN with BGP to establish Layer 3 routing

Since my home network already relies on VLANs, I created a **VLAN Zone** named `homelan`, using `vmbr0` as the bridge and applying it cluster-wide:
![Create a VLAN zone in the Proxmox SDN](img/proxmox-create-vlan-zone-homelan.png)

### VNets

A **VNet** is a virtual network inside a zone. In a VLAN zone, each VNet corresponds to a specific VLAN ID.

I started by creating `vlan55` in the `homelan` zone for my DMZ network:
![Create a VNet for VLAN 55 in the homelan zone](img/proxmox-create-vlan-vnet-homelan.png)

Then I added VNets for most of my VLANs, since I plan to attach them to an OPNsense VM:
![All my VLANs created in the Proxmox SDN](img/proxmox-sdn-all-vlan-homelan.png)

Finally, I applied the configuration in **Datacenter → SDN**:
![Application de la configuration SDN dans Proxmox](img/proxmox-apply-sdn-homelan-configuration.png)

---
## Test the Network Configuration

In a old VM which I don't use anymore, I replace the current `vmbr0` with VLAN tag 66 to my new VNet `vlan66`:
![Change the network bridge in a VM](img/proxmox-change-vm-nic-vlan-vnet.png)

After starting it, the VM gets an IP from the DHCP on OPNsense on that VLAN, which sounds good. I also try to ping another machine and it works:
![Ping another machine in the same VLAN](img/proxmox-console-ping-vm-vlan-66.png)

---
## Update Cloud-Init Template and Terraform

To go further, I update the bridge used in my **cloud-init** template, which I detailed the creation in that [post]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}). Pretty much the same thing I've done with the VM, I replace the current `vmbr0` with VLAN tag 66 with my new VNet `vlan66`.

I also update the **Terrafom** code to take this change into account:
![Mise à jour du code Terraform pour vlan66](img/terraform-code-update-vlan66.png)

I quicky check if I don't have regression and can still deploy a VM with Terraform:
```bash
terraform apply -var 'vm_name=vm-test-vnet'
```
```plaintext
data.proxmox_virtual_environment_vms.template: Reading...
data.proxmox_virtual_environment_vms.template: Read complete after 0s [id=23b17aea-d9f7-4f28-847f-41bb013262ea]
[...]
Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + vm_ip = (known after apply)

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

proxmox_virtual_environment_file.cloud_config: Creating...
proxmox_virtual_environment_file.cloud_config: Creation complete after 1s [id=local:snippets/vm.cloud-config.yaml]
proxmox_virtual_environment_vm.vm: Creating...
proxmox_virtual_environment_vm.vm: Still creating... [10s elapsed]
[...]
proxmox_virtual_environment_vm.vm: Still creating... [3m0s elapsed]
proxmox_virtual_environment_vm.vm: Creation complete after 3m9s [id=119]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

vm_ip = "192.168.66.181"
```

The VM is deploying without any issue, everything is OK:
![VM déployée par Terraform sur vlan66](img/proxmox-terraform-test-deploy-vlan66.png)

---
## Conclusion

Setting up Proxmox SDN with a **VLAN zone** turned out to be straightforward and very useful. Instead of tagging VLANs manually per VM, I now just pick the right VNet, and everything stays consistent across the cluster.

| Step              | Before SDN                      | After SDN                      |
| ----------------- | ------------------------------- | ------------------------------ |
| Attach VM to VLAN | `vmbr0` + set VLAN tag manually | Select the right VNet directly |
| VLANs on nodes    | Repeated config per node        | Centralized in cluster SDN     |
| IP management     | Manual or DHCP only             | Optional IPAM via SDN subnets  |

This prepares my cluster to host my **OPNsense router**, and it also sets the stage for future experiments, like trying out VXLAN overlays or EVPN with BGP.

See you next time for the next step!


