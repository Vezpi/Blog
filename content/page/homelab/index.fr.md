---
title: Bienvenue dans mon Homelab
layout: page
description: Mon homelab compact avec Proxmox, Ceph, TrueNAS et OPNsense, les services qui y tournent et mon projet de migration vers Kubernetes.
showToc: true
menu:
  main:
    name: Homelab
    weight: 20
    params:
      icon: flask
---

Mon homelab a commencé en 2013 avec le tout premier Raspberry Pi. Je voulais une machine bon marché pour apprendre Linux, et elle est devenue un petit NAS appelé Vezpibox. Le nom n'a pas particulièrement bien vieilli.

D'autres Raspberry Pi ont suivi, puis un mini-PC en 2019, quand j'ai commencé à expérimenter la virtualisation et Docker à la maison. Ce serveur unique a fini par poser problème : c'était à la fois mon terrain de jeu et la machine qui faisait tourner les services utiles. Casser un environnement de test est une chose. Couper aussi les lumières ou Internet en est une autre.

Aujourd'hui, le lab comprend un cluster Proxmox à trois nœuds, du stockage distribué, un NAS séparé et une paire de firewalls redondants. La plupart des applications tournent encore avec Docker Compose. Kubernetes fonctionne aussi, mais la migration des applications est la suite du projet, pas quelque chose que j'ai déjà terminé.

*Dernière revue : octobre 2026.*

## Un lab dans une armoire

L'idée de départ était de construire un mini datacenter dans un placard. L'espace, le bruit, la consommation électrique et le budget comptaient tous, alors le setup s'est construit autour de machines compactes plutôt que de serveurs rackables.

![L'armoire du homelab ouverte et fermée, à côté de la cuisine. L'espace disponible fait partie de la conception, ce n'est pas une salle de serveurs extensible à volonté.](images/homelab-enclore-open-closed.png)

Le rack est un DeskPi RackMate T1. Il tient dans cette armoire étroite, avec des étagères et une multiprise pour utiliser l'espace disponible. Une fois la porte fermée, le lab disparaît dans l'appartement.

![L'agencement initial du rack. Les légendes du routeur et des HDD correspondent à l'ancien setup ; l'architecture actuelle du firewall et du stockage est décrite plus bas.](images/homelab-rack-legend.png)

Le refroidissement a demandé un peu d'attention aussi. Lors de la construction initiale, j'ai ajouté deux ventilateurs d'extraction de 40 mm au-dessus du meuble, avec des conduits en PVC et de la mousse pour limiter les vibrations. Deux ventilateurs de 80 mm dans le rack et un contrôleur PWM ont aidé à équilibrer le flux d'air et le bruit. Dans une armoire au milieu d'un espace de vie, faire rentrer les machines ne résout que la moitié du problème.

## Le matériel

Les trois nœuds Proxmox sont des mini-PC différents :

| Nœud | Matériel | CPU | RAM |
| --- | --- | --- | --- |
| vertex | ASRock DeskMini A300 | Ryzen 3 2200G, 4 cœurs / 4 threads | 16 GB |
| apex | Minisforum HM50 | Ryzen 5 4500U, 6 cœurs / 6 threads | 32 GB |
| zenith | T-bao MN57 | Ryzen 7 5700U, 8 cœurs / 16 threads | 32 GB |

Chacun dispose d'un SSD de 256 GB pour le système, les ISO et les templates, ainsi que d'un NVMe de 1 TB pour Ceph. Une interface 1 Gbps transporte le trafic LAN et management, et une interface 2.5 Gbps séparée est dédiée à Ceph.

Une quatrième machine, `granite`, est un Beelink ME mini avec un Intel N200 et 12 GB de RAM. Elle fait tourner TrueNAS indépendamment du cluster Proxmox. Cette séparation ne sert pas qu'au stockage.

## Plateforme

![Une sélection de VM dans le cluster Proxmox, avec TrueNAS à côté. Les VM OPNsense Master et Backup forment une paire HA répartie entre les deux plateformes d'hébergement.](images/homelab-hosting-overview.png)

### Proxmox et Ceph

[Proxmox VE 9]({{< ref "post/14-proxmox-cluster-upgrade-8-to-9-ceph" >}}) fournit la couche de virtualisation sur les trois mini-PC. Ceph tourne sur les mêmes nœuds physiques, avec un NVMe par nœud et une réplication à trois copies sur le réseau dédié 2.5 Gbps. Il fournit le stockage partagé des VM et permet de déplacer les workloads entre les nœuds Proxmox.

C'est la base du lab, mais cela ne rend pas chaque application hautement disponible. Une VM peut toujours subir une panne interne, et une application peut casser dans une VM parfaitement saine. Les NVMe grand public et le réseau de stockage imposent aussi des limites concrètes aux performances.

### TrueNAS

[TrueNAS]({{< ref "post/18-create-nas-server-with-truenas" >}}) tourne sur `granite`, en dehors du cluster Proxmox. Son pool de stockage est un miroir de deux NVMe de 2 TB, avec des partages SMB pour les fichiers et NFSv4 pour les données applicatives. Les fichiers Nextcloud et les photos Immich vivent ici plutôt qu'à l'intérieur de leurs conteneurs.

Son rôle est différent de celui de Ceph : Ceph héberge les disques des VM, tandis que TrueNAS fournit les fichiers partagés et les photos. L'ancien conteneur NFS sur Vertex n'existe plus. TrueNAS héberge aussi la [VM OPNsense secondaire]({{< ref "post/19-migrate-passive-opnsense-node-to-truenas" >}}), avec son disque sur un zvol, pour garder ce firewall en dehors du domaine de panne de Proxmox et Ceph.

### dockerVM

La plupart des applications tournent actuellement sur `dockerVM`, avec [une stack Docker Compose par application]({{< ref "post/16-how-I-deploy-application" >}}). Le disque de la VM est sur Ceph, tandis que les services qui ont besoin de données partagées montent les partages TrueNAS correspondants.

Docker reste la plateforme applicative du quotidien. C'est aussi un point de concentration : la plupart des services dépendent de cette seule VM, les mises à jour restent manuelles, et restaurer une application n'est pas la même chose que redémarrer sa VM ailleurs dans le cluster.

### Kubernetes

Kubernetes est [la plateforme prévue pour prendre le relais de Compose]({{< ref "post/24-roadmap-migrate-docker-applications-kubernetes" >}}). Ses six VM tournent déjà sur Proxmox : trois nœuds control plane et trois workers, initialisés avec kubeadm et connectés avec Cilium. [Terraform provisionne les VM et Ansible les prépare]({{< ref "post/25-automate-kubernetes-vms-terraform-ansible" >}}) avant le bootstrap manuel du cluster.

Les fondations fonctionnent, mais aucune application n'y a encore été déplacée. La gateway Traefik de Kubernetes et cert-manager restent à déployer, puis il faudra travailler sur le stockage et sa protection avant la migration progressive. GitOps viendra plus tard. L'instance Traefik qui dessert les applications Docker aujourd'hui est une installation distincte.

## Réseau

### UniFi pour le réseau filaire et le Wi-Fi

Le réseau physique utilise un UniFi Switch Lite 16 PoE, un Flex Mini 2.5G dédié à Ceph et un point d'accès U7 Pro Wall. L'application UniFi Network tourne dans un conteneur sur `dockerVM` et gère ces équipements.

Les [VLAN]({{< ref "post/11-proxmox-cluster-networking-sdn" >}}) séparent les appareils des utilisateurs, les équipements IoT, le lab, la DMZ et le management. Des réseaux sont également dédiés au WAN, à la synchronisation des firewalls, au heartbeat Proxmox, à Ceph et à l'accès VPN. UniFi transporte le trafic ; OPNsense décide de ce qui peut passer entre les segments routés.

### OPNsense pour le routage et le firewall

Les [deux VM firewall]({{< ref "post/15-migration-opnsense-proxmox-highly-available" >}}) sont `cerbere-head1`, le Master sur Proxmox, et `cerbere-head2`, le Backup sur TrueNAS. CARP assure la redondance des passerelles, pfSync synchronise l'état des connexions et XMLRPC synchronise la configuration.

Héberger le Backup sur TrueNAS permet de ne pas perdre les deux VM firewall quand le cluster Proxmox ou Ceph est arrêté. Cela améliore la résilience du firewall, sans prétendre que chaque switch, câble ou autre composant est lui aussi redondant.

Dnsmasq fournit le DHCP et les noms locaux. Unbound assure la résolution DNS récursive avec les blocklists Hagezi, et WireGuard permet l'accès distant depuis mes appareils mobiles.

[HAProxy tourne sur OPNsense]({{< ref "post/23-install-haproxy-opnsense-replace-caddy" >}}) et distribue les connexions HTTPS entrantes. Les services hébergés dans Docker passent par Traefik sur `dockerVM` ; les interfaces d'infrastructure utilisent une branche reverse proxy HTTPS séparée sur OPNsense. Le plugin ACME d'OPNsense gère le renouvellement des certificats d'infrastructure sur le firewall principal.

## Applications

Les applications ci-dessous tournent encore sur `dockerVM`. Certaines sont des services utilisés à la maison, tandis que d'autres servent au réseau, à l'automatisation ou au blog lui-même.

| Application | Ce que j'en fais |
| --- | --- |
| Home Assistant | Intégrer les appareils connectés et faire tourner la domotique. |
| Node-RED | Construire visuellement des flows d'automatisation avec Home Assistant, notamment pour le [contrôle de la climatisation Daikin]({{< ref "post/6-ac-automation-home-assistant-node-red" >}}). |
| InfluxDB | Stocker les données historiques de Home Assistant. |
| Nextcloud | Synchroniser des fichiers et collaborer, avec les données sur un partage TrueNAS. |
| Immich | Gérer les photos et vidéos, avec la photothèque sur TrueNAS. |
| Vaultwarden | Héberger un gestionnaire de mots de passe léger, compatible avec Bitwarden. |
| Jellyfin | Servir la bibliothèque multimédia. |
| ARR stack | Automatiser l'acquisition et l'organisation des médias avec Sonarr, Radarr, Prowlarr et les outils associés. |
| Gitea | Héberger les dépôts Git et exécuter les workflows CI/CD avec Gitea Actions. |
| Hugo blog | Générer ce site statique à partir du Markdown dans Obsidian, puis le servir avec Nginx. |
| Umami | Collecter les statistiques de fréquentation du blog. |
| Traefik | Acheminer les requêtes vers les applications Docker derrière OPNsense HAProxy et assurer la terminaison de leurs connexions HTTPS. |
| UniFi Network Application | Gérer les switchs et le point d'accès Wi-Fi. |
| [Semaphore UI]({{< ref "post/17-semaphore-ui-interface-ansible-terraform" >}}) | Lancer les automatisations Ansible et Terraform depuis une interface web. |
| Portainer | Inspecter et gérer les conteneurs Docker, les stacks et les logs. |
| [Ntfy]({{< ref "post/5-notification-system-gotify-vs-ntfy" >}}) | Envoyer des notifications push depuis les déploiements, les exécutions d'automatisations et les services multimédias. |

## Documentation avec Obsidian

Obsidian est l'endroit où je conserve la documentation du lab. Les projets, les journaux de tâches, les références techniques et l'inventaire de l'infrastructure vivent dans le même vault, sous forme de fichiers Markdown locaux versionnés dans Gitea. J'y garde à la fois ce qui tourne et la manière dont c'est arrivé là, y compris les décisions et les dépannages derrière un changement.

C'est aussi là que j'écris ce blog. Les articles commencent dans le dossier `Blog/` du vault, et [Gitea Actions et Hugo transforment ces notes en site]({{< ref "post/2-blog-deployment-obisidan-hugo-gitea-actions" >}}), celui que vous lisez. Seul le contenu du blog est envoyé au site ; les notes de projet et l'inventaire restent dans le vault.

Obsidian tourne lui-même en local, ce n'est pas un service supplémentaire sur `dockerVM`. Gitea héberge le dépôt du vault, tandis que Hugo génère le site public.

## Toujours en chantier

Le setup est plus résilient que le serveur unique d'origine, mais il garde des limites évidentes. La plupart des applications dépendent de `dockerVM`, le NAS est une machine unique, et TrueNAS nécessite actuellement des redémarrages périodiques pour contourner une augmentation de l'utilisation mémoire non résolue. Le firewall secondaire vit sur cette machine : le problème ne concerne donc pas que le stockage des fichiers.

Cela fait aussi partie du lab. Cette page en donne la vue d'ensemble ; les articles racontent comment les différents éléments sont arrivés là et ce qui change ensuite.
