---
slug: create-nas-server-with-truenas
title: Construction et installation de mon NAS avec TrueNAS SCALE
description: "Guide pas à pas pour un NAS TrueNAS SCALE en homelab : choix du matériel, installation, pool ZFS et datasets, partages SMB/NFS et snapshots."
date: 2026-02-27
draft: true
tags:
  - truenas
categories:
  - homelab
---
## Introduction

Dans mon homelab, j'ai besoin d'un endroit pour stocker des données en dehors de mon cluster Proxmox VE.

Au départ, mon unique serveur physique a 2 disques HDD de 2 To. Quand j'ai installé Proxmox dessus, ces disques sont restés attachés à l'hôte. Je les ai partagés via un serveur NFS dans un LXC, loin des bonnes pratiques.

Cet hiver, le nœud a commencé à montrer des signes de faiblesse, s'éteignant sans raison. Ce compagnon a maintenant 7 ans. Lorsqu'il est passé hors ligne, mes partages NFS ont disparu, entraînant la chute de quelques services dans mon homelab. Le remplacement du ventilateur du CPU l'a stabilisé, mais je veux maintenant un endroit plus sûr pour ces données.

Dans cet article, je vais vous expliquer comment j'ai construit mon NAS avec TrueNAS.

---
## Choisir la bonne plateforme

Depuis un moment je voulais un NAS. Pas un Synology ou QNAP prêt à l'emploi, même si je pense qu'ils sont de bons produits. Je voulais le construire moi‑même. L'espace est limité dans mon petit rack, et les boîtiers NAS compacts sont rares.

### Matériel

Je suis parti sur un NAS full‑flash. Pourquoi ?

- C'est rapide
- C'est ~~furieux~~ compact
- C'est silencieux
- Ça consomme moins d'énergie
- Ça chauffe moins

Le problème est le prix.

La vitesse réseau est de toute façon mon goulot d'étranglement, mais les autres avantages sont exactement ce que je veux. Je n'ai pas besoin d'une capacité massive, environ 2 To utilisables suffisent.

Mon premier choix était le [Aiffro K100](https://www.aiffro.com/fr/products/all-ssd-nas-k100). Mais la livraison vers la France a presque doublé le prix. Finalement j'ai opté pour un [Beelink ME mini](https://www.bee-link.com/products/beelink-me-mini-n150?variant=48678160236786).

Ce petit cube a :
- CPU Intel N200
- 12 Go de RAM
- 2x Ethernet 2,5 Gbps
- Jusqu'à 6x disques NVMe
- Une puce eMMC 64 Go pour l'OS

J'ai commencé avec 2 disques NVMe pour l'instant, 2 To chacun.

### Logiciel

Maintenant que le matériel est choisi, quel logiciel vais‑je utiliser ?

Mes besoins étaient simples :
- partages NFS
- support ZFS
- capacités VM

J'ai considéré FreeNAS/TrueNAS, OpenMediaVault et Unraid. J'ai choisi TrueNAS SCALE 25.10 Community Edition. Pour être clair : FreeNAS a été renommé TrueNAS CORE (basé sur FreeBSD), tandis que TrueNAS SCALE est la gamme basée sur Linux. J'utilise SCALE.

---
## Installer TrueNAS

⚠️ J'ai installé TrueNAS sur la puce eMMC. Ce n'est pas recommandé, l'endurance de l'eMMC peut être un risque.

L'installation ne s'est pas déroulée aussi bien que prévu...

J'utilise [Ventoy](https://www.ventoy.net/en/index.html) pour garder plusieurs ISOs sur une clé USB. J'étais en version 1.0.99, et l'ISO ne se lançait pas. La mise à jour vers 1.1.10 a résolu le problème :
![TrueNAS installation splash screen](img/truenas-iso-installation-splash.png)

Mais là j'ai rencontré un autre problème lors du lancement de l'installation sur mon périphérique de stockage eMMC :
```
Failed to find partition number 2 on mmcblk0
```

J'ai trouvé une solution sur ce [post](https://forums.truenas.com/t/installation-failed-on-emmc-odroid-h4/15317/12) :
- Entrer dans le shell
![Enter the shell in TrueNAS installer](img/truenas-iso-enter-shell.png)
- Edit the file `/lib/python3/dist-packages/truenas_installer/utils.py`
- Move the line `await asyncio.sleep(1)` right beneath `for _try in range(tries):`
- Edit line 46 to add `+ 'p'`:
`for partdir in filter(lambda x: x.is_dir() and x.name.startswith(device + 'p'), dir_contents):`
![Fixed file in the TrueNAS installer](img/truenas-iso-fix-installer.png)
- Exit the shell and start the installation without reboot

The installer was finally able to get through:
![TrueNAS installation progress](img/truenas-iso-installation.png)

Once the installation was complete, I shut down the machine. Then I installed it into my rack on top of the 3 Proxmox VE nodes. I plugged both Ethernet cables from my switch and powered it up.

## Configure TrueNAS

By default, TrueNAS uses DHCP. I found its MAC in UniFi and created a DHCP reservation. In OPNsense, I added a Dnsmasq host override. In the Caddy plugin, I set up a domain for TrueNAS pointing to that IP, then rebooted.

✅ After a few minutes, TrueNAS is now available on https://nas.vezpi.com.
### General Settings

During install, I didn’t set a password for truenas_admin. The login page forced me to pick one:
![TrueNAS login page to change `truenas_admin` password](img/truenas-login-page-change-password.png)

Once the password is updated, I land on the dashboard. The UI feels great at first glance:
![TrueNAS dashboard](img/truenas-fresh-install-dashboard.png)

I quickly explore the interface, the first thing I do is changing the hostname to `granite` and check the box below et it inherit domain from DHCP:
![TrueNAS hostname configuration](img/truenas-config-change-hostname.png)

In the `General Settings`, I change the `Localization` settings. I set the Console Keyboard Map to `French (AZERTY)` and the Timezone to `Europe/Paris`.

I create a new user `vez`, with `Full Admin` role within TrueNAS. I allow SSH for key‑based auth only, no passwords:
![TrueNAS user creation](img/truenas-create-new-user.png)

Finally I remove the admin role from `truenas_admin` and lock the account.

### Pool creation

In TrueNAS, a pool is a storage collection created by combining multiple disks into a unified ZFS‑managed space.

In the `Storage` page, I can find my `Disks`, where I can confirm TrueNAS can see my couple of NVMe drives:
![List of available disks in TrueNAS](img/truenas-storage-disks-unconfigured.png)

Back in the `Storage Dashboard`, I click the `Create Pool` button. I name the pool `storage` because I'm really inspired to give it a name:
![Pool creation wizard in TrueNAS](img/truenas-pool-creation-general.png)

Then I select the `Mirror` layout:
![Disk layout selection in the pool creation wizard in TrueNAS](img/truenas-pool-creation-layout.png)

I explore quickly the optional configurations, but the defaults are fine to me: autotrim, compression, no dedup, etc. At the end, before creating the pool, there is a `Review` section:
![Review section of the pool creation wizard in TrueNAS](img/truenas-pool-creation-review.png)

After hitting `Create Pool`, I'm warned that everything on the disks will be wiped, which I confirm. Finally the pool is created.

### Datasets creation

A dataset is a filesystem inside a pool. It can contains files, directories and child datasets, it can be shared using NFS and/or SMB. It allows you to independently manage permissions, compression, snapshots, and quotas for different sets of data within the same storage pool.

#### SMB share

Let's now create my first dataset `files` to share files over the network for my Windows client, like ISOs, etc:
![Create a dataset in TrueNAS](img/truenas-create-dataset-files.png)

When creating SMB datasets in SCALE, set Share Type to SMB so the right ACL/xattr defaults apply. TrueNAS then prompts me to start/enable the SMB service:
![Prompt to start SMB service in TrueNAS](img/truenas-start-smb-service.png)

From my Windows Laptop, I try to access my new share `\\granite.mgmt.vezpi.com\files`. As expected I'm prompt to give credentials.

I create a new user account with SMB permission.

✅ Success: I can browse and copy files.

#### NFS share

I create another dataset: `media`, and a child `photos`. I create a NFS share from the latter. 

On my current NFS server, the files for the photos are owned by `root` (managed by *Immich*). Later I'll see how I can migrate towards a root-less version. 

⚠️ For now I set, in `Advanced Options`, the `Maproot User` and `Maproot Group` to `root`. This is equivalent to the NFS attribute `no_squash_root`, the local `root` of the client stays `root` on the server, don't do that:
![NFS share permission in TrueNAS](img/truenas-dataset-photos-nfs-share.png)

✅ I mount the NFS share on a client, this works fine.

After initial setup, my `storage` pool datasets look like:
- backups
	- `duplicati`: [Duplicati](https://duplicati.com/) storage backend
	- `proxmox`: future Proxmox Backup Server
- `cloud`: `Nextcloud` data
- `files`:
- `media`
	- `downloads`
	- `photos`
	- `videos`

I mentioned VM capabilities in my requirements. I won't cover that is this post, it will be covered next time.
### Data protection

Now time to enable some data protection features:
![Data protection features in TrueNAS](img/truenas-data-protection-tab.png)

I want to create automatic snapshots for some of my datasets, those I care the most: my cloud files and photos.

Let's create snapshot tasks. I click on the `Add` button next to `Periodic Snapshot Tasks`:
- cloud: daily snapshots, keep for 2 months
- photos: daily snapshots, keep for 7 days
![Create periodic snapshot task in TrueNAS ](img/truenas-create-periodic-snapshot.png)

I could also set up a `Cloud Sync Task`, but Duplicati already handles offsite backups.

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

TrueNAS is a great product. It needs capable hardware for ZFS, but the experience is excellent once set up.

Next step: deploy Proxmox Backup Server as a VM on TrueNAS, then revisit NFS permissions to go root‑less for Immich.