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

Mon aventure homelab a commencé en 2013 avec un modeste Raspberry Pi, le tout premier modèle. J'avais besoin d'une machine bon marché pour mes premiers pas dans le monde de Linux. Elle m'a beaucoup aidé à m’initier dans cette technologie et m'a servi de NAS de base, merci Vezpibox (nom pourri, je sais).

En 2015, je suis passé à un Raspberry Pi 2, à la recherche de meilleures performances pour exécuter plusieurs applications comme XBMC (l'ancien nom de Kodi), CouchPotato, SickBeard... 😇

En 2018, le besoin de plus de RAM m'a conduit à un Raspberry Pi 3, me permettant d'exécuter encore plus d'applications. Mes trois petites machines fonctionnaient harmonieusement ensemble, dans un bordel bien ordonné.

Enfin, en 2019, mon nouveau travail m'a fait découvrir la virtualisation, avec les machines virtuelles et surtout Docker. Je voulais essayer ça à la maison, et je suis passé a la vitesse supérieure avec un mini-PC compact mais assez puissant qui a posé les bases de mon homelab.

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
### Stockage

Bien que je n'aie pas besoin d'un stockage important, il me fallait une configuration flexible pour stocker les datas de mon homelab, ainsi que mes médias et documents personnels.

Chaque nœud Proxmox est équipé d'un SSD SATA de 256 Go pour le système d'exploitation, les fichiers ISO et les templates VM/LXC. Pour le stockage des datas, j'ai ajouté un disque NVMe de 1 To par nœud, qui constitue la base de mon cluster Ceph. Cela me permet d'obtenir un stockage distribué, redondant et performant pour les VM et les conteneurs, ce qui permet une migration à chaud et une haute disponibilité sur l'ensemble du cluster.

À l'origine, mon premier serveur était équipé de deux disques durs de 1 To installés en interne. Comme j'avais besoin d'un emplacement pour le SSD, je les ai déplacés hors du boîtier à l'aide d'adaptateurs USB vers SATA et les ai reconnectés au même nœud. Ces disques stockent mes photos, mes documents Nextcloud et mes sauvegardes, des données moins critiques pour les performances qui n'ont pas besoin de rester sur Ceph. Ils sont servis sur le réseau à l’aide d’un serveur NFS situé dans un conteneur LXC sur ce nœud.
### Refroidissement

J'ai vite compris que mon équipement réseau transformait mon placard en mini-fournaise. Heureusement, j'ai commencé la construction en décembre, donc la chaleur n'était pas trop perceptible, mais avec l'été, elle allait forcément devenir un vrai problème.

Les options étaient limitées, impossible de convaincre ma femme que nos serveurs avaient besoin d'un système de refroidissement. De plus, il fallait que ce soit silencieux. Une combinaison difficile.

La meilleure solution que j'ai trouvée a été de percer deux trous de 40 mm au-dessus du meuble de cuisine. J'ai fait passer des tuyaux en PVC dans le mur et installé deux petits ventilateurs, chacun recouvert de mousse pour minimiser les vibrations et le bruit.

À l'intérieur du rack, j'ai également ajouté deux ventilateurs de 80 mm pour améliorer la circulation de l'air. Pour un fonctionnement silencieux, j'ai branché un contrôleur PWM pour réguler la vitesse des ventilateurs, trouvant ainsi un équilibre entre circulation d'air et silence.
### Photos

Voici à quoi ça ressemble :

![homelab-rack-legend.png](img/homelab-rack-legend.png)
![homelab-enclore-open-closed.png](img/homelab-enclore-open-closed.png)

---
## Stack Logicielle

Une fois les fondations matérielles posées, l'étape suivante consistait à déterminer la partie software qui orchestrerait l'ensemble, véritable moteur de chaque expérience, déploiement et opportunité d'apprentissage.
### Hyperviseur

Au cœur de ma configuration se trouve un cluster Proxmox VE 8 à 3 nœuds, un hyperviseur basé sur KVM prenant également en charge les conteneurs LXC. Basé sur Debian, il offre des fonctionnalités essentielles telles que la migration à chaud, la haute disponibilité et l'intégration de Ceph, prêtes à l'emploi.

Pour l'instant, j'utilise principalement une seule VM et un seul conteneur LXC. La VM est en quelque sorte un clone de mon ancien serveur physique, hébergeant la plupart de mes applications sous forme de conteneurs Docker. Le conteneur LXC sert de simple jump server.
### Réseau

L'objectif de mon réseau était d'implémenter des VLAN pour la segmentation et de gérer directement les règles de pare-feu afin de simuler des configurations plus complexes.
#### Routeur et pare-feu

Au cœur de ce réseau se trouve **OPNsense**, fonctionnant dans un boîtier dédié sans ventilateur. Le routeur du FAI est en mode pont et transmet tout le trafic à OPNsense, qui gère toutes les fonctions de routage et de pare-feu. Le trafic inter-VLAN est restreint, des règles de pare-feu explicites sont obligatoires, et seul le VLAN de management a accès aux autres segments.
#### Réseau L2

Le réseau de couche 2 est géré par des **switchs UniFi**, choisis pour leur interface utilisateur épurée et leur simplicité. Le contrôleur UniFi, qui gère la configuration des appareils, fonctionne en tant que plugin sur OPNsense.

Le point d'accès diffuse deux SSID : un pour les ordinateurs et téléphones portables de ma famille (5 et 6 GHz) et l'autre uniquement en 2,4 GHz pour tout le reste (IoT, aspirateur, climatisation, imprimante, Chromecast, etc.).

Un switch UniFi 2,5 Gbit/s est dédié aux communications de Ceph, isolant le trafic de stockage pour éviter les interférences avec d'autres réseaux.

J'ai configuré **LACP** (agrégation de liens) entre le routeur et le commutateur principal à 1 Gbit/s, dans l'espoir de doubler la bande passante. En réalité : une session n'utilise qu'un seul lien, ce qui signifie qu'un téléchargement unique est toujours plafonné à 1 Gbit/s.
#### VLAN

Pour segmenter le trafic, j'ai divisé le réseau en plusieurs VLAN :

| Nom       | ID   | Rôle                         |
| --------- | ---- | ---------------------------- |
| User      | 13   | Home network                 |
| IoT       | 37   | IoT and untrusted equipments |
| DMZ       | 55   | Internet facing              |
| Lab       | 66   | Lab network, trusted         |
| Heartbeat | 77   | Proxmox cluster heartbeat    |
| Mgmt      | 88   | Management                   |
| Ceph      | 99   | Ceph                         |
| VPN       | 1337 | Wireguard network            |

Chaque VLAN possède son propre pool DHCP géré par OPNsense, à l'exception des VLAN Heartbeat et Ceph.
#### DNS

Au sein d'OPNsense, le DNS est structuré en deux couches :
- ADguard Home : filtres de publicités et de traqueurs, sert chaque client du réseau sur le port DNS standard 53.
- Unbound DNS : DNS récursif, distribue uniquement le service DNS ADguard Home en interne.
#### Reverse Proxy

**Caddy** fonctionne comme plugin sur OPNsense et sert de point d'entrée principal pour le trafic web. Il achemine les requêtes en fonction des sous-domaines, gère automatiquement les certificats HTTPS et drop les accès aux services internes provenant du WAN.

La plupart des services sont toujours gérés par une instance **Traefik** exécutée sur ma VM. Dans ce cas, Caddy transfère simplement les requêtes HTTPS directement à Traefik.

Cette configuration de proxy à deux couches centralise la gestion des certificats SSL dans **Caddy** tout en préservant un routage interne flexible et dynamique avec **Traefik**.
#### VPN

Pour un accès distant sécurisé, j'ai configuré **WireGuard** sur OPNsense. Ce VPN léger fournit une connectivité chiffrée à mon lab où que je sois, permettant ainsi de gérer tous mes services sans les exposer directement à Internet.
#### Schéma Réseau

![homelab-network-schema.png](img/homelab-network-schema.png)
### Application

Plongeons dans la partie fun ! Ce qui a commencé comme une modeste configuration destinée à répondre à quelques besoins personnels s'est rapidement transformé en un écosystème complet de services open source, chacun répondant à un besoin spécifique ou simplement à la curiosité.

Voici un aperçu de ce qui fonctionne actuellement dans mon homelab :
- **Home Assistant** : Plateforme centralisée pour la domotique, intégrant des appareils connectés et des routines.
- **Vaultwarden** : Alternative légère à Bitwarden pour gérer et synchroniser les mots de passe en toute sécurité.
- **Nextcloud** : Stockage cloud self-hosted.
- **Gitea** : Solution de dépôt Git pour gérer mon code et mes projets.
- **Blog** : Mon blog personnel basé sur Hugo, que vous lisez actuellement.
- **Immich** : Application de gestion de photos et de vidéos, similaire à Google Photos.
- **Jellyfin** : Serveur multimédia pour le streaming de films et de séries.
- **ARR Stack** : Outils d'acquisition multimédia automatisés. (Radarr, Sonarr, Torrent, etc.)
- **Duplicati** : Solution de sauvegarde chiffrée pour mes données et configurations importantes.
- **Prometheus** : Outil de surveillance et de collecte de métriques, utilisé avec Grafana pour les tableaux de bord.
- **Portainer** : Interface web pour la gestion des conteneurs et des stacks Docker.
- **Umami** : Analyses axées sur la confidentialité pour le suivi des visites sur mon blog.
- **phpIPAM** : Outil de gestion des adresses IP pour l'organisation de mes VLAN et sous-réseaux.
#### Docker

Docker a véritablement révolutionné mon aventure homelab. Avant les conteneurs, gérer plusieurs services sur un seul serveur était une bataille constante avec les dépendances et les conflits. Aujourd'hui, chaque service fonctionne parfaitement, géré par Docker Compose au sein d'une seule VM. Traefik gère dynamiquement le reverse proxy, simplifiant ainsi l'accès et les certificats SSL.
#### Kubernetes

Mon prochain grand défi est de faire passer l'orchestration des conteneurs au niveau supérieur. Si Docker Swarm pouvait répondre à ce besoin technique, mon objectif principal est d'acquérir une expérience pratique de Kubernetes, et il n'y a pas de meilleur moyen d'apprendre que de l'appliquer à des cas d'utilisation concrets.

---

## Derniers Mots

Merci d'avoir pris le temps de lire mon aventure homelab !

Construire et peaufiner cette configuration a été une formidable source d'apprentissage et de plaisir, et je suis toujours à la recherche de nouvelles façons de l'améliorer.

Si vous avez des idées, des commentaires, de meilleures solutions, ou si vous souhaitez simplement partager votre propre configuration, n'hésitez pas à me contacter. Envoyez-moi un message, challengez mes choix ou partagez votre histoire avec moi !
