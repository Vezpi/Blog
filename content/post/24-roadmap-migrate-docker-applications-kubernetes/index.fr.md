---
slug: roadmap-migrate-docker-applications-kubernetes
title: Roadmap pour migrer de Docker Compose vers Kubernetes
description: Pourquoi je migre mes applications auto-hébergées d'une VM Docker vers Kubernetes et comment je compte le faire prudemment.
date: 2026-09-27
draft: true
tags:
  - kubernetes
  - docker
categories:
  - homelab
image: cover-24.webp
---

## Introduction

Depuis des années, mes applications auto-hébergées fonctionnent sous forme de conteneurs Docker gérés avec Docker Compose sur une seule machine virtuelle. Cela fonctionne suffisamment bien, ce qui rend précisément le changement un peu inconfortable.

Je ne suis pas poussé à migrer par un incident urgent en production. Il n'y a pas de panne mystérieuse ni de matériel sur le point de prendre feu. Je veux simplement apprendre Kubernetes par la pratique et faire évoluer mon homelab vers une plateforme qui me donnera davantage de liberté pour expérimenter.

😈 Oui, faire tourner un cluster Kubernetes dans un homelab est overkill. Je le sais. C'est aussi le but.

Cet article présente la feuille de route de cette migration, depuis la mise en place des fondations du cluster jusqu'à la mise hors service de l'ancienne VM Docker.

## Pourquoi Kubernetes dans un homelab

La configuration actuelle avec Docker Compose est simple : une VM héberge les applications et Compose décrit la manière dont les conteneurs doivent fonctionner. Pour un petit environnement auto-hébergé, c'est une solution parfaitement raisonnable.

Kubernetes ajoute une quantité considérable de complexité. Il faut prendre en compte plusieurs nœuds, un control plane, le réseau, le stockage, l'ingress, les certificats, la supervision et les sauvegardes. Je ne prétends pas qu'il s'agit de la manière la plus simple d'héberger mes services.

La motivation est l'apprentissage. Un homelab offre un endroit sûr pour comprendre le comportement de Kubernetes, tester différentes approches et faire des erreurs sans les contraintes d'un environnement de production. Le but n'est pas de prouver que Kubernetes est meilleur que Docker Compose pour toutes les charges de travail. Le but est d'acquérir une expérience pratique de Kubernetes.

Il y a une autre raison de faire les choses correctement : je veux rendre la plateforme reproductible. À terme, je veux pouvoir construire un cluster de validation temporaire, y tester des changements, puis reconstruire le cluster et ses applications grâce à l'automatisation avec Terraform et Ansible.

## La stratégie de migration

Je ne veux pas tout migrer en une seule opération massive. Cela rendrait le troubleshooting inutilement difficile et transformerait chaque petite erreur en potentielle interruption de service.

À la place, je découpe le travail en plusieurs étapes. Chaque étape ajoute une capacité importante à la plateforme avant d'y déplacer le groupe d'applications suivant.

Le cluster Kubernetes lui-même est d'abord bootstrapé manuellement. C'est volontaire. Avant d'automatiser le processus, je veux comprendre ce qui se passe lors de la création du cluster et du déploiement des applications. GitOps fait partie de l'objectif final, mais je le repousse à plus tard afin de pouvoir d'abord expérimenter la plateforme sans dissimuler le processus de déploiement derrière une couche d'automatisation supplémentaire.

## Étape 1 : construire les fondations du cluster

La première étape consiste à créer l'infrastructure sur laquelle Kubernetes fonctionnera. Je l'ai déjà fait il y a quelques mois dans [cet article]({{< ref "post/8-create-manual-kubernetes-cluster-kubeadm" >}}), mais cette fois je vais pousser l'automatisation un peu plus loin.

Je prévois d'utiliser Terraform pour provisionner les machines virtuelles des nœuds Kubernetes. Ansible préparera ensuite ces VMs. Le bootstrap initial du cluster et l'installation de la Container Network Interface seront effectués manuellement.

Cette approche permet de séparer clairement les responsabilités :

- Terraform crée les machines.
- Ansible prépare les systèmes d'exploitation.
- Le premier bootstrap Kubernetes reste manuel pour le moment.

Les fondations du cluster doivent être fiables avant d'y ajouter les applications. Si les nœuds et le réseau ne sont pas sains, déboguer un déploiement applicatif devient une manière particulièrement créative de gâcher une soirée.

## Étape 2 : ajouter le point d'entrée

Une fois le cluster en place, il doit pouvoir recevoir du trafic. L'étape suivante concerne donc l'API gateway et la gestion des certificats.

Je vais déployer une API gateway et `cert-manager`, puis une première application pour vérifier que l'ensemble du chemin fonctionne. Cette première application ne représente pas une migration complète. C'est un test de la plateforme : est-il possible de déployer une application, d'y accéder depuis l'extérieur du cluster et de la sécuriser avec un certificat ?

Cette étape est importante car elle valide davantage que le scheduling Kubernetes. Elle teste l'intégration entre le cluster, le réseau, l'accès externe et TLS.

## Étape 3 : stockage, sauvegardes et supervision

Avant de migrer quoi que ce soit d'important, je dois comprendre ce qui arrive aux données.

Le plan consiste à définir des storage classes pour les stockages Ceph et TrueNAS. J'ai également besoin d'une configuration de supervision de base et d'une stratégie de sauvegarde pour le cluster.

C'est à ce moment que le projet cesse de se limiter à faire tourner des conteneurs. Les workloads stateless sont relativement simples à déplacer. Les applications stateful nécessitent de décider où leurs données seront stockées, comment elles seront sauvegardées et comment le service pourra être restauré après une panne.

Je ne veux pas découvrir que la stratégie de sauvegarde est incomplète après avoir déplacé les applications qui comptent le plus.

## Étapes 4 à 6 : migrer progressivement les applications

Une fois les capacités de la plateforme en place, les applications peuvent être déplacées par groupes, selon leur niveau de risque.

### Applications à faible risque

Les premières migrations concerneront des applications stateless. Elles sont les meilleures candidates pour valider le processus de déploiement, car elles ne contiennent pas de données critiques et devraient être plus faciles à recréer.

### Applications à risque moyen et stateful

Viendront ensuite les services non vitaux et les applications dont les besoins en stockage sont plus complexes. Ces migrations aideront à valider les storage classes, les sauvegardes et les procédures de récupération dans des conditions plus réalistes.

### Applications critiques

Les applications vitales arriveront en dernier. À ce moment-là, le cluster aura déjà été éprouvé avec des workloads moins importants et les fondations de la supervision et des sauvegardes devraient être plus matures.

Cet ordre est volontairement prudent. La migration est aussi un projet d'apprentissage, mais je n'ai pas besoin de transformer chaque leçon en interruption de service.

## Étape 7 : améliorer la supervision et la reprise après sinistre

Une fois les applications migrées, la solution de supervision et de sauvegarde devra être revue.

La configuration initiale est une base, pas un état final. L'objectif est de tendre vers une solution de supervision plus complète et de mettre en place un plan de reprise après sinistre. Un cluster peut sembler sain tout en étant difficile à restaurer, c'est pourquoi le processus de récupération doit être considéré séparément de la supervision quotidienne.

## Étape 8 : automatiser le cycle de vie du cluster

L'étape importante suivante consiste à rendre la plateforme temporaire et reconstructible.

Je veux pouvoir créer un cluster de validation depuis zéro et reconstruire de manière fiable le cluster ainsi que ses applications. Terraform et Ansible seront utilisés pour automatiser ce processus.

C'est ici que le travail manuel réalisé au début devrait porter ses fruits. En comprenant d'abord les étapes, je peux automatiser un processus que je maîtrise réellement au lieu de convertir aveuglément des commandes en playbooks.

## Étape 9 : introduire GitOps

Je n'introduirai GitOps qu'une fois la plateforme et l'automatisation de son cycle de vie opérationnelles.

Le repository sera réorganisé pour prendre en charge ce mode de fonctionnement, avec l'état souhaité du cluster et des applications géré dans Git. L'objectif est de permettre un déploiement complet du cluster conforme à la stratégie GitOps.

GitOps est la destination, pas la ligne de départ. L'introduire trop tôt rendrait la première phase d'apprentissage plus difficile, notamment alors que l'architecture du cluster et les méthodes de déploiement des applications sont encore amenées à évoluer.

## Étape 10 : mettre la VM Docker hors service

La dernière étape ne prendra pas la forme d'un arrêt brutal. Je veux arrêter la VM Docker pendant un certain temps tout en faisant fonctionner les applications sur Kubernetes. Si tout reste stable et que la nouvelle plateforme se montre fiable, je pourrai finalement détruire l'ancienne VM.

Conserver l'ancien environnement pendant la transition fournit un filet de sécurité. Cela donne aussi une définition claire de la fin du projet : la migration n'est pas terminée simplement parce qu'une application démarre dans Kubernetes. Elle sera terminée lorsque j'aurai suffisamment confiance pour supprimer la plateforme précédente.

## Conclusion

🚀 C'est le plus grand projet de homelab que j'ai planifié jusqu'à présent, et probablement aussi le plus passionnant.

L'objectif technique est de migrer des applications auto-hébergées depuis une VM Docker Compose unique vers un cluster Kubernetes. L'objectif le plus important est d'apprendre à concevoir, exploiter, automatiser, superviser, sauvegarder et finalement reconstruire cette plateforme.

La feuille de route progresse de la compréhension vers la migration, puis de la migration vers l'automatisation. Je commence par un cluster manuel, j'ajoute le réseau et le stockage, je migre les applications selon leur niveau de risque, j'améliore la récupération, j'automatise le cycle de vie et je termine avec GitOps.

🔥 Cela représente beaucoup de travail pour un homelab. C'est précisément pour cela que ce projet devrait être une formidable occasion d'apprendre.
