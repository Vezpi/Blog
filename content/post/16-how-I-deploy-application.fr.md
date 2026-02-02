---
slug: how-I-deploy-application
title: Comment je Déploie des Applications Aujourd’hui
description: La méthode que j’utilise aujourd’hui pour déployer de nouvelles applications dans mon homelab. Workflow simple tirant parti de Docker Compose dans une VM sur Proxmox VE
date: 2026-01-31
draft: false
tags:
  - docker
  - proxmox
  - opnsense
  - treafik
  - gitea
categories:
  - homelab
---
## Intro

Dans cet article, je ne vais pas expliquer les bonnes pratiques pour déployer des applications. À la place, je veux documenter comment je déploie actuellement de nouvelles applications dans mon homelab.

Considérez cet article comme un snapshot. C’est comme ça que les choses fonctionnent vraiment aujourd’hui, sachant que dans un futur proche j’aimerais évoluer vers un workflow plus orienté GitOps.

La méthode que j’utilise est assez simple. J’ai essayé de la standardiser autant que possible, mais elle implique encore pas mal d’étapes manuelles. J’expliquerai aussi comment je mets à jour les applications, ce qui est, à mon avis, la plus grande faiblesse de cette configuration. À mesure que le nombre d’applications augmente, garder le tout à jour demande de plus en plus de temps.


---
## Overview de la Plateforme

Avant d’entrer dans le workflow, voici un rapide aperçu des principaux composants impliqués.
### Docker

Docker est la base de ma stack applicative. Quand c’est possible, je déploie les applications sous forme de conteneurs.

J’utilise Docker Compose depuis des années. À l’époque, tout tournait sur un seul serveur physique. Aujourd’hui, mon installation est basée sur des VM, et je pourrais migrer vers Docker Swarm, mais j’ai choisi de ne pas le faire. Cela peut avoir du sens dans certains scénarios, mais ce n’est pas aligné avec là où je veux aller à long terme.

Pour l’instant, je m’appuie toujours sur une seule VM pour héberger toutes les applications Docker. Cette VM est plus ou moins un clone de mon ancien serveur physique, simplement virtualisé.

### Proxmox VE

Cette VM est hébergée sur un cluster Proxmox VE, composé de trois nœuds et utilisant Ceph comme stockage distribué.

Cela me donne de la haute disponibilité et facilite grandement la gestion des VM, même si le workload Docker n'est pas hautement disponible.

### Traefik

Traefik tourne directement sur l’hôte Docker et fait office de reverse proxy.

Il est responsable d’acheminer le trafic HTTPS vers les bons conteneurs et de gérer automatiquement les certificats TLS via Let’s Encrypt. Cela garde la configuration au niveau des applications simple et centralisée.

### OPNsense

OPNsense est mon routeur, pare-feu et agit aussi comme reverse proxy.

Le trafic HTTPS entrant est transféré vers Traefik en utilisant le plugin Caddy avec des règles Layer 4. Le TLS n’est pas terminé au niveau du pare-feu. Il est transmis à Traefik, qui gère l’émission et le renouvellement des certificats.

### Gitea

Gitea est un dépôt Git self-hosted, j’ai une instance qui tourne dans mon homelab.

Dans Gitea, j’ai un dépôt privé qui contient toutes mes configurations Docker Compose. Chaque application a son propre dossier, ce qui rend le dépôt facile à parcourir et à maintenir.

---
## Déployer une Nouvelle Application

Pour standardiser les déploiements, j’utilise un template `docker-compose.yml` qui ressemble à ceci :
```yml
services:
  NAME:
    image: IMAGE
    container_name: NAME
    volumes:
      - /appli/data/NAME/:/
    environment:
      - TZ=Europe/Paris
    networks:
      - web
    labels:
    - traefik.enable=true
    - traefik.http.routers.NAME.rule=Host(`HOST.vezpi.com`)
    - traefik.http.routers.NAME.entrypoints=https
    - traefik.http.routers.NAME.tls.certresolver=letsencrypt
    - traefik.http.services.NAME.loadbalancer.server.port=PORT
    restart: always

networks:
  web:
    external: true
```

Laissez-moi expliquer.

Pour l’image, selon l’application, le registre utilisé peut varier, mais j’utilise quand même Docker Hub par défaut. Quand j’essaie une nouvelle application, je peux utiliser le tag `latest` au début. Ensuite, si je choisis de la garder, je préfère épingler la version actuelle plutôt que `latest`.

J’utilise des montages de volumes pour tout ce qui est stateful. Chaque application a son propre dossier dans le filesystem `/appli/data`.

Quand une application doit être accessible en HTTPS, je relie le conteneur qui sert les requêtes au réseau `web`, qui est géré par Traefik et je lui associe des labels. Les `entrypoint` et `certresolver` sont définis dans ma configuration Traefik. L’URL définie dans `Host()` est celle qui sera utilisée pour accéder à l’application. Elle doit être identique à ce qui est défini dans la route Layer4 du plugin Caddy d’OPNsense.

Si plusieurs conteneurs doivent communiquer entre eux, j’ajoute un réseau `backend` qui sera créé lors du déploiement de la stack, dédié à l’application. Ainsi, aucun port n’a besoin d’être ouvert sur l’hôte.

### Étapes de Déploiement

La plupart du travail est effectué depuis VScode :
- Créer un nouveau dossier dans ce dépôt, avec le nom de l’application.
- Copier le template ci-dessus dans ce dossier.
- Adapter le template avec les valeurs fournies par la documentation de l’application.
- Créer un fichier `.env` pour les secrets si nécessaire. Ce fichier est ignoré par `.gitignore`.
- Démarrer les services directement depuis VS Code en utilisant l’extension Docker.

Puis dans l’interface Web OPNsense, je mets à jour 2 routes Layer4 pour le plugin Caddy:
- Selon que l’application doit être exposée sur Internet ou non, j’ai une route _Internal_ et une route _External_. J’ajoute l’URL donnée à Traefik dans l’une d’elles.
- J’ajoute aussi cette URL dans une autre route pour rediriger le challenge HTTP Let’s Encrypt vers Traefik.

Une fois terminé, je teste l’URL. Si tout est correctement configuré, l’application devrait être accessible en HTTPS.

Quand tout fonctionne comme prévu, je commit le nouveau dossier de l’application dans le dépôt.

---
## Mettre à Jour une Application

Les mises à jour d’applications sont encore entièrement manuelles.

Je n’utilise pas d’outils automatisés comme Watchtower pour l’instant. Environ une fois par mois, je cherche de nouvelles versions en regardant Docker Hub, les releases GitHub ou la documentation de l’application.

Pour chaque application que je veux mettre à jour, je passe en revue:
- Nouvelles fonctionnalités
- Breaking changes
- Chemins de mise à niveau si nécessaire

La plupart du temps, les mises à jour sont simples:

- Mettre à jour le tag de l’image dans le fichier Docker Compose
- Redémarrer la stack.
- Vérifier que les conteneurs redémarrent correctement
- Consulter les logs Docker
- Tester l’application pour détecter des régressions

Si ça fonctionne, je continue à mettre à niveau étape par étape jusqu’à atteindre la dernière version disponible.

Sinon, je débogue jusqu’à corriger le problème. Les retours arrière sont pénibles.

Une fois la dernière version atteinte, je commit les changements dans le dépôt.

---
## Avantages et inconvénients

Qu’est-ce qui fonctionne bien et qu’est-ce qui fonctionne moins ?

### Avantages

- Modèle simple, une VM, un fichier compose par application.
- Facile à déployer, idéal pour tester une application.
- Emplacement central pour les configurations.

### Inconvénients

- La VM Docker unique est un point de défaillance unique.
- Les mises à jour manuelles ne passent pas à l’échelle quand le nombre d’applications augmente.
- Devoir déclarer l’URL dans Caddy est fastidieux.
- Difficile de suivre ce qui est en ligne et ce qui ne l’est pas.
- Les secrets dans .env sont pratiques mais basiques.
- Pas de moyen rapide de rollback.
- Les opérations sur la VM sont critiques.

---
## Conclusion

Cette configuration fonctionne, et elle m’a bien servi jusqu’ici. Elle est simple et intuitive. Cependant, elle est aussi très manuelle, surtout pour les mises à jour et la maintenance à long terme.

À mesure que le nombre d’applications augmente, cette approche ne passe clairement pas très bien à l’échelle. C’est l’une des principales raisons pour lesquelles je regarde vers GitOps et des workflows plus déclaratifs pour l’avenir.

Pour l'instant, cependant, c'est ainsi que je déploie des applications dans mon homelab, et cet article sert de point de référence pour savoir par où j'ai commencé.