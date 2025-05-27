---
title: Proxmox - Créer un Template de VM Cloud-Init
description: Découvrez comment créer un template de VM Ubuntu réutilisable avec cloud-init dans Proxmox pour accélérer et simplifier le déploiement de machines virtuelles.
date: 2025-03-31
draft: false
tags:
  - proxmox
  - cloud-init
categories:
  - homelab
---
## Intro

Créer un template de VM dans **Proxmox** avec **cloud-init** peut considérablement simplifier les déploiements de VM. Cet article décrit étape par étape la configuration d'un template de VM compatible **cloud-init** avec **Ubuntu** pour **Proxmox**.

Proxmox prend en charge cloud-init, un outil qui permet la configuration automatique des machines virtuelles immédiatement après leur provisionnement. Cela inclut la configuration du réseau, des clés SSH et d'autres paramètres initiaux.

Dans ce guide, nous allons créer un template de VM avec cloud-init activé, permettant ainsi un déploiement rapide de VM préconfigurées.

---
## Pourquoi Cloud-init ?

Cloud-init est un outil largement utilisé pour automatiser la configuration initiale des instances cloud. Il permet de configurer les clés SSH, le nom d'hôte, la configuration réseau et d'autres paramètres dès le premier démarrage, ce qui le rend idéal pour créer des templates de VM réutilisables en homelab ou en environnement de production.

[Documentation Proxmox Cloud-init](https://pve.proxmox.com/wiki/Cloud-Init_Support)

## Télécharger l'Image de l'OS

Tout d'abord, nous devons télécharger une image compatible cloud-init. Bien que Rocky Linux ait été initialement envisagé, le format `.img` n'était pas disponible et le format `.qcow2` posait problème. Nous allons donc utiliser l'image cloud d'Ubuntu.

Trouvez des images compatibles cloud dans le [Guide des images OpenStack](https://docs.openstack.org/image-guide/obtain-images.html).

Dans Proxmox, accédez à **Storage > ISO Images > Upload** pour uploader l'image téléchargée.
![Download window for ISO images in Proxmox](img/proxmox-download-iso-img.png)
## Créer la VM

Ensuite, on crée une VM en utilisant la ligne de commande (CLI) depuis le nœud Proxmox avec la commande suivantes :

```bash
qm create 900 \
   --memory 2048 \
   --core 1 \
   --net0 virtio,bridge=vmbr0 \
   --scsihw virtio-scsi-pci \
   --bios ovmf \
   --machine q35 \
   --efidisk0 ceph-workload:0,pre-enrolled-keys=0 \
   --name ubuntu-cloud
```

Cela crée une VM avec le support UEFI, 2GB de RAM, et un seul cœur. Le paramètre `efidisk0` spécifie une disque EFI.

### Importer le Disque OS

Maintenant, on importe l'image disque téléchargée comme disque primaire :

```bash
qm set 900 --scsi0 ceph-workload:0,import-from=/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img
```

### Configurer Cloud-init

On ajoute un lecteur CD cloud-init à la VM : 

```bash
qm set 900 --scsi1 ceph-workload:cloudinit
```

On définit l'ordre de démarrage pour donner la priorité au disque principal par rapport au CD :

```bash
qm set 900 --boot order=scsi0
```

On ajoute un port série pour l'accès console :

```bash
qm set 900 --serial0 socket --vga serial0
```

## Convertir en Template

Après avoir configuré la VM, on fait un clic droit dessus dans l'interface Web de Proxmox et sélectionnez `Convert to template`. La création du template est alors terminée.

## Conclusion

Cette méthode permet un déploiement rapide avec Proxmox de VM préconfigurées et cloud-init.

Le template peut désormais être utilisé pour générer de nouvelles instances avec des configurations personnalisées en fournissant les paramètres cloud-init nécessaires. Ceci est particulièrement utile pour déployer rapidement plusieurs instances avec des configurations de base similaires.