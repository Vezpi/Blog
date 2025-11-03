---
slug: proxmox-cluster-upgrade-8-to-9-with-ceph
title: Template
description:
date:
draft: true
tags:
categories:
---

## Intro

My **Proxmox VE** cluster is almost one year old now, and it's been a while since I didn't update my nodes. Now is the time to move forward and bump it to Proxmox VE **9**.

I'm mainly interested in the new HA affinity rules, here what this version brings:
- Debian 13 "Trixie"
- Snapshots for thick-provisioned LVM shared storage
- Fabrics feature for the SDN stack
- Better mobile interface
- Affinity rules in HA cluster

In this article, I will walk you through the upgrade steps for my Proxmox VE highly available cluster supported by **Ceph** distributed storage. The official documentation can be found [here](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9).

---
## Prerequisites

Before jumping into the upgrade, let's review the prerequisites:

1. All nodes upgraded to the latest version of Proxmox VE 8.4.
2. Ceph: upgrade cluster to Ceph 19.2 Squid before.
3. Proxmox Backup Server: upgrade to Proxmox BS 4.
4. Reliable access to the node.
5. A healthy cluster.
6. backup of all VMs and CTs.
7. At least 5 GB free disk space on the root mount point.

Well, I have some homework to do before the major upgrade to Proxmox VE 9. My nodes are currently in version `8.3.2`, hence a first update is necessary.

Then my Ceph cluster, for my distributed storage, is using Ceph Reef (`18.2.4`). After the update to Proxmox VE 8.4, I'll move from Ceph Reef to Squid.

I don't use Proxmox Backup Server in my homelab for now, I can skip that point. For the access to the nodes, it is better to reach the console (not from the WebGUI). I don't have direct access, In only have SSH.

The last points are checked, all my nodes have more than 10GB on the `/` mount point.

ℹ️ One of my VM is using the host's processing unit of the APU via PCI pass-through. As this prevents the VM for hot migration, I remove the device at the beginning of this procedure to avoid having to restart the VM each time.

Also, until the end of the upgrade to Proxmox VE 9, I set the Ceph OSDs as "no out", to avoid the CRUSH algorithm to try to rebalance the Ceph cluster during the upgrade:
```bash
ceph osd set noout
```

### Update Proxmox VE to 8.4.14

The plan is simple, for all nodes, one at a time, I will:
- Enable the maintenance mode
```bash
ha-manager crm-command node-maintenance enable $(hostname)
```

- Update the node
```bash
apt-get update
apt-get dist-upgrade -y
```

At the end of the update, I'm aksed to remove a bootloader, which I execute:
```plaintext
Removable bootloader found at '/boot/efi/EFI/BOOT/BOOTX64.efi', but GRUB packages not set up to update it!
Run the following command:

echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u

Then reinstall GRUB with 'apt install --reinstall grub-efi-amd64'
```

- Restart it
```bash
reboot
```

- Disable the maintenance node
```bash
ha-manager crm-command node-maintenance disable $(hostname)
```

Between each node, I wait for the Ceph status to be clean, without warnings.

✅ At the end, the Proxmox VE cluster is updated to `8.4.14`

### Upgrade Ceph from Reef to Squid

I can now move on into the Ceph upgrade, the Proxmox documentation for that topics is [here](https://pve.proxmox.com/wiki/Ceph_Reef_to_Squid).

On all nodes, I update the source of the Ceph packages for Proxmox:
```bash
sed -i 's/reef/squid/' /etc/apt/sources.list.d/ceph.list
```

I upgrade the Ceph packages:
```
apt update
apt full-upgrade -y
```

After the upgrade on the first node, the Ceph version now shows `19.2.3`, I can see my OSDs appear now outdated, the monitors need either an upgrade or a restart:
![proxmox-ceph-version-upgrade.png](img/proxmox-ceph-version-upgrade.png)

I carry on and upgrade the packages on the 2 other nodes. 

I have a monitor on each node, so I have to restart the monitor, one node at a time:
```bash
systemctl restart ceph-mon.target
```

I verify the Ceph status between each restart:
```bash
ceph status
```

Once all monitors are restarted, they report the latest version, with `ceph mon dump`:
- Before: `min_mon_release 18 (reef)`
- After: `min_mon_release 19 (squid)`

Now I can restart the OSD, still one node at a time. I have one OSD per node:
```bash
systemctl restart ceph-osd.target
```

I monitor the Ceph status with the Proxmox WebGUI. At start, it is showing some fancy colors. I'm just waiting to be back to full green, it takes less than a minute:
![Pasted_image_20251102230907.png](img/Pasted_image_20251102230907.png)

A warning now shows up: `HEALTH_WARN: all OSDs are running squid or later but require_osd_release < squid`. Now all my OSDs are running Squid, I can set the minimum version to it:
```bash
ceph osd require-osd-release squid
```

ℹ️ I'm not currently using CephFS so I don't have to care about the MDS (MetaData Server) daemon.

✅ The Ceph cluster has been successfully upgraded to Squid (`19.2.3`).

---
## Checks

The prerequisites to upgrade the cluster to Proxmox VE 9 are now complete. Am I ready to upgrade? Not yet.

### Script `pve8to9`

A small checklist program named **`pve8to9`** is included in the latest Proxmox VE 8.4 packages. The program will provide hints and warnings about potential issues before, during and after the upgrade process. Pretty handy isn't it?

Running the tool the first time give me some insights on what I need to do. The script checks a number of parameters, grouped by theme. Here the VM guest section:
```plaintext
= VIRTUAL GUEST CHECKS =

INFO: Checking for running guests..
WARN: 1 running guest(s) detected - consider migrating or stopping them.
INFO: Checking if LXCFS is running with FUSE3 library, if already upgraded..
SKIP: not yet upgraded, no need to check the FUSE library version LXCFS uses
INFO: Checking for VirtIO devices that would change their MTU...
PASS: All guest config descriptions fit in the new limit of 8 KiB
INFO: Checking container configs for deprecated lxc.cgroup entries
PASS: No legacy 'lxc.cgroup' keys found.
INFO: Checking VM configurations for outdated machine versions
PASS: All VM machine versions are recent enough
```

At the end, you have the summary. The goal is to address as many `FAILURES` and `WARNINGS` as possible:
```plaintext
= SUMMARY =

TOTAL:    57
PASSED:   43
SKIPPED:  7
WARNINGS: 2
FAILURES: 2
```

These are the `FAILURES` and `WARNINGS` on my system:
```
FAIL: 1 custom role(s) use the to-be-dropped 'VM.Monitor' privilege and need to be adapted after the upgrade
FAIL: systemd-boot meta-package installed. This will cause problems on upgrades of other boot-related packages. Remove 'systemd-boot' See https://pve.proxmox.com/wiki/Upgrade_from_8_to_9#sd-boot-warning for more information.
WARN: 1 running guest(s) detected - consider migrating or stopping them.
WARN: The matching CPU microcode package 'amd64-microcode' could not be found! Consider installing it to receive the latest security and bug fixes for your CPU.
        Ensure you enable the 'non-free-firmware' component in the apt sources and run:
        apt install amd64-microcode
```

### Custom Role using `VM.Monitor`

Some time ago, in order to use Terraform with my Proxmox cluster, I created a dedicated role. This was detailed in that [post]({{< ref "post/3-terraform-create-vm-proxmox" >}}).

This role is using the `VM.Monitor` privilege, which is removed in Proxmox VE 9. Instead, new privileges  under `VM.GuestAgent.*` exist. So I remove this one and I'll add those once the cluster have been upgraded.

### Meta-package `systemd-boot`

 Proxmox VE usually use `systemd-boot` for booting only in some configurations (ZFS on root and UEFI booted without secure boot), which are managed by `proxmox-boot-tool`, the meta-package `systemd-boot` should be removed. The package was automatically shipped for systems installed from the PVE 8.1 to PVE 8.4 ISOs, as it contained `bootctl` in bookworm.

If the `pve8to9` checklist script suggests it, the `systemd-boot` meta-package is safe to remove unless you manually installed it and are using `systemd-boot` as a bootloader. Should `systemd-boot-efi` and `systemd-boot-tools` be required, `pve8to9` will warn you accordingly. The `pve8to9` checklist script will change its output depending on the state of the upgrade, and should be [run continuously before and after the upgrade](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9#Continuously_use_the_pve8to9_checklist_script "Upgrade from 8 to 9"). It will print which packages should be removed or added at the appropriate time.



NOTICE: Proxmox VE 9 replaced the ambiguously named 'VM.Monitor' privilege with 'Sys.Audit' for QEMU HMP monitor access and new dedicated '*' privileges for access to a VM's guest agent.
        The guest agent sub-privileges are 'Audit' for all informational commands, 'FileRead' and 'FileWrite' for file-read and file-write, 'FileSystemMgmt' for filesystem freeze, thaw and trim, and 'Unrestricted' for everything, including command execution. Operations that affect the VM runstate require 'VM.PowerMgmt' or 'VM.GuestAgent.Unrestricted'
#### New

- VM.PowerMgmt
- Sys.Console
- Sys.Audit
- VM.Config.Cloudinit
- Pool.Allocate
- SDN.Use
- VM.Config.Memory
- VM.Allocate
- VM.Console
- VM.Clone
- VM.Config.Network
- Sys.Modify
- VM.Config.Disk
- Datastore.Allocate
- VM.Config.CPU
- VM.Config.CDROM
- Datastore.Audit
- VM.Migrate
- Datastore.AllocateSpace
- VM.Config.Options
- VM.Config.HWType
- VM.Audit


To add
- VM.GuestAgent.Audit
- VM.GuestAgent.FileRead
- VM.GuestAgent.FileWrite
- VM.GuestAgent.FileSystemMgmt
- VM.GuestAgent.Unrestricted
- SDN.Audit
- Mapping.Audit
- Mapping.Use
- Sys.Syslog
- Pool.Audit

Dropped
- Permissions.Modify"
- SDN.Allocate
- Realm.Allocate
- VM.Replicate
- Realm.AllocateUser
- Sys.AccessNetwork
- Datastore.AllocateTemplate
- Sys.PowerMgmt
- User.Modify
- Mapping.Modify
- Group.Allocate
- Sys.Incoming
- VM.Backup
- VM.Snapshot
- VM.Snapshot.Rollback

#### Old
VM.Monitor

NOTICE: Proxmox VE 9 replaced the ambiguously named 'VM.Monitor' privilege with 'Sys.Audit' for QEMU HMP monitor access and new dedicated 'VM.GuestAgent.*' privileges for access to a VM's guest agent.
        The guest agent sub-privileges are 'Audit' for all informational commands, 'FileRead' and 'FileWrite' for file-read and file-write, 'FileSystemMgmt' for filesystem freeze, thaw and trim, and 'Unrestricted' for everything, including command execution. Operations that affect the VM runstate require 'VM.PowerMgmt' or 'VM.GuestAgent.Unrestricted'

### Continuously use the **pve8to9** checklist script



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


### Post-Upgrade Validation

- Checking cluster communication (`pvecm status`)
    
- Verifying storage mounts and access
    
- Testing Ceph cluster health (`ceph -s`)
    
- Confirming VM operations, backups, and HA groups
    
- Re-enabling HA and migrating workloads back


Finally, I can remove the noout flag:
```bash
ceph osd unset noout
```

Add role to terraform user