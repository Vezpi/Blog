---
slug: homelab-page-preview
title: Prévisualisation de la page Homelab
description: Mon homelab compact avec Proxmox, Ceph, TrueNAS et OPNsense, les services qui y tournent et mon projet de migration vers Kubernetes.
date: 2026-10-18
draft: true
tags:
  - proxmox
  - ceph
  - truenas
  - opnsense
categories:
  - homelab
image: cover-26.webp
---

Mon homelab a commencé en 2013 avec le tout premier Raspberry Pi. Je voulais une machine bon marché pour apprendre Linux, et elle est devenue un petit NAS appelé Vezpibox. Le nom n'a pas particulièrement bien vieilli.

D'autres Raspberry Pi ont suivi, puis un mini-PC en 2019, quand j'ai commencé à expérimenter la virtualisation et Docker à la maison. Ce serveur unique a fini par poser problème : c'était à la fois mon terrain de jeu et la machine qui faisait tourner les services utiles. Casser un environnement de test est une chose. Emporter les lumières ou Internet avec lui en est une autre.

Aujourd'hui, le lab comprend un cluster Proxmox à trois nœuds, du stockage distribué, un NAS séparé et une paire de firewalls redondants. La plupart des applications tournent encore avec Docker Compose. Kubernetes fonctionne aussi, mais la migration des applications est la suite du projet, pas quelque chose que j'ai déjà terminé.

Cette page présente la configuration actuelle. Les articles détaillent les installations, les migrations et les erreurs occasionnelles.

*Dernière revue : octobre 2026.*

## Un lab dans une armoire

L'idée de départ était de construire un mini datacenter dans un placard. L'espace, le bruit, la consommation électrique et le budget comptaient tous, alors le setup s'est construit autour de machines compactes plutôt que de serveurs rackables.

![L'armoire du homelab ouverte et fermée, à côté de la cuisine. L'espace disponible fait partie de la conception, ce n'est pas une salle de serveurs extensible à volonté.](images/homelab-enclore-open-closed.png)

Le rack est un DeskPi RackMate T1. Il tient dans cette armoire étroite, avec des étagères et une multiprise pour utiliser l'espace disponible. Une fois la porte fermée, le lab disparaît dans l'appartement.

![L'agencement initial du rack. Les légendes du routeur et des HDD correspondent à l'ancien setup ; l'architecture actuelle du firewall et du stockage est décrite plus bas.](images/homelab-rack-legend.png)

Le refroidissement a demandé un peu d'attention aussi. Lors de la construction initiale, j'ai ajouté deux ventilateurs d'extraction de 40 mm au-dessus du meuble, avec des conduits en PVC et de la mousse pour limiter les vibrations. Deux ventilateurs de 80 mm dans le rack et un contrôleur PWM ont aidé à équilibrer le flux d'air et le bruit. Dans une armoire au milieu d'un espace de vie, faire rentrer les machines ne résout que la moitié du problème.

## Le lab en un coup d'œil

![Une vue synthétique du lab, de la connexion Internet au réseau, au compute et au stockage partagé.](images/homelab-overview-simple.png)

OPNsense gère le routage et le firewall, UniFi fournit le réseau filaire et le Wi-Fi, et les serveurs ont deux rôles principaux : Proxmox et Ceph hébergent les VM, tandis que TrueNAS fournit les fichiers partagés et les photos. Le schéma laisse volontairement de côté les VM individuelles, les segments réseau et les dépendances des applications.

## Le matériel

Les trois nœuds Proxmox sont des mini-PC différents :

| Nœud | Matériel | CPU | RAM |
| --- | --- | --- | --- |
| vertex | ASRock DeskMini A300 | Ryzen 3 2200G, 4 cœurs / 4 threads | 16 GB |
| apex | Minisforum HM50 | Ryzen 5 4500U, 6 cœurs / 6 threads | 32 GB |
| zenith | T-bao MN57 | Ryzen 7 5700U, 8 cœurs / 16 threads | 32 GB |

Chacun dispose d'un SSD de 256 GB pour le système, les ISO et les templates, ainsi que d'un NVMe de 1 TB pour Ceph. Une interface 1 Gbps transporte le trafic LAN et management, et une interface 2.5 Gbps séparée est dédiée à Ceph.

Une quatrième machine, `granite`, est un Beelink ME mini avec un Intel N200 et 12 GB de RAM. Elle fait tourner TrueNAS indépendamment du cluster Proxmox. Cette séparation ne sert pas qu'au stockage.

## Proxmox et deux rôles de stockage différents

Le cluster tourne maintenant sous Proxmox VE 9. Il héberge la VM applicative, le firewall principal, les VM Kubernetes et celle de Hermes Agent, ainsi que les environnements LXC pour l'administration et OpenCode.

Ceph tourne sur les trois mêmes nœuds physiques. Chacun apporte un NVMe, avec une réplication à trois copies sur le réseau dédié 2.5 Gbps. Il fournit le stockage partagé des VM et permet leur migration entre les nœuds Proxmox.

Cela ne rend pas chaque application hautement disponible. `dockerVM` reste une seule VM contenant la plupart de mes services. Le cluster en dessous ne supprime pas les pannes à l'intérieur de cette VM ou de ses conteneurs. Les NVMe grand public et le réseau de stockage imposent aussi des limites concrètes aux performances, qui restent un sujet d'investigation.

TrueNAS a un autre rôle. Son pool de stockage est un miroir de deux NVMe de 2 TB. Il fournit des partages SMB et NFSv4, notamment pour les données Nextcloud et les photos Immich. Ces partages sont distincts des disques des VM stockés sur Ceph.

L'ancien conteneur NFS sur Vertex n'existe plus. TrueNAS est désormais le NAS, mais reste une machine unique, pas un autre cluster HA. La réplication, un miroir et des snapshots ne doivent pas non plus être confondus avec une stratégie complète de sauvegarde hors site.

## Ne pas enfermer tout le réseau dans le même domaine de panne

OPNsense ne tourne plus sur le boîtier dédié d'origine. Il y a maintenant deux VM firewall :

- `cerbere-head1`, le principal, tourne sur Proxmox avec son disque sur Ceph.
- `cerbere-head2`, le secondaire, tourne sur TrueNAS avec son propre disque sur zvol.

CARP assure la redondance des passerelles, pfSync synchronise l'état des connexions et XMLRPC synchronise la configuration. Placer le secondaire sur TrueNAS évite de perdre les deux VM firewall quand le cluster Proxmox ou Ceph est indisponible. Cela ne rend pas tout le reste du réseau domestique redondant.

Le réseau physique utilise un UniFi Switch Lite 16 PoE, un Flex Mini 2.5G pour Ceph et un point d'accès U7 Pro Wall. L'application UniFi Network tourne dans un conteneur Docker sur `dockerVM`, pas comme plugin OPNsense.

Le réseau est découpé en segments management, utilisateurs, IoT, DMZ et lab, avec des réseaux supplémentaires pour le WAN, la synchronisation des firewalls, le heartbeat Proxmox, Ceph et l'accès VPN. OPNsense gère le routage et les règles de firewall. Dnsmasq fournit le DHCP et les noms locaux, tandis qu'Unbound assure la résolution DNS récursive et le filtrage avec les blocklists Hagezi. WireGuard permet l'accès distant depuis mes appareils mobiles.

### De HAProxy aux applications

HAProxy a remplacé Caddy sur OPNsense. Pour les services HTTPS hébergés dans Docker, le chemin principal est le suivant :

```text
HTTPS request → OPNsense HAProxy → Traefik on dockerVM → application
```

HAProxy distribue les connexions HTTPS en utilisant le SNI. Les services d'infrastructure empruntent une branche reverse proxy HTTPS séparée sur OPNsense ; ils ne passent pas tous par le Traefik de Docker.

Le plugin ACME d'OPNsense gère le renouvellement des certificats d'infrastructure. Sa tâche de renouvellement tourne uniquement sur le firewall principal : synchroniser la configuration du proxy ne revient donc pas à rendre le renouvellement des certificats redondant.

## Ce qui tourne ici

La plupart des services du quotidien utilisent encore une stack Docker Compose par application sur `dockerVM`.

| Usage | Services |
| --- | --- |
| Domotique | Home Assistant, Node-RED et InfluxDB |
| Fichiers, photos et mots de passe | Nextcloud, Immich et Vaultwarden |
| Médias | Jellyfin et la stack ARR |
| Code et publication | Gitea avec Actions, ce blog Hugo servi par Nginx et Umami |
| Administration | Semaphore UI, Portainer et l'application UniFi Network |
| Notifications | Ntfy |

Le blog fait lui aussi partie du lab. Son contenu commence sous forme de Markdown dans mon vault Obsidian, passe par Gitea Actions et est généré par Hugo. Le résultat est servi par Nginx sur la même VM applicative.

Les outils d'IA ont leurs propres environnements. Hermes Agent tourne dans une VM séparée, avec des profils pour l'orchestration, la recherche, l'ingénierie et la rédaction. OpenCode CLI reste dans un LXC. Ils m'aident dans le travail autour du lab ; je reste responsable de l'application des changements d'infrastructure.

## Faciliter la reconstruction

Le LXC `bastion` est mon environnement d'administration, avec SSH, Ansible, Terraform, OpenTofu, Helm et kubectl. Semaphore UI fournit une interface web pour lancer les automatisations.

Chaque semaine, Semaphore reconstruit le template cloud-init Ubuntu Noble et envoie une notification via Ntfy. Terraform provisionne les VM Kubernetes et Ansible les prépare avant le bootstrap manuel avec kubeadm.

Tout n'est pas encore automatisé. Les mises à jour des applications Docker restent manuelles, et reconstruire l'ensemble du lab depuis Git est encore un objectif, pas une capacité que je peux revendiquer aujourd'hui.

## Kubernetes fonctionne, la migration n'est pas terminée

Le cluster Kubernetes comprend six VM : trois nœuds control plane et trois workers. Il a été initialisé avec kubeadm et utilise Cilium. HAProxy répartit les accès à l'API Kubernetes, et des sessions BGP relient les workers Cilium à OPNsense.

Il n'héberge encore aucune application. La gateway Traefik et cert-manager restent à déployer. L'instance Traefik qui dessert les applications Docker est une installation distincte, et le fait que Ceph héberge les disques des VM ne signifie pas que Kubernetes possède déjà une storage class Ceph.

Le plan est de valider la gateway et les certificats, de définir le stockage et sa protection, puis de migrer les applications progressivement. GitOps viendra plus tard. Tout déplacer d'un coup irait à l'encontre de l'idée de conserver un environnement utile à la maison à côté d'un espace d'expérimentation.

## Toujours en chantier

Le setup est plus résilient que le serveur unique d'origine, mais il garde des limites évidentes. La plupart des applications dépendent de `dockerVM`, le NAS est une machine unique, et TrueNAS nécessite actuellement des redémarrages périodiques pour contourner une augmentation de l'utilisation mémoire non résolue. Le firewall secondaire vit sur cette machine : le problème ne concerne donc pas que le stockage des fichiers.

Cela fait aussi partie du lab. Cette page en donne la vue d'ensemble ; les articles racontent comment les différents éléments sont arrivés là et ce qui change ensuite.

## Les projets derrière cette page

- [Construire le serveur TrueNAS]({{< ref "post/18-create-nas-server-with-truenas" >}})
- [Déplacer la VM OPNsense secondaire sur TrueNAS]({{< ref "post/19-migrate-passive-opnsense-node-to-truenas" >}})
- [Remplacer Caddy par HAProxy sur OPNsense]({{< ref "post/23-install-haproxy-opnsense-replace-caddy" >}})
- [Préparer la migration de Docker Compose vers Kubernetes]({{< ref "post/24-roadmap-migrate-docker-applications-kubernetes" >}})
