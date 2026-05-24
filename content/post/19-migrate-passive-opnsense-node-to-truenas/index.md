---
slug: migrate-passive-opnsense-node-to-truenas
title: Migrate my Passive OPNsense HA Node to TrueNAS
description: I migrated my passive OPNsense HA VM from Proxmox to TrueNAS to keep routing and firewalling available even when my Proxmox cluster is down.
date: 2026-05-24
draft: true
tags:
  - opnsense
  - truenas
  - proxmox
categories:
  - homelab
---
## Intro

My homelab network is handled by an OPNsense cluster composed of two VM nodes. Both of these VMs are running inside my Proxmox VE cluster.

This setup works fine most of the time. The issue is more about the rare cases where the Proxmox cluster itself is down. When that happens, both OPNsense nodes are unavailable at the same time, which means I do not have any router left, so no network at all.

Recently, I installed a TrueNAS server in the lab. You can find the infos in that [post]({{< ref "post/18-create-nas-server-with-truenas" >}}). It is mainly here to act as a NAS, but it could also host virtual machines. That give me a good opportunity to improve the resilience of my network without changing the whole design.

💡 The idea is simple: keep the active OPNsense node on Proxmox, but move the passive node to TrueNAS.

This way, if the Proxmox cluster goes down, the passive OPNsense node can still take over and keep the network alive.

---
## Prepare the OPNsense Nodes

Before moving anything, I want to make sure the OPNsense VMs could run with less memory.

The TrueNAS server does not have as much RAM available as the Proxmox cluster, so the first step is to reduce the memory allocation of the OPNsense nodes to the minimum.

I start with the passive node, `cerbere-head2`:

- Shut down the passive node
- Reduce its memory allocation from 4 to 2GB
- Restart it
- Verify the cluster health
- Swap the service to the passive node
- Run network checks

Then I repeat the same operation on the active node, `cerbere-head1`.

Doing it one node at a time allow me to keep the HA cluster healthy while validating that the reduced memory allocation is still enough for my setup.

---
## Prepare the TrueNAS Network

The most important part of this migration is not the disk export or the VM creation. It is the network.

An OPNsense VM is not a simple server with one management interface. It needs access to several networks, including management, WAN, user networks, IoT, pfSync, DMZ and lab networks.

On the TrueNAS side, I start from `System` > `Network` and add VLAN interfaces.

The first one is the User VLAN:

- Type: `VLAN`
- Name: `vlan13`
- Description: `User`
- Parent interface: `enp1s0`
- VLAN tag: `13`

![Creating the User VLAN interface in TrueNAS](images/truenas-create-new-vlan-interface.png)

I then add the other VLANs in the same way.

TrueNAS does not apply network changes directly. It gives the option to test the changes first, with a short validation window. If the configuration is not confirmed in time, it rolls back automatically.

This is really convenient when changing the network configuration of the machine you are currently connected to.

![Confirming the VLAN interfaces before applying the network changes](images/truenas-network-confirm-add-vlans.png)

For the management network, I created a bridge called `br1`.

This bridge holds the TrueNAS management IP configuration instead of the physical interface `enp1s0`, because it also needs to be shared with the OPNsense VM.

![Creating the management bridge for TrueNAS and the OPNsense VM](images/truenas-network-mgmt-bridge.png)

After that, I remove the IP configuration from the physical interface and keep it on the bridge.

![Network configuration before applying the bridge changes](images/truenas-network-changes-before-apply.png)

I initially tried to use DHCP for the management bridge after updating the MAC address in Dnsmasq, but I finally decided to keep a static IP address for TrueNAS. After some network changes, DHCP gave another address from the pool, so static addressing was the safer and simpler option for this server.

For the OPNsense VM, I create a bridge for each VLAN. For example, `br13` uses `vlan13`, I also move the description, like `User`, from the VLAN interface to the bridge for clarity.

The final TrueNAS network configuration:

![Creating one bridge per VLAN for the OPNsense VM](images/truenas-network-bridges-for-vlan.png)

---
## Create a Temporary Export Dataset

To move the passive OPNsense VM disk from Proxmox to TrueNAS, I first need a place to export the disk image.

In TrueNAS, I create a dataset named `storage/vm/disk`, then create a NFS share from it.

In the advanced options of the NFS share, I configured:

- Maproot user: `root`
- Authorized hosts:
  - `192.168.88.21`
  - `192.168.88.22`
  - `192.168.88.23`

These are the Proxmox VE nodes allowed to mount the share.

I don't manually create a zvol at that point. The VM creation process in TrueNAS handle the disk import and conversion.

## Export the VM Disk from Proxmox

From the Proxmox VE web interface, I locate the node hosting the passive OPNsense VM `cerbere-head2`, it is running on `Zenith`.

I log into that Proxmox node over SSH and mount the NFS share from TrueNAS:

```bash
mount granite.mgmt.vezpi.com:/mnt/storage/vm/disk /mnt
```

Then I shut down the VM from the Proxmox VE interface. I don't shut it down from inside OPNsense because the VM has HA enabled.

Once the VM is stopped, I export the main disk to qcow2. I don't export the EFI disk.

```bash
qemu-img convert -f raw -O qcow2 -p \
         rbd:ceph-workload/vm-123-disk-1 \
         /mnt/cerbere-head2.qcow2
```

The conversion took about one minute for a 20 GB disk.

At this point, the passive OPNsense disk is available on TrueNAS and ready to be imported into a new VM.

## Recreate the OPNsense VM in TrueNAS

The next step is to recreate the passive OPNsense VM in TrueNAS with parameters matching the original VM as closely as possible.

From the TrueNAS web interface, I go to the `Virtual Machines` section.

![Opening the Virtual Machines section in TrueNAS](images/truenas-vm-menu.png)

I create a new VM with these settings.

For the operating system:

- Guest Operating System: `FreeBSD`
- Name: `cerberehead2`
- System Clock: `Local`
- Boot Method: `UEFI`
- Enable Secure Boot: disabled
- Enable Trusted Platform Module: disabled
- Shutdown Timeout: `90`
- Start on Boot: enabled
- Enable Display VNC: disabled

The VM name does not use dashes because TrueNAS do not allow them there.

For CPU and memory:

- Virtual CPUs: `1`
- Cores: `2`
- Threads: `1`
- CPU Mode: `Custom`
- CPU Model: `qemu64`
- Memory Size: `2 GiB`

For the disk:

- Create new disk image
- Import Image: enabled
- Image source: `/mnt/storage/vm/files/cerbere-head2.qcow2`
- Disk Type: `VirtIO`
- Storage Location: `storage/vm`
- Size: `20 GiB`

For the first network interface:

- Adapter Type: `VirtIO`
- MAC Address: keep the proposed one
- Attach NIC: `br1: Mgmt`

I skip installation media and GPU configuration, then confirm the summary.

![Summary before creating the OPNsense VM in TrueNAS](images/truenas-vm-create-new-summary.png)

After confirmation, TrueNAS convert the imported qcow2 image into a zvol.

![TrueNAS converting the imported disk image into a zvol](images/truenas-vm-disk-image-conversion.png)

Once the VM is created, I open the VM details and add the remaining NICs.

![Accessing the VM devices in TrueNAS](images/truenas-vm-details.png)

For each additional NIC, I used VirtIO as the adapter type and attach it to the corresponding bridge.

For the WAN NIC, I copy the old MAC address because I use a single WAN IP address trick. I also increment the digit in the MAC address for the following NICs to keep the order clear.

![Adding an additional VirtIO network interface to the OPNsense VM](images/truenas-vm-add-nic.png)

After moving the VM NICs to the VLAN bridges, the passive OPNsense VM started correctly in TrueNAS.

![OPNsense booting successfully as a TrueNAS VM](images/truenas-vm-opnsense-start-shell.png)

## Validating the HA cluster

Once the passive node was running on TrueNAS, I needed to validate that the OPNsense HA cluster was still behaving correctly.

I started with basic checks on the passive node:

- Management interface ping from the bastion: `192.168.88.3`
- User interface ping from a laptop: `192.168.13.3`
- IoT interface ping: `192.168.37.3`
- pfSync ping from the other node: `192.168.44.2`
- DMZ interface ping: `192.168.55.3`
- Lab interface ping from DockerVM: `192.168.66.3`

I also checked that the node was accessible over SSH from Termius using `192.168.13.3`, and that the web interface was reachable at:

```text
https://192.168.13.3:4443
```

Then I validated the OPNsense HA state:

- CARP VIP status must be `BACKUP` on all VIPs
- HA status page must show that the active node can log in to the passive node
- Services must be running as expected
- HA service synchronization must work
- Firmware update checks must be accessible

From the active node, I used the HA status page and forced a full synchronization with `Synchronize and reconfigure all`.

## Switchover tests

Before testing failover, I started an SSH session to DockerVM to confirm that firewall states were preserved across nodes. I also started a ping from a laptop to `192.168.37.120`.

For the switchover test, I gracefully enabled maintenance mode on the master node.

The passive node became `MASTER`, and I validated the important services:

- Extra VLAN routing with ping to `192.168.37.120`
- WAN access with ping to `8.8.8.8`
- Firewall states by keeping the SSH session alive
- External DNS resolution with `host redhat.com`
- Internal DNS resolution with `host SLZB-06M.mgmt.vezpi.com`
- Access to a random internet page
- Caddy reverse proxy
- Caddy layer4 proxy
- Wireguard access from outside
- mDNS by checking if the printer showed up

The switchover was successful.

I also tested the switchback. It required entering maintenance mode and leaving it again to return to the expected state, but the cluster behavior was validated.

## Failover tests

After the graceful switchover test, I tested a more direct failover scenario by forcing a poweroff of the active node.

I repeated the same validation checklist:

- Extra VLAN routing
- WAN access
- Firewall states
- DNS resolution
- Caddy reverse proxy
- Caddy layer4 proxy
- Wireguard
- mDNS

For DNS, I tested an external domain with:

```text
host microsoft.com
```

And I also checked the internal host:

```text
host SLZB-06M.mgmt.vezpi.com
```

The failover was successful.

Finally, I restarted the active OPNsense VM.

At that point, the OPNsense HA cluster was operational again, with the passive node now running on TrueNAS instead of Proxmox.

## A note about QEMU Guest Agent

The OPNsense VM already had the QEMU Guest Agent installed.

In this setup, it does not seem useful because TrueNAS does not have it implemented as a hypervisor feature in the way I would need here. I kept it installed anyway, because it is harmless.

## Conclusion

This migration was a small but important improvement for my homelab.

Before, both OPNsense nodes depended on the Proxmox VE cluster. If the cluster was down, my whole network routing layer was down with it.

Now, the active node still runs on Proxmox, but the passive node runs on TrueNAS. This gives me a better separation between the virtualization cluster and the network failover layer.

The most important part of the project was the TrueNAS networking model. Creating VLAN interfaces was not enough for the VM use case. The working design was to create one bridge per VLAN and attach the OPNsense VM NICs to those bridges.

After validating CARP, HA sync, routing, DNS, Caddy, Wireguard, mDNS and firewall states, the cluster is working as expected.

The passive OPNsense node is now outside of Proxmox, and that is exactly what I wanted: keeping network abilities even when the Proxmox VE cluster is unavailable.