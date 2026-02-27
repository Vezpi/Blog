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
- Éditer le fichier `/lib/python3/dist-packages/truenas_installer/utils.py`
- Déplacer la ligne `await asyncio.sleep(1)` juste sous `for _try in range(tries):`
- Modifier la ligne 46 pour ajouter `+ 'p'` : 
`for partdir in filter(lambda x: x.is_dir() and x.name.startswith(device + 'p'), dir_contents):`
![Fichier corrigé dans l'installateur TrueNAS](img/truenas-iso-fix-installer.png)
- Quitter le shell et lancer l'installation sans redémarrer

L'installateur a finalement pu passer :
![Progression de l'installation de TrueNAS](img/truenas-iso-installation.png)

Une fois l'installation terminée, j'ai éteint la machine. Ensuite je l'ai installée dans mon rack au-dessus des 3 nœuds Proxmox VE. J'ai branché les deux câbles Ethernet depuis mon switch et je l'ai mise sous tension.

## Configurer TrueNAS

Par défaut, TrueNAS utilise DHCP. J'ai trouvé son adresse MAC dans mon interface UniFi et créé une réservation DHCP. Dans OPNsense, j'ai ajouté un override host pour Dnsmasq. Dans le plugin Caddy, j'ai configuré un domaine pour TrueNAS pointant vers cette IP, puis j'ai redémarré.

✅ Après quelques minutes, TrueNAS est maintenant disponible sur [https://nas.vezpi.com](https://nas.vezpi.com/).

### Paramètres généraux

Pendant l'installation, je n'ai pas défini de mot de passe pour truenas_admin. La page de connexion m'a forcé à en choisir un :
![Page de connexion TrueNAS pour changer le mot de passe de `truenas_admin`](img/truenas-login-page-change-password.png)

Une fois le mot de passe mis à jour, j'arrive sur le tableau de bord. L'interface donne une bonne impression au premier abord :
![Tableau de bord de TrueNAS](img/truenas-fresh-install-dashboard.png)

J'explore rapidement l'interface, la première chose que je fais est de changer le hostname en `granite` et de cocher la case en dessous pour hériter du domaine depuis DHCP :
![Configuration du hostname dans TrueNAS](img/truenas-config-change-hostname.png)

Dans les `General Settings`, je change les paramètres de `Localization`. Je mets le Console Keyboard Map sur `French (AZERTY)` et le Fuseau horaire sur `Europe/Paris`.

Je crée un nouvel utilisateur `vez`, avec le rôle `Full Admin` dans TrueNAS. J'autorise SSH uniquement pour l'authentification par clé, pas de mots de passe :
![Création d'un utilisateur dans TrueNAS](img/truenas-create-new-user.png)

Finalement je retire le rôle admin de `truenas_admin` et verrouille le compte.

### Création du pool

Dans TrueNAS, un pool est une collection de stockage créée en combinant plusieurs disques en un espace unifié géré par ZFS.

Dans la page `Storage`, je trouve mes `Disks`, où je peux confirmer que TrueNAS voit mon couple de NVMe :
![List of available disks in TrueNAS](img/truenas-storage-disks-unconfigured.png)

De retour sur le `Storage Dashboard`, je clique sur le bouton `Create Pool`. Je nomme le pool `storage` parce que je suis vraiment inspiré pour lui donner un nom :
![Assistant de création de pool dans TrueNAS](img/truenas-pool-creation-general.png)

Puis je sélectionne la disposition `Mirror` :
![Disk layout selection in the pool creation wizard in TrueNAS](img/truenas-pool-creation-layout.png)

J'explore rapidement les configurations optionnelles, mais les valeurs par défaut me conviennent : autotrim, compression, pas de dedup, etc. À la fin, avant de créer le pool, il y a une section `Review` :
![Review section of the pool creation wizard in TrueNAS](img/truenas-pool-creation-review.png)

Après avoir cliqué sur `Create Pool`, on m'avertit que tout sur les disques sera effacé, ce que je confirme. Finalement le pool est créé.

### Création des datasets

Un dataset est un système de fichiers à l'intérieur d'un pool. Il peut contenir des fichiers, des répertoires et des datasets enfants, il peut être partagé via NFS et/ou SMB. Il vous permet de gérer indépendamment les permissions, la compression, les snapshots et les quotas pour différents ensembles de données au sein du même pool de stockage.

#### Partage SMB

Créons maintenant mon premier dataset `files` pour partager des fichiers sur le réseau pour mes clients Windows, comme des ISOs, etc :
![Create a dataset in TrueNAS](img/truenas-create-dataset-files.png)

Lors de la création de datasets SMB dans SCALE, définissez le Share Type sur SMB afin que les bons ACL/xattr par défaut s'appliquent. TrueNAS me demande alors de démarrer/activer le service SMB :
![Invite à démarrer le service SMB dans TrueNAS](img/truenas-start-smb-service.png)

Depuis mon portable Windows, j'essaie d'accéder à mon nouveau partage `\\granite.mgmt.vezpi.com\files`. Comme prévu on me demande des identifiants.

Je crée un nouveau compte utilisateur avec permission SMB.

✅ Succès : je peux parcourir et copier des fichiers.

#### Partage NFS

Je crée un autre dataset : `media`, et un enfant `photos`. Je crée un partage NFS à partir de ce dernier.

Sur mon serveur NFS actuel, les fichiers photos sont possédés par `root` (gérés par _Immich_). Plus tard je verrai comment migrer vers une version sans root.

⚠️ Pour l'instant je définis, dans les `Advanced Options`, le `Maproot User` et le `Maproot Group` sur `root`. Cela équivaut à l'attribut NFS `no_squash_root`, le `root` local du client reste `root` sur le serveur, ne faites pas ça :
![NFS share permission in TrueNAS](img/truenas-dataset-photos-nfs-share.png)

✅ Je monte le partage NFS sur un client, cela fonctionne bien.

Après la configuration initiale, mes datasets du pool `storage` ressemblent à :

- `backups`
    - `duplicati` : backend de stockage [Duplicati](https://duplicati.com/)
    - `proxmox` : futur Proxmox Backup Server
- `cloud` : données `Nextcloud`
- `files` :
- `media`
    - `downloads`
    - `photos`
    - `videos`

J'ai mentionné les capacités VM dans mes exigences. Je ne couvrirais pas cela dans ce post, ce sera abordé la prochaine fois.

### Protection des données

Il est maintenant temps d'activer quelques fonctionnalités de protection des données :
![Data protection features in TrueNAS](img/truenas-data-protection-tab.png)

Je veux créer des snapshots automatiques pour certains de mes datasets, ceux qui me tiennent le plus à cœur : mes fichiers cloud et les photos.

Créons des tâches de snapshot. Je clique sur le bouton `Add` à côté de `Periodic Snapshot Tasks` :
- cloud : snapshots quotidiens, conserver pendant 2 mois
- photos : snapshots quotidiens, conserver pendant 7 jours
![Create periodic snapshot task in TrueNAS ](img/truenas-create-periodic-snapshot.png)

Je pourrais aussi configurer une `Cloud Sync Task`, mais Duplicati gère déjà les sauvegardes hors site.

---
## Utilisation de TrueNAS

Maintenant que mon instance TrueNAS est configurée, je dois planifier la migration des données depuis mon serveur NFS actuel vers TrueNAS.

### Migration des données

Pour chacun de mes partages NFS actuels, sur un client, je monte le nouveau partage NFS pour synchroniser les données :
```
sudo mkdir /new_photos
sudo mount 192.168.88.30:/mnt/storage/media/photos /new_photos
sudo rsync -a --info=progress2 /data/photo/ /new_photos
```

À la fin, je pourrais décommissionner mon ancien serveur NFS sur le LXC. La disposition des datasets après migration ressemble à ceci :
![Dataset layout in TrueNAS](img/truenas-datasets-layout.png)

### Application Android

Par curiosité, j'ai cherché sur le Play Store une application pour gérer une instance TrueNAS. J'ai trouvé [Nasdeck](https://play.google.com/store/apps/details?id=com.strtechllc.nasdeck&hl=fr&pli=1), qui est plutôt sympa. Voici quelques captures d'écran :
![Captures d'écran de l'application Nasdeck](img/nasdeck-android-app.png)

---
## Conclusion

Mon NAS est maintenant prêt à stocker mes données.

Je n'ai pas abordé les capacités VM car je vais bientôt les expérimenter pour installer Proxmox Backup Server en VM. De plus je n'ai pas configuré les notifications, je dois mettre en place une solution pour recevoir des alertes par email dans mon système de notification.

TrueNAS est un excellent produit. Il nécessite du matériel capable pour ZFS, mais l'expérience est excellente une fois configuré.

Étape suivante : déployer Proxmox Backup Server en tant que VM sur TrueNAS, puis revoir les permissions NFS pour passer Immich en mode sans root.