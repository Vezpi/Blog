---
slug: create-nas-server-with-truenas
title: Template
description:
date:
draft: true
tags:
  - truenas
categories:
---
## Introduction

In my homelab, I need somewhere I can put data, outside of my Proxmox VE cluster.

At the beginning, my only one physical server has 2 HDDs disks of 2 TB. When I installed Proxmox on it, these disks were still attached to the host. I managed to share the content using a NFS server in a LXC, but this was far from a good practice.

During this winter, the node started to fail, it was stopping by itself for no reason. This bad boy is 7 years old. When it was shut down, the NFS shares were unavailable, which was affecting some services in my homelab. Luckily I could fix it up by replacing its CPU fan, but now I want a safer place for these data.

In this article I will walk you through the entire build of my NAS, using TrueNAS.

---
## Choose the right platform


For a while I wanted to have a NAS. Not one ready out-of-the-box like Synology or QNAP. While I think these are good products, I wanted to build mine. But I have a huge constraint of space in my tiny rack and the choice for a small NAS case are very limited.

### Hardware

I consider full flash NAS. This has several advantages:
- It is fast
- It is small
- It consumes less
- It heats less
But with a major drawback, the price.

While the speed is negligible to me because my network can't handle it, the others are exactly what I’m looking for. I don't need a massive volume a data, around 2 TB of usable space is enough.

My first choice was the [Aiffro K100](https://www.aiffro.com/fr/products/all-ssd-nas-k100). But I couldn't find a way to have it delivered to France without doubling the price. Finally I managed to buy a [Beelink ME mini](https://www.bee-link.com/products/beelink-me-mini-n150?variant=48678160236786).

This small cube has:
- N200 CPU
- 12 GB of RAM
- 2x 2.5Gbps Ethernet ports 
- can host up to 6x NVMe drives
- a 64 GB eMMC chip to install an OS.

I started with 2 drives for now, 2 TB each.

### Software

Now that the hardware is chosen, which software will I use?

In the past I've heard of several NAS operating system, like FreeNAS, Open Media Vault or Unraid. But I never really dig into the subject.

Here are my requirements:
- NFS shares
- ZFS support
- VM capabilities

After comparing the solutions, the choice was made to use TrueNAS Scale 25.10 Community Edition, which is the new name of FreeNAS.

---
## Install TrueNAS

⚠️ I'll install the TrueNAS OS on my eMMC chip. This is not recommended as eMMC endurance could be a risk.

The installation of TrueNAS didn’t go as smoothly as expected.

I'm using [Ventoy](https://www.ventoy.net/en/index.html) to store multiple ISO in a single USB stick. I was in version 1.0.99, and the ISO wouldn't launch. I had to update to version 1.1.10 to make it work:
![TrueNAS installation splash screen](img/truenas-iso-installation-splash.png)

But here I encounter another problem when launching the installation on my eMMC storage device:
```
Failed to find partition number 2 on mmcblk0
```

I found a solution on this [post](https://forums.truenas.com/t/installation-failed-on-emmc-odroid-h4/15317/12):
- Enter the shell
![Enter the shell in TrueNAS installer](img/truenas-iso-enter-shell.png)
- Edit the file `/lib/python3/dist-packages/truenas_installer/utils.py`
- Move the line `await asyncio.sleep(1)` right beneath `for _try in range(tries):`
- Edit line 46 to add `+ 'p'`:
`for partdir in filter(lambda x: x.is_dir() and x.name.startswith(device + 'p'), dir_contents):`
![Fixed file in the TrueNAS installer](img/truenas-iso-fix-installer.png)
- Exit the shell and start the installation without reboot

The installer was finally able to get through:
![TrueNAS installation progress](img/truenas-iso-installation.png)

Once the installation is complete, I shut down the machine. Then I install it into my rack on top of the 3 Proxmox VE nodes. I plug both Ethernet cables from my switch, the power and turn it on.

## Configure TrueNAS

By default TrueNAS is using DHCP. I check the lease given on my UniFi interface to gather its MAC. Then I reserve a static DHCP lease. In OPNsense, I define a new host override in Dnsmasq. Finally in the Caddy plugin, I create a new domain for TrueNAS with that IP. I restart the machine a last time.

✅ After a few minutes, TrueNAS is now available on https://nas.vezpi.com.
### General Settings

During the installation I didn't choose to define a password for the user `truenas_admin`. I'm requested to change it as soon as I reach the login page:
![TrueNAS login page to change `truenas_admin` password](img/truenas-login-page-change-password.png)

Once the password is updated, I land on the dashboard. The UI feels great at first glance:
![TrueNAS dashboard](img/truenas-fresh-install-dashboard.png)

I quickly explore the interface, the first thing I do is changing the hostname to `granite` and check the box below to define the domain inherited from DHCP:
![TrueNAS hostname configuration](img/truenas-config-change-hostname.png)

In the `General Settings`, I change the `Localization` settings. I set the Console Keyboard Map to `French (AZERTY)` and the Timezone to `Europe/Paris`.

I create a new user `vez`, with `Full Admin` role within TrueNAS. I allow SSH access but only with a SSH key, not with password:
![TrueNAS user creation](img/truenas-create-new-user.png)

Finally I remove the admin role from `truenas_admin` and lock the account.

### Pool creation

In TrueNAS, a pool is a storage collection created by combining multiple disks into a unified ZFS‑managed space.

In the `Storage` page, I can find my `Disks`, where I can confirm TrueNAS can see my couple of NVMe drives:
![List of available disks in TrueNAS](img/truenas-storage-disks-unconfigured.png)

Back in the `Storage Dashboard`, I click the `Create Pool` button. I name the pool `storage` because I'm really inspired:
![Pool creation wizard in TrueNAS](img/truenas-pool-creation-general.png)

Then I select the `Mirror` layout:
![Disk layout selection in the pool creation wizard in TrueNAS](img/truenas-pool-creation-layout.png)

I explore quickly the optional configurations, but the defaults are fine for me: autotrim, compression, no dedup, etc. At the end, before creating the pool, there is a `Review` section:
![Review section of the pool creation wizard in TrueNAS](img/truenas-pool-creation-review.png)

After hitting `Create Pool`, I'm warned that everything on the disks will be erased, which I confirm. Finally the pool is created.

### Datasets creation

A dataset is a filesystem inside a pool. It can contains files, directories and child datasets of files, it can be shared using NFS and/or SMB. It allows you to independently manage permissions, compression, snapshots, and quotas for different sets of data within the same storage pool.

#### SMB share

Let's now create my first dataset `files` to share files over the network, like ISOs, etc:
![Create a dataset in TrueNAS](img/truenas-create-dataset-files.png)

Creating my first SMB dataset, TrueNAS prompts me to start and enable the SMB service:
![Prompt to start SMB service in TrueNAS](img/truenas-start-smb-service.png)

From my Windows Laptop, I try to access my new share `\\granite.mgmt.vezpi.com\files`. As expected I'm prompted to give credentials.

I create a new user account with SMB permission.

✅ I can now browse the share and copy files into it.

#### NFS share

I create another dataset: `media`, and a child `photos`. I create a NFS share from the latter. 

On my current NFS server, the files for the photos are owned by `root` (managed by *Immich*). Later I'll see how I can migrate towards a root-less version. 

⚠️ For now I set, in `Advanced Options`, the `Maproot User` and `Maproot Group` to `root`. This is equivalent to the attribute `no_squash_root`, the local `root` of the client stays `root` on the server, don't do that:
![NFS share permission in TrueNAS](img/truenas-dataset-photos-nfs-share.png)

✅ I try to mount the NFS share on a client, this is working fine.

At the end, my datasets tree in my `storage` pool look like this:
- backups
	- `duplicati`: [Duplicati](https://duplicati.com/) storage backend
	- `proxmox`: future Proxmox Backup Server
- `cloud`: `Nextcloud` data
- `files`:
- `media`
	- `downloads`
	- `photos`
	- `videos`

On the requirement, I talked about VM capabilities. I won't cover that is this post, it will be covered next time.
### Data protection

Now let's configure some data protection features, here is the `Data Protection` tab:
![Data protection features in TrueNAS](img/truenas-data-protection-tab.png)

I want to create automatic snapshots for some of my datasets, those I care the most are my cloud files and the photos.

Let's create snapshot tasks. I click on the `Add` button next to `Periodic Snapshot Tasks`. For the `cloud` dataset, I create a daily snapshot with a lifetime of 2 months, for `photos`, only 7 days should be fine:
![Create periodic snapshot task in TrueNAS ](img/truenas-create-periodic-snapshot.png)

I could also create a `Cloud Sync Task` but I already have Duplicati managing this.

---
## Using TrueNAS

Now my TrueNAS instance is configured, I need to plan the migration of the data from my current NFS server to TrueNAS.
### Data migration

For each of my current NFS shares, on a client, I mount the new NFS share to synchronize the data:
```
sudo mkdir /new_photos
sudo mount 192.168.88.30:/mnt/storage/media/photos /new_photos
sudo rsync -a --info=progress2 /data/photo/ /new_photos
```

At the end, I could decommission my old NFS server on the LXC. The dataset layout after migration looks like this:
![Dataset layout in TrueNAS](img/truenas-datasets-layout.png)

### Android application

Out of curiosity, I've checked on the Google Play store for an app to manage a TrueNAS instance. I've found [Nasdeck](https://play.google.com/store/apps/details?id=com.strtechllc.nasdeck&hl=fr&pli=1), which is quite nice. Here some screenshots:
![Screenshots of Nasdeck application](img/nasdeck-android-app.png)

---
## Conclusion

My NAS is now ready to store my data.

I didn't address VM capabilities as I will experience it soon to install Proxmox Backup Server as VM. Also I didn't configure notifications, I need to setup a solution to receive email alerts to my notification system.
****
TrueNAS is a really great product. It requires a little bit of hardware to support ZFS.

The next step would be to deploy a  in TrueNAS. 