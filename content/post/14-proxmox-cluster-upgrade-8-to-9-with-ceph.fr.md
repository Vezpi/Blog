---
slug: proxmox-cluster-upgrade-8-to-9-with-ceph
title: Upgrading my 3-node Proxmox VE HA Cluster from 8 to 9 with Ceph
description: Step-by-step upgrade of my 3-node Proxmox VE highly available cluster from 8 to 9, based on Ceph distributed storage, without any downtime.
date: 2025-11-04
draft: true
tags:
  - proxmox
  - high-availability
  - ceph
categories:
  - homelab
---

## Intro

Mon **cluster Proxmox VE** a presque un an maintenant, et je n’ai pas tenu les nœuds complètement à jour. Il est temps de m’en occuper et de le passer en Proxmox VE **9**.

Je recherche principalement les nouvelles règles d’affinité HA, mais voici les changements utiles apportés par cette version :
- Debian 13 "Trixie".
- Snapshots pour le stockage LVM partagé thick-provisioned.
- Fonctionnalité SDN fabrics.
- Interface mobile améliorée.
- Règles d’affinité dans le cluster HA.

Le cluster est composée de 3 nœuds, hautement disponible, avec une configuration hyper‑convergée, utilisant Ceph pour le stockage distribué.

Dans cet article, je décris les étapes de mise à niveau de mon cluster Proxmox VE, de la version 8 à 9, tout en gardant les ressources actives. [Documentation officielle](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9).

---
## Prérequis

Avant de se lancer dans la mise à niveau, passons en revue les prérequis :

1. Tous les nœuds mis à jour vers la dernière version Proxmox VE `8.4`.
2. Cluster Ceph mis à niveau vers Squid (`19.2`).
3. Proxmox Backup Server mis à jour vers la version 4.
4. Accès fiable au nœud.
5. Cluster en bonne santé.
6. Sauvegarde de toutes les VM et CT.
7. Au moins 5 Go libres sur `/`.

Remarques sur mon environnement :

- Les nœuds PVE sont en `8.3.2`, donc une mise à jour mineure vers 8.4 est d’abord requise.
- Ceph tourne sous Reef (`18.2.4`) et sera mis à niveau vers Squid après PVE 8.4.
- Je n’utilise pas PBS dans mon homelab, donc je peux sauter cette étape.
- J’ai plus de 10 Go disponibles sur `/` sur mes nœuds, c’est suffisant.
- Je n’ai qu’un accès console SSH, si un nœud ne répond plus je pourrais avoir besoin d’un accès physique.
- Une VM a un passthrough CPU (APU). Le passthrough empêche la migration à chaud, donc je supprime ce mapping avant la mise à niveau.
- Mettre les OSD Ceph en `noout` pendant la mise à niveau pour éviter le rebalancing automatique :
```bash
ceph osd set noout
```

### Mettre à Jour Proxmox VE vers 8.4.14

Le plan est simple, pour tous les nœuds, un par un :

1. Activer le mode maintenance
```bash
ha-manager crm-command node-maintenance enable $(hostname)
```

2. Mettre à jour le nœud
```bash
apt-get update
apt-get dist-upgrade -y
```

À la fin de la mise à jour, on me propose de retirer booloader, ce que j’exécute :
```plaintext
Removable bootloader found at '/boot/efi/EFI/BOOT/BOOTX64.efi', but GRUB packages not set up to update it!
Run the following command:

echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u

Then reinstall GRUB with 'apt install --reinstall grub-efi-amd64'
```

3. Redémarrer la machine
```bash
reboot
```

4. Désactiver le mode maintenance
```bash
ha-manager crm-command node-maintenance disable $(hostname)
```

Entre chaque nœud, j’attends que le statut Ceph soit clean, sans alertes.

✅ À la fin, le cluster Proxmox VE est mis à jour vers `8.4.14`

### Mettre à Niveau Ceph de Reef à Squid

Je peux maintenant passer à la mise à niveau de Ceph, la documentation Proxmox pour cette procédure est [ici](https://pve.proxmox.com/wiki/Ceph_Reef_to_Squid).

Mettre à jour les sources de paquets Ceph sur chaque nœud :
```bash
sed -i 's/reef/squid/' /etc/apt/sources.list.d/ceph.list
```

Mettre à niveau les paquets Ceph :
```
apt update
apt full-upgrade -y
```

Après la mise à niveau sur le premier nœud, la version Ceph affiche maintenant `19.2.3`, je peux voir mes OSD apparaître comme obsolètes, les moniteurs nécessitent soit une mise à niveau soit un redémarrage :
![Ceph storage status in Proxmox after first node Ceph package udpate](img/proxmox-ceph-version-upgrade.png)

Je poursuis et mets à niveau les paquets sur les 2 autres nœuds.

J’ai un moniteur sur chaque nœud, donc je dois redémarrer chaque moniteur, un nœud à la fois :
```bash
systemctl restart ceph-mon.target
```

Je vérifie le statut Ceph entre chaque redémarrage :
```bash
ceph status
```

Une fois tous les moniteurs redémarrés, ils rapportent la dernière version, avec `ceph mon dump` :
- Avant : `min_mon_release 18 (reef)`
- Après : `min_mon_release 19 (squid)`

Je peux maintenant redémarrer les OSD, toujours un nœud à la fois. Dans ma configuration, j’ai un OSD par nœud :
```bash
systemctl restart ceph-osd.target
```

Je surveille le statut Ceph avec la WebGUI Proxmox. Après le redémarrage, elle affiche quelques couleurs fancy. J’attends juste que les PG redeviennent verts, cela prend moins d’une minute :
![Ceph storage status in Proxmox during the first OSD restart](img/proxmox-ceph-status-osd-restart.png)

Un avertissement apparaît : `HEALTH_WARN: all OSDs are running squid or later but require_osd_release < squid`

Maintenant tous mes OSD tournent sous Squid, je peux fixer la version minimum à celle‑ci :
```bash
ceph osd require-osd-release squid
```

ℹ️ Je n’utilise pas actuellement CephFS donc je n’ai pas à me soucier du daemon MDS (MetaData Server).

✅ Le cluster Ceph a été mis à niveau avec succès vers Squid (`19.2.3`).

---
## Vérifications

The prerequisites to upgrade the cluster to Proxmox VE 9 are now complete. Am I ready to upgrade? Not yet.

A small checklist program named **`pve8to9`** is included in the latest Proxmox VE 8.4 packages. The program will provide hints and warnings about potential issues before, during and after the upgrade process. Pretty handy isn't it?

Running the tool the first time give me some insights on what I need to do. The script checks a number of parameters, grouped by theme. For example, this is the VM guest section:
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

Let's review the problems it found:

```
FAIL: 1 custom role(s) use the to-be-dropped 'VM.Monitor' privilege and need to be adapted after the upgrade
```

Some time ago, in order to use Terraform with my Proxmox cluster, I created a dedicated role. This was detailed in that [post]({{< ref "post/3-terraform-create-vm-proxmox" >}}).

This role is using the `VM.Monitor` privilege, which is removed in Proxmox VE 9. Instead, new privileges  under `VM.GuestAgent.*` exist. So I remove this one and I'll add those once the cluster have been upgraded.

```
FAIL: systemd-boot meta-package installed. This will cause problems on upgrades of other boot-related packages. Remove 'systemd-boot' See https://pve.proxmox.com/wiki/Upgrade_from_8_to_9#sd-boot-warning for more information.
```

 Proxmox VE usually uses `systemd-boot` for booting only in some configurations which are managed by `proxmox-boot-tool`, the meta-package `systemd-boot` should be removed. The package was automatically shipped for systems installed from the PVE 8.1 to PVE 8.4, as it contained `bootctl` in bookworm.

If the `pve8to9` checklist script suggests it, the `systemd-boot` meta-package is safe to remove unless you manually installed it and are using `systemd-boot` as a bootloader:
```bash
apt remove systemd-boot -y
```


```
WARN: 1 running guest(s) detected - consider migrating or stopping them.
```

In HA setup, before updating a node, I put it in maintenance mode. This automatically moves the workload elsewhere. When this mode is disabled, the workload moves back to its previous location.

```
WARN: The matching CPU microcode package 'amd64-microcode' could not be found! Consider installing it to receive the latest security and bug fixes for your CPU.
        Ensure you enable the 'non-free-firmware' component in the apt sources and run:
        apt install amd64-microcode
```

It is recommended to install processor microcode for updates which can fix hardware bugs, improve performance, and enhance security features of the processor.

I add the `non-free-firmware` source to the current ones:
```bash
sed -i '/^deb /{/non-free-firmware/!s/$/ non-free-firmware/}' /etc/apt/sources.list
```

Then install the `amd64-microcode` package:
```bash
apt update
apt install amd64-microcode -y
```

After these small adjustments, am I ready yet? Let's find out by relaunching the `pve8to9` script.

⚠️ Don't forget to run the `pve8to9` on all nodes to make sure everything is good.

---
## Upgrade

🚀 Now everything is ready for the big move! Like I did for the minor update, I'll proceed one node at a time, keeping my VMs and CTs up and running.

### Set Maintenance Mode

First, I enter the node into maintenance mode. This will move existing workload on other nodes:
```bash
ha-manager crm-command node-maintenance enable $(hostname)
```

After issuing the command, I wait about one minute to give the resources the time to migrate.

### Change Source Repositories to Trixie

Since Debian Trixie, the `deb822` format is now available and recommended for sources. It is structured around key/value format. This offers better readability and security.

#### Debian Sources
```bash
cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: trixie trixie-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.debian.org/debian-security/
Suites: trixie-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
```

#### Proxmox Sources (without subscription)
```bash
cat > /etc/apt/sources.list.d/proxmox.sources << EOF
Types: deb 
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
```

#### Ceph Squid Sources (without subscription)
```bash
cat > /etc/apt/sources.list.d/ceph.sources << EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
```

#### Remove Old `bookworm` Source Lists

The lists for Debian `bookworm` in the old format must be removed:
```bash
rm -f /etc/apt/sources.list{,.d/*.list}
```

### Update the Configured `apt` Repositories

Refresh the repositories:
```bash
apt update
```
```plaintext
Get:1 http://security.debian.org/debian-security trixie-security InRelease [43.4 kB]
Get:2 http://deb.debian.org/debian trixie InRelease [140 kB]                                                                       
Get:3 http://download.proxmox.com/debian/ceph-squid trixie InRelease [2,736 B]        
Get:4 http://download.proxmox.com/debian/pve trixie InRelease [2,771 B]               
Get:5 http://deb.debian.org/debian trixie-updates InRelease [47.3 kB]
Get:6 http://security.debian.org/debian-security trixie-security/main Sources [91.1 kB]
Get:7 http://security.debian.org/debian-security trixie-security/non-free-firmware Sources [696 B]
Get:8 http://security.debian.org/debian-security trixie-security/main amd64 Packages [69.0 kB]
Get:9 http://security.debian.org/debian-security trixie-security/main Translation-en [45.1 kB]
Get:10 http://security.debian.org/debian-security trixie-security/non-free-firmware amd64 Packages [544 B]
Get:11 http://security.debian.org/debian-security trixie-security/non-free-firmware Translation-en [352 B]
Get:12 http://download.proxmox.com/debian/ceph-squid trixie/no-subscription amd64 Packages [33.2 kB]
Get:13 http://deb.debian.org/debian trixie/main Sources [10.5 MB] 
Get:14 http://download.proxmox.com/debian/pve trixie/pve-no-subscription amd64 Packages [241 kB]
Get:15 http://deb.debian.org/debian trixie/non-free-firmware Sources [6,536 B]
Get:16 http://deb.debian.org/debian trixie/contrib Sources [52.3 kB]
Get:17 http://deb.debian.org/debian trixie/main amd64 Packages [9,669 kB]
Get:18 http://deb.debian.org/debian trixie/main Translation-en [6,484 kB]
Get:19 http://deb.debian.org/debian trixie/contrib amd64 Packages [53.8 kB]
Get:20 http://deb.debian.org/debian trixie/contrib Translation-en [49.6 kB]
Get:21 http://deb.debian.org/debian trixie/non-free-firmware amd64 Packages [6,868 B]
Get:22 http://deb.debian.org/debian trixie/non-free-firmware Translation-en [4,704 B]
Get:23 http://deb.debian.org/debian trixie-updates/main Sources [2,788 B]
Get:24 http://deb.debian.org/debian trixie-updates/main amd64 Packages [5,412 B]
Get:25 http://deb.debian.org/debian trixie-updates/main Translation-en [4,096 B]
Fetched 27.6 MB in 3s (8,912 kB/s)              
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
666 packages can be upgraded. Run 'apt list --upgradable' to see them.
```

😈 666 packages, I'm doomed!

### Upgrade to Debian Trixie and Proxmox VE 9

Launch the upgrade:
```bash
apt-get dist-upgrade -y
```

During the process , you will be prompted to approve changes to configuration files and some service restarts. You may also be shown the output of changes, you can simply exit there by pressing `q`:
- `/etc/issue`: Proxmox VE will auto-generate this file on boot -> `No`
- `/etc/lvm/lvm.conf`: Changes relevant for Proxmox VE will be updated -> 
- `/etc/ssh/sshd_config`: Depending your setup -> `Inspect`
- `/etc/default/grub`: Only if you changed it manually -> `Inspect`
- `/etc/chrony/chrony.conf`: If you did not make extra changes yourself -> `Yes`

The upgrade took about 5 minutes, depending of the hardware.

At the end of the upgrade, restart the machine:
```bash
reboot
```
### Remove Maintenance Mode

Finally when the node (hopefully) comes back, you can disable the maintenance mode. The workload which was located on that machine will come back:
```bash
ha-manager crm-command node-maintenance disable $(hostname)
```

### Post-Upgrade Validation

- Check cluster communications:
```bash
pvecm status
```

- Verify storage mounts points

- Check Ceph cluster health 
```bash
ceph status
```

- Confirm VM operations, backups, and HA groups

HA groups have been removed at the profit of HA affinity rules. HA groups will be automatically migrated to HA rules.

- Disable PVE Enterprise repository

If you don't use the `pve-enterprise` repo, you can disable it:
```bash
sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.sources
```

🔁 This node is now upgraded to Proxmox VE 9. Proceed to other nodes.

## Post Actions

Once the whole cluster has been upgraded, proceed to post actions:
- Remove the Ceph cluster `noout` flag:
```bash
ceph osd unset noout
```

- Recreate PCI mapping

For the VM which I removed the host mapping at the beginning of the procedure, I can now recreate the mapping.

-  Add privileges for the Terraform role

During the check phase, I was advised to remove the privilege `VM.Monitor` from my custom role for Terraform. Now that new privileges have been added with Proxmox VE 9, I can assign them to that role:
- VM.GuestAgent.Audit
- VM.GuestAgent.FileRead
- VM.GuestAgent.FileWrite
- VM.GuestAgent.FileSystemMgmt
- VM.GuestAgent.Unrestricted

## Conclusion

🎉My Proxmox VE cluster is now is version 9!

The upgrade process was pretty smooth, without any downtime for my resources.

Now I have access to HA affinity rules, which I was needing for my OPNsense cluster.

As you could observe, I'm not maintaining my node up to date quite often. I might automate this next time, to keep them updated without any effort.



