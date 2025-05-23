---
title: Bienvenue dans mon Homelab
layout: page
description: L'histoire derrière mon projet de homelab, d'un Raspberry Pi à un micro datacenter, où j'expérimente Proxmox, Kubernetes, l'automatisation et plus encore.
showToc: true
menu:
  main:
    name: Homelab
    weight: 20
    params:
      icon: flask
---
## Intro

Mon aventure homelab a commencé en 2013 avec un modeste Raspberry Pi, le tout premier modèle. J'avais besoin d'une machine bon marché pour mes premiers pas dans le monde de Linux. Elle m'a beaucoup aidé à me lancer dans cette technologie et m'a servi de NAS de base, merci Vezpibox (nom pourri, je sais).

En 2015, je suis passé à un Raspberry Pi 2, à la recherche de meilleures performances pour exécuter plusieurs applications comme XBMC (l'ancien nom de Kodi), CouchPotato, SickBeard, 

En 2018, le besoin de plus de RAM m'a conduit à un Raspberry Pi 3, me permettant d'exécuter encore plus d'applications. Mes trois petites machines fonctionnaient harmonieusement ensemble, dans un bordel bien ordonné.

Enfin, en 2019, mon nouveau travail m'a fait découvrir la virtualisation, avec les machines virtuelles et surtout Docker. Je voulais essayer ça à la maison, et j'ai franchi une étape importante avec un mini-PC compact mais puissant qui a posé les bases de mon homelab.

---
## Pourquoi un Homelab ?

Je voulais mon propre terrain de jeu, un espace où casser des objets était non seulement acceptable, mais encouragé. C'est le meilleur moyen d'apprendre à les réparer et, surtout, de vraiment comprendre leur fonctionnement.

Mon unique serveur était génial, mais tester quoi que ce soit de risqué dessus était devenu problématique. Il exécutait des services critiques comme la domotique ou le DNS, et croyez-moi, ne pas avoir de lumières ni d'internet était un incident majeur pour ma famille. Le serveur était devenu indispensable. Lorsqu'il était en panne, tout était en panne. Plus aussi fun.

Le premier grand défi que je me suis lancé a été de créer un cluster Kubernetes. Bien sûr, je pouvais en exécuter un sur un seul nœud, mais à quoi bon un cluster avec un seul nœud ? On pourrait dire qu'utiliser Kubernetes pour contrôler mes volets est excessif, et vous auriez raison. Mais ce n'était pas le sujet.

Je voulais aussi créer de nouvelles machines virtuelles à volonté, les reconstruire de zéro et appliquer les principes de l'Infrastructure as Code. J'aurais pu faire tout cela dans le cloud, mais je voulais un contrôle total.

Au départ, mon objectif était d'assurer la haute disponibilité de mes services existants. Un seul serveur ne suffisait pas. J'avais donc besoin d'un deuxième nœud. Mais dans la plupart des configurations haute disponibilité, trois nœuds constituent le compromis idéal. Et c'est ainsi que j'ai pu construire ce qui allait devenir mon homelab.

---
## Conception du Lab

Tout d'abord, il me fallait définir les fonctions de mon homelab. Je souhaitais qu'il héberge mes services existants de manière fiable, mais cela ne suffisait pas, je voulais un véritable terrain de jeu, capable de simuler un environnement d'entreprise plus complexe.
### Blueprint

Cela impliquait :
- **Haute disponibilité** : Trois nœuds pour garantir qu'aucun point de défaillance ne puisse tout interrompre.
- **Stockage distribué** : Redondance des données entre les nœuds, non seulement pour garantir la disponibilité, mais aussi pour apprendre le fonctionnement des systèmes de stockage d'entreprise.
- **Segmentation du réseau** : Plusieurs VLAN pour imiter les topologies de réseau réelles, isoler les services et pratiquer la mise en réseau avancée.

En résumé, je souhaitais construire un mini datacenter dans un placard.
### Contraintes

Bien sûr, la réalité ne correspond pas toujours aux ambitions. Voici ce à quoi je me suis heurté :
- **Espace** : Mon labo devait tenir dans une petite armoire de service cachée au milieu de mon appartement. Pas vraiment une salle de serveurs.
- **Bruit** : Le silence était crucial. Ce n'était pas un endroit caché dans un garage ou un sous-sol, mais en plein cœur de notre espace de vie.
- **Consommation électrique** : Fonctionnant 24/7, la consommation électrique devait être maîtrisée. Je ne pouvais pas me permettre de tripler ma facture d'électricité juste pour bricoler des machines virtuelles.
- **Budget** : Je n'allais pas dépenser des milliers d'euros pour du matériel professionnel. L'équilibre résidait dans la recherche d'un équipement d'occasion fiable et abordable.
- **Température** : Franchement, je n'y avais pas pensé… Les mini-PC ne chauffent pas beaucoup, mais le matériel réseau ? C'est une autre histoire. Leçon apprise.

---

## Présentation de l'Infrastructure

Décomposons les composants de mon homelab.
### Rack

Que serait un datacenter sans rack ? Honnêtement, je ne pensais pas qu'un rack pourrait tenir dans mon espace limité, jusqu'à ce que je découvre le [DeskPi RackMate T1](https://deskpi.com/products/deskpi-rackmate-t1-2).

Ce produit était parfait. Sa taille était idéale, sa qualité de fabrication impressionnante et sa conception modulaire m'a permis d'ajouter des accessoires supplémentaires, comme une multiprise et des étagères, pour compléter l'installation.
### Serveurs

J'avais déjà un serveur qui constituait la pierre angulaire de mon homelab et je souhaitais le conserver. Cependant, il présentait deux inconvénients majeurs :
- **Interface réseau unique** : Je voulais au moins deux cartes réseau pour la segmentation et la redondance du réseau.
- **Matériel vieillissant** : Il avait plus de cinq ans et ses options de compatibilité devenaient limitées.

Pour la carte réseau manquante, j'ai envisagé un adaptateur USB, mais j'ai finalement trouvé une meilleure solution : utiliser le port M.2 interne, initialement prévu pour un module Wi-Fi, pour connecter un adaptateur 2,5 Gbit/s. C'était la solution idéale.

Concernant le matériel, mon serveur actuel était équipé d'un Ryzen 3 2200G AM4 avec 16 Go de RAM DDR4. Pour garantir la cohérence et simplifier la compatibilité, j'ai décidé de conserver le socket AM4 pour tous les nœuds.

Les spécifications des deux nœuds supplémentaires étaient claires : un socket AM4 pour la cohérence, une faible consommation d'énergie, deux cartes réseau dont au moins une à 2,5 Gbit/s, et des options de stockage suffisantes, dont au moins un emplacement M.2 NVMe et une baie pour lecteur 2,5 pouces. L'AM4 étant un peu ancien, les modèles plus récents étaient exclus, ce qui était une bonne nouvelle pour mon budget, car j'ai pu acheter des mini-PC d'occasion.

Voici les spec de mes nœuds :

| **Node**  | **Vertex**              | **Apex**                | **Zenith**               |
| --------- | ----------------------- | ----------------------- | ------------------------ |
| **Model** | ASRock DeskMini A300    | Minisforum HM50         | T-bao MN57               |
| **CPU**   | AMD Ryzen 3 2200G 4C/4T | AMD Ryzen 5 4500U 6C/6T | AMD Ryzen 7 5700U 8C/16T |
| **TDP**   | 65W                     | 15W                     | 15W                      |
| **RAM**   | 16GB                    | 16GB                    | 32GB                     |
| **NIC**   | 1Gbps (+ 2.5Gbps)       | 1Gbps + 2.5Gbps         | 1Gbps + 2.5Gbps          |
| **M.2**   | 2                       | 1                       | 1                        |
| **2,5"**  | 2                       | 2                       | 1                        |
|           |                         |                         |                          |

Chaque nœud a la même configuration de disque : un SSD de 256 Go dans la baie 2,5 pouces pour le système d’exploitation et un disque NVMe de 1 To pour le stockage des données.
### Réseau

Pour le réseau, j’avais deux objectifs principaux : implémenter des VLAN pour la segmentation du réseau et gérer mon pare-feu pour un contrôle plus précis. Mes nœuds étant équipés de cartes réseau 2,5 Gbit/s, j’avais besoin de switchs capables de gérer ces débits, ainsi que de quelques ports Power over Ethernet (PoE) pour mon antenne Zigbee et ses futures fonctionnalités.

Au départ, j’étais attiré par le matériel MikroTik, idéal pour apprendre, mais la disposition de leurs switchs ne correspondait pas vraiment à ma configuration. En revanche, la gamme UniFi d’Ubiquiti était la solution de facilité, avec son interface utilisateur élégante et son esthétique matérielle impressionnante.

Pour le routeur, je ne voulais pas de passerelle UniFi. Je voulais quelque chose de plus personnalisable, avec lequel je pouvais bidouiller. Après quelques recherches, j’ai opté pour OPNsense plutôt que pfSense. Il paraît que c'est un peu plus adapté aux débutants, et jusqu'à présent, je ne l'ai pas regretté.

Voici la configuration réseau finale :
- **Routeur :** OPNsense fonctionnant sur un boîtier Topton sans ventilateur avec un processeur Intel N100, 16 Go de RAM et 4 ports 2,5 Gbit/s.
- **Swtich :** [UniFi Switch Lite 16 PoE](https://eu.store.ui.com/eu/en/category/switching-utility/products/usw-lite-16-poe), 8 ports PoE 1 Gbit/s et 8 ports non PoE.
- **Swtich :** [UniFi Flex Mini 2,5 G](https://eu.store.ui.com/eu/en/category/switching-utility/products/usw-flex-2-5g-5), 5 ports 2,5 Gbit/s, dont un port PoE entrant.
- **Point d'accès :** [UniFi U7 Pro Wall](https://eu.store.ui.com/eu/en/category/all-wifi/products/u7-pro-wall), Wi-Fi 7, 2,5 Gbit/s PoE+ entrant.
### Storage

While I don't have massive storage requirement, I still needed a flexible setup to either store my homelab workload and my personal media and documents.

Each Proxmox node is equipped with a **256GB SATA SSD** for the operating system, ISO files, and VM/LXC templates. For the workload storage, I added a **1TB NVMe drive** per node, which forms the basis of my **Ceph cluster**. This gives me distributed, redundant, and high-performance storage for VMs and containers, which allows live migration and high availability across the cluster.

Originally, my first server had two **1TB HDDs** installed internally. Because I needed a slot for the SSD, I moved them outside the case using **USB-to-SATA adapters** and reconnected them to the same node. These drives store my photos, Nextcloud documents and backups, less performance-critical data that doesn’t need to sit on Ceph. They are served on the network using a NFS server sitting in a LXC container on that node.
### Cooling

I quickly learned that my network gear was turning my closet into a mini furnace. Fortunately, I started the build in December, so the heat wasn’t too noticeable, but come summer, it was bound to become a real problem.

Options were limited, there was no way I was going to convince my wife that our servers needed a cooling system. Plus, it had to be silent. Not an easy combo.

The best solution I came up with was to drill two 40mm holes above the kitchen cabinet. I ran PVC pipes through the wall and installed two small fans, each cushioned with foam to minimize vibrations and keep noise down.

Inside the rack, I also added two 80mm fans to help with airflow. To keep everything quiet, I hooked up a PWM controller to regulate fan speeds, striking a balance between airflow and silence.
### Photos

Here what is look like

![homelab-rack-legend.png](img/homelab-rack-legend.png)
![homelab-enclore-open-closed.png](img/homelab-enclore-open-closed.png)

---
## Software Stack

With the hardware foundation set, the next step was to decide what software would orchestrate everything, the real engine behind every experiment, deployment, and learning opportunity.
### Hypervisor

At the core of my setup is a 3-node Proxmox VE 8 cluster, a KVM-based hypervisor that also supports LXC containers. Built on Debian, it provides essential features like live migration, HA, and seamless Ceph integration right out of the box.

For now, I’m primarily running just one VM and one LXC container. The VM is essentially a clone of my old physical server, hosting most of my applications as Docker containers. The LXC container serves as a simple jump server.
### Network

The objective for my network was to implement VLANs for segmentation and manage firewall rules directly to simulate more complex setups. 

#### Router and Firewall

At the heart of this network is **OPNsense**, running on a dedicated fanless box. The ISP router is in bridge mode, passing all traffic to OPNsense, which handles all routing and firewall duties. Inter-VLAN traffic is restricted, explicit firewall rules are mandatory, only the management VLAN having access to other segments.  
#### L2 Network

Layer 2 networking is managed by **UniFi switches**, chosen for their sleek UI and simplicity. The UniFi controller, which manages the devices configuration, runs as a plugin on OPNsense.

The access point is broadcasting 2 SSIDs, one for my family's laptops and cellulars (5 and 6Ghz) and the other only in 2.4Ghz for everything else (IoT, vacuum, AC, printer, Chromecast, etc.)

A 2.5Gbps UniFi switch is dedicated to Ceph storage communications, isolating storage traffic to prevent interference with other networks.

I set up **LACP** (Link Aggregation) between the router and the main switch at 1Gbps, hoping to double bandwidth. Reality check: a single session will only use one link, meaning that a single download will still cap at 1Gbps.
#### VLANs

To segment traffic, I divided the network into several VLANs:

| Name      | ID   | Purpose                      |
| --------- | ---- | ---------------------------- |
| User      | 13   | Home network                 |
| IoT       | 37   | IoT and untrusted equipments |
| DMZ       | 55   | Internet facing              |
| Lab       | 66   | Lab network, trusted         |
| Heartbeat | 77   | Proxmox cluster heartbeat    |
| Mgmt      | 88   | Management                   |
| Ceph      | 99   | Ceph                         |
| VPN       | 1337 | Wireguard network            |

Each VLAN has its own DHCP pool managed by OPNsense, excepted the Heartbeat and Ceph ones.
#### DNS

DNS is structured in two layers within OPNsense:
- ADguard Home:  ads and trackers filters, serves every client on the network over plain DNS on port 53
- Unbound DNS: recursive DNS, serves only the ADguard Home DNS service locally
#### Reverse Proxy

**Caddy** runs as a plugin on OPNsense and acts as the main entry point for web traffic. It routes requests based on subdomains and automatically handles HTTPS certificates and drops internal service access coming from the WAN.

Most services are still managed by a **Traefik** instance running on my VM. In those cases, Caddy simply forwards HTTPS requests directly to Traefik.

This two-layer proxy setup centralizes SSL certificate management in **Caddy** while preserving flexible and dynamic routing internally with **Traefik**.
#### VPN

For secure remote access, I configured **WireGuard** on OPNsense. This lightweight VPN provides encrypted connectivity to my lab from anywhere, allowing management of all my services without exposing them all directly to the internet.
#### Network Diagram

![homelab-network-schema.png](img/homelab-network-schema.png)
### Application

Let's dive into the fun part! What started as a modest setup meant to serve a few personal needs quickly turned into a full ecosystem of open source services, each solving a specific need or just satisfying curiosity.

Here’s an overview of what’s currently running in my homelab:
- **Home Assistant**: Central hub for home automation, integrating smart devices and routines.
- **Vaultwarden**: Lightweight alternative to Bitwarden for managing and syncing passwords securely.
- **Nextcloud**: Self-hosted cloud storage.
- **Gitea**:  Git repository solution for managing my code and projects.
- **Blog**: My Hugo-based personal blog, which you are reading now.
- **Immich** – Photo and video management app, similar to Google Photos.
- **Jellyfin**: Media server for streaming movies and shows.
- **ARR Stack**: Automated media acquisition tools. (Radarr, Sonarr, Torrent, etc.)
- **Duplicati**: Encrypted backup solution for my important data and configs.
- **Prometheus**: Monitoring and metrics collection tool, used with Grafana for dashboards.
- **Portainer**: Web interface for managing Docker containers and stacks.
- **Umami**: Privacy-focused analytics for tracking visits on my blog.
- **phpIPAM**: IP address management tool for keeping my VLANs and subnets organized.
#### Docker

Docker was the real game-changer in my self-hosted journey. Before containers, managing multiple services on a single server felt like a constant battle with dependencies and conflicts. Now, every service runs neatly, managed with Docker Compose inside a single VM. Traefik dynamically handles reverse proxy, simplifying access and SSL.
#### Kubernetes

My next big challenge is to take container orchestration to the next level. While Docker Swarm could meet the technical need, my primary goal is to gain hands-on experience with Kubernetes, and there’s no better way to learn than by applying it to real-world use cases.

---

## Final Words

Thank you for taking the time to read through my homelab journey!

Building and refining this setup has been a great source of learning and fun, and I’m always looking for new ways to improve it.

If you’ve got ideas, feedback, better solutions, or just want to share your own setup, I’d love to hear from you. Drop me a message, challenge my choices, or inspire me with your story!
