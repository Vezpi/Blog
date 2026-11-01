---
slug: documenting-homelab-obsidian-ai
title: Créer l'inventaire de mon homelab dans Obsidian
description: Je documente mon homelab dans Obsidian grâce à un entretien mené par un agent IA, pour fournir un contexte précis à mes agents.
date: 2026-11-01
draft: false
tags:
  - obsidian
  - ai
categories:
  - homelab
image: cover-27.webp
---

## Introduction

Mon homelab réunit des hôtes physiques, des machines virtuelles, du stockage et des applications qui dépendent les uns des autres. Quand je demande à un agent IA de m'aider sur un projet, connaître le fonctionnement de Proxmox ou de Docker ne lui suffit pas. Il doit aussi comprendre comment ces éléments s'articulent dans mon lab.

J'utilise Obsidian depuis environ trois ans, après avoir quitté Notion. Mes notes de projet et mes articles de blog s'y trouvent déjà. C'est donc aussi là que je conserve l'inventaire : une description de l'infrastructure actuelle que je peux lire et que mes agents peuvent consulter.

💡 Pour le constituer, j'ai donné à un agent les grandes lignes de ma configuration et je lui ai demandé de m'interviewer. J'ai apporté les connaissances, pendant qu'il s'occupait de la rédaction et de l'organisation. Le résultat est un inventaire de notes liées entre elles qui nous donne une base commune, sans demander à chaque agent de reconstituer le lab à partir d'une conversation.

## Pourquoi Obsidian ?

[Obsidian](https://obsidian.md/) stocke les notes sous forme de fichiers Markdown dans un dossier local appelé coffre. Des liens relient les notes associées, par exemple une application et la VM qui l'héberge.

Je les lis et les modifie dans Obsidian. Mes agents travaillent sur les mêmes fichiers avec leurs outils de manipulation de fichiers, sans avoir besoin de piloter l'interface de l'application.

### Git et le blog

Le coffre est versionné dans mon instance Gitea self-hosted. Je peux donc examiner les modifications de la documentation, y compris celles effectuées par un agent.

📖 Mon [workflow Obsidian, Hugo et Gitea Actions]({{< ref "post/2-blog-deployment-obisidan-hugo-gitea-actions" >}}) envoie le dossier dédié `Blog/` vers le dépôt du blog. Le reste du coffre reste en dehors de ce workflow de publication.

## Un entretien avec l'IA

J'ai donné à un agent des informations générales sur mon infrastructure, puis je lui ai demandé de m'interviewer. Il s'est appuyé sur mes réponses pour rédiger les notes d'inventaire et relier les composants associés.

Je préfère une question précise à la fois. C'est plus facile d'y répondre qu'à un long questionnaire, et les détails incertains peuvent attendre une vérification.

L'agent prend les notes. Je dois quand même savoir ce qui est branché sur quoi. 😅

⚠️ Les détails inconnus restent signalés comme tels. Une application inutilisée, par exemple, ne correspond pas forcément à un conteneur arrêté ou supprimé.

## Organisation de l'inventaire

L'inventaire se trouve sous `Homelab/Inventory/`, avec quatre catégories :

- **Compute**: Hôtes physiques, VMs, LXCs et clusters. On y trouve par exemple le cluster Proxmox, `dockerVM` et le LXC `bastion`.
- **Storage**: Plateformes de stockage, notamment Ceph et TrueNAS.
- **Network**: Connectivité et services partagés, comme OPNsense, les VLANs, le DNS, le DHCP et UniFi.
- **Application**: Une note par application, comme Home Assistant, Gitea et Portainer.

Un index `Infrastructure.md` donne accès aux notes des composants. C'est le point de départ pour moi comme pour les agents.

### Sections communes

Chaque note de composant doit comporter quatre sections :

- **Description**: Ce qu'est le composant et son rôle dans le lab.
- **Details**: Spécifications, configuration et informations techniques utiles.
- **Relations**: Liens vers les hôtes, les dépendances et les composants qui l'utilisent.
- **Changelog**: Modifications datées du composant ou de sa documentation.

### Détails selon le type

La structure reste la même, mais les sous-sections de `Details` dépendent du `kind` du composant :

- **Hôte, VM ou LXC**: Matériel ou ressources allouées, OS, disques et configuration réseau.
- **Cluster**: Membres, topologie et mécanismes de disponibilité.
- **Stockage**: Architecture, pools ou datasets, redondance et composants qui l'utilisent.
- **Réseau ou service**: Architecture, adressage ou nommage et configuration du service concerné.
- **Application**: Usage, mode d'hébergement et configuration ou intégrations propres à l'application.

### Hébergement et dépendances

Les propriétés YAML indiquent le type du composant, son statut, son mode de gestion et sa disponibilité. Deux champs décrivent ses relations :

- **`runs_on`**: L'hôte ou la plateforme sur lesquels il s'exécute.
- **`depends_on`**: Les autres services dont il a besoin, sans répéter l'hôte.

### Un exemple complet

Voici la note `Portainer.md` complète, avec ses propriétés et son changelog :

```markdown
---
type: inventory
kind: application
status: active
runs_on:
  - "[[dockerVM]]"
depends_on:
  - "[[Traefik]]"
  - "[[Inventory/Network/OPNsense|OPNsense]]"
managed_by: manual
high_availability: false
tags:
  - inventory
  - docker
  - portainer
---
### Description

Docker management UI for the [[dockerVM]] application stack. Provides visual container management, logs, and monitoring for Docker Compose workloads.

### Details

| Property | Value |
|----------|-------|
| Runs on | [[dockerVM]] (Docker Compose) |
| Purpose | Visual Docker management |

### Relations

- **Managed**: All Docker containers on [[dockerVM]].
- **Ingress**: Via [[Traefik]] → [[Inventory/Network/OPNsense|OPNsense]] HAProxy.

### Changelog

- **2026-10-12**: Initial documentation.
- **2026-10-16**: Removed the host from `depends_on`; it is represented by `runs_on`.
```

ℹ️ Les doubles crochets sont des liens Obsidian, présentés ici sous forme de Markdown brut. Ils relient Portainer à `dockerVM` et à ses dépendances d'ingress.

Le changelog consigne aussi une correction : la VM doit figurer dans `runs_on`, pas dans les deux champs de relation.

## Du contexte pour les agents

### Lire avant d'agir

Un agent peut partir de la note d'une application et suivre ses liens d'hébergement et de dépendances. Il obtient le contexte pertinent sans lire tout le coffre ni s'appuyer sur une conversation précédente.

📖 Les notes de projet expliquent les décisions et les travaux en cours. L'inventaire décrit la configuration actuelle. Un plan de migration ne signifie pas que les applications ont déjà été déplacées.

### Garder les notes à jour

🔁 Je veux que les agents entretiennent le contexte qu'ils utilisent, en mettant à jour les notes concernées à partir de changements vérifiés. L'historique Git et les changelogs permettent de revoir ces modifications.

### Vérifier sur l'infrastructure

Plus tard, je veux que les agents recueillent des données directement auprès des composants. Avec des accès adaptés en lecture seule, ils pourraient comparer la configuration en fonctionnement avec l'inventaire, signaler les écarts et aider à corriger les notes obsolètes.

⚠️ C'est une prochaine étape, pas un processus de vérification automatique déjà en place. Je reste responsable des décisions et de l'application des changements à l'infrastructure. L'autorisation de lire les données d'un système ne donne pas celle de le modifier.

## Conclusion

J'ai maintenant un inventaire structuré dans Obsidian, avec un index pour parcourir le lab et des notes individuelles qui décrivent ses composants. Le format commun facilite la recherche d'informations, tandis que les liens d'hébergement et de dépendances expliquent comment les éléments s'articulent. Les changelogs gardent une trace des corrections et des mises à jour.

Le constituer par un entretien me permet d'apporter mes connaissances sans rédiger chaque note moi-même. Pour moi, le résultat est une référence lisible sur l'infrastructure. Pour mes agents, c'est un contexte concret à consulter avant de m'aider sur un projet, plutôt que de s'appuyer sur des fragments de conversations précédentes.

🔁 Cela me donne une base pour une documentation entretenue par les agents. La prochaine étape est de garder ces notes à jour à partir de changements vérifiés, puis de les vérifier directement sur l'infrastructure. Je continue à contrôler les faits, mais la rédaction et l'organisation sont des tâches que je peux partager avec les agents.
