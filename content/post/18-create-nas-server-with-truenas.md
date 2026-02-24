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

In my homelab, I need somewhere I can put datas, outside of my Proxmox VE cluster.

At the beginning, my only one physical server has 2 HDDs disks of 2 TB. When I installed Proxmox on it, these disks were still attached to the host. I managed to share the content using a NFS server in a LXC, but this was far from a good practice.

During this winter, the node started to fail, it was stopping by itself for no reason. This bad boy is 7 years old. When it was shut down, the NFS share were unavailable, which was affecting some services in my homelab. Luckily I could fix it up by replacing its CPU fan, but now I want a safer place for these datas.

I this article I will walk you through the entire build of my NAS, using TrueNAS.


## Choose the the right platform


For a while I wanted to have a NAS. Not one ready out-of-the-box like Synology or QNAP. While I think these are good products, I wanted to build mine. But I have a huge constraint of space in my tiny rack and the choice for a small NAS case are very limited.

### Hardware

I consider full flash NAS. This has several advantages:
- It is fast
- It is small
- It consumes less
- It heats less
But with a major drawback, the price.

While the speed is negligible to me because my network can't handle it, the others are exactly what I'm looking for. I don't need a massive volume a data, around 2 TB of usable space is enough.

My first choice was the [Aiffro K100](https://www.aiffro.com/fr/products/all-ssd-nas-k100). But I couldn't find a way to have it deliver in France without doubling the price. Finally I managed to buy a [Beelink ME mini](https://www.bee-link.com/products/beelink-me-mini-n150?variant=48678160236786).

This small cube has:
- N200 CPU
- 12 GB of RAM
- 2x 2.5Gbps Ethernet ports 
- can host up to 6x NVMe drives
- a 64 GB eMMC chip to install an OS.

I started with 2 drives for now, 2 TB each.

### Software

Now that the hardware choice is done, what I would use as software?

In the past I've heard of several NAS operating system, like FreeNAS, Open Media Vault or Unraid. But I never really dig into the subject.

Here my requirements:
- NFS shares
- ZFS support
- VM capabilities

After comparing the solutions, the choice was made to use TrueNAS Community Edition, which is the new name of FreeNAS.

## Install TrueNAS

The installation of TrueNAS didn't go as smooth as I expected id to be.

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

Once the installation is complete, I shutdown the machine. Then I install it into my rack on top of the 3 Proxmox VE nodes. I plug both Ethernet cables from my switch, the power and turn it on.

## Configuration of TrueNAS

By default TrueNAS is using DHCP. I check the UniFi interface to gather its MAC, then in OPNsense, I define a new host override in Dnsmasq. Finally in the Caddy plugin, I create a new domain for TrueNAS with that IP. I restart the machine a last time.

✅ After a few minutes, TrueNAS is now available on https://nas.vezpi.com.
### General Settings

During the installation I didn't choose to define a password for the user `truenas_admin`. I'm requested to change it as soon as I reach the login page:
![TrueNAS login page to change `truenas_admin` password](img/truenas-login-page-change-password.png)

Once the password is updated, I land on the dashbaord. The UI feels great at first glance:
![TrueNAS dashboard](img/truenas-fresh-install-dashboard.png)

The first thing I do is to change the hostname to `granite` and check the box below to define the domain inherited from DHCP:
![TrueNAS hostname configuration](img/truenas-config-change-hostname.png)

In the `General Settings`, I change the `Localization` settings. I set the Console Keyboard Map to `French (AZERTY)` and the Timezone to `Europe/Paris`.

I create a new user `vez`, with `Full Admin` role within TrueNAS. I allow SSH access but only with a SSH key, not with password:
![TrueNAS user creation](img/truenas-create-new-user.png)

Finally I remove the admin role from `truenas_admin` and lock the account.

### Pool creation

{what is pool}

In the `Storage` page, I can find my `Disks`, where I can confirm TrueNAS can see my couple of NVMe drives:
![truenas-storage-disks-unconfigured.png](img/truenas-storage-disks-unconfigured.png)

Now back in the `Storage Dashboard`, I click the `Create Pool` button. I name the pool `storage`:
![truenas-pool-creation-general.png](img/truenas-pool-creation-general.png)

Then I select the `Mirror` layout:
![truenas-pool-creation-layout.png](img/truenas-pool-creation-layout.png)

I explore quickly the optional options but none makes sense for my setup. At the end, before creating the pool, there is a Review section:
![truenas-pool-creation-review.png](img/truenas-pool-creation-review.png)

After hitting `Create Pool`, I'm warned that everything on the disks will be erased, which I have to confirm. Finally the pool is created.

### dataset config

### data protection

## Use of TrueNAS

### Firewall rule

### Data migration

### Android application

## Conclusion