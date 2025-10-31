---
slug: 
title: Template
description: 
date: 
draft: true
tags: 
categories:
---


## Prerequisites

- Upgraded to the latest version of Proxmox VE 8.4 on all nodes.
    
    Ensure your node(s) have correct package repository configuration (web UI, Node -> Repositories) if your pve-manager version isn't at least `8.4.1`.
    
- Hyper-converged Ceph: upgrade any Ceph Quincy or Ceph Reef cluster to Ceph 19.2 Squid **before** you start the Proxmox VE upgrade to 9.0.
    
    Follow the guide [Ceph Quincy to Reef](https://pve.proxmox.com/wiki/Ceph_Quincy_to_Reef "Ceph Quincy to Reef") and [Ceph Reef to Squid](https://pve.proxmox.com/wiki/Ceph_Reef_to_Squid "Ceph Reef to Squid"), respectively.
    
- Co-installed Proxmox Backup Server: see [the Proxmox Backup Server 3 to 4 upgrade how-to](https://pbs.proxmox.com/wiki/index.php/Upgrade_from_3_to_4)
- Reliable access to the node. It's recommended to have access over a host independent channel like IKVM/IPMI or physical access.
    
    If only SSH is available we recommend testing the upgrade on an identical, but non-production machine first.
    
    It is also highly recommended to use a terminal multiplexer (for example, tmux or screen) to ensure the upgrade can continue even if the SSH connection gets interrupted.
    
- A healthy cluster
- Valid and tested backup of all VMs and CTs (in case something goes wrong)
- At least 5 GB free disk space on the root mount point, ideally more than 10 GB.
- Check [known upgrade issues](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9#Known_Upgrade_Issues)

## Checks


Use console if possible, avoid using console from the WebGUI. Use SSH instead

### Continuously use the **pve8to9** checklist script

A small checklist program named **`pve8to9`** is included in the latest Proxmox VE 8.4 packages. The program will provide hints and warnings about potential issues before, during and after the upgrade process. You can call it by executing:

 pve8to9

### Move important Virtual Machines and Containers


## Upgrade
### Update the configured APT repositories

#### Update Debian Base Repositories to Trixie

#### Add the Proxmox VE 9 Package Repository

#### Update the Ceph Package Repository

#### Refresh Package Index

### Upgrade the system to Debian Trixie and Proxmox VE 9.0

### Check Result & Reboot Into Updated Kernel