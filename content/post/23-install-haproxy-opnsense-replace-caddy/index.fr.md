---
slug: install-haproxy-opnsense-replace-caddy
title: Installer HAProxy sur OPNsense pour remplacer Caddy
description: J’ai installé HAProxy sur mon cluster OPNsense et remplacé Caddy pour résoudre des erreurs SSL aléatoires tout en conservant le routage HTTPS et le failover.
date: 2026-09-19
draft: false
tags:
  - opnsense
  - caddy
  - haproxy
categories:
  - homelab
image: cover-23.webp
---

## Introduction

Mon cluster OPNsense est la porte d’entrée de mon homelab. Il reçoit le trafic HTTPS, décide de sa destination, puis le transmet soit aux services derrière Traefik, soit directement aux interfaces d’infrastructure comme Proxmox, TrueNAS et OPNsense lui-même.

Jusqu’à récemment, ce travail était assuré par Caddy. Il était simple à configurer et, surtout, il gérait les certificats sans rien me demander. Un élément d’infrastructure merveilleusement silencieux.

Puis j’ai mis OPNsense à niveau vers la version 26.1. Les requêtes vers les services gérés par Traefik ont commencé à échouer aléatoirement avec `SSL_ERROR_INTERNAL_ERROR_ALERT`. Pas toutes les requêtes, ni tous les services, mais suffisamment souvent pour rendre la configuration peu fiable.

Je voulais également recréer un endpoint Kubernetes que j’avais auparavant géré avec HAProxy. Plutôt que d’essayer de convaincre Caddy de mieux se comporter, j’ai donc profité de l’occasion pour le remplacer par HAProxy.

Voici l’histoire de cette migration, avec le moment où un simple reverse proxy devient un ensemble de dispatchers TCP, de maps, de certificats et d’un peu de configuration HAProxy en mode libre.

## Ce que j’attends du reverse proxy

La configuration répond à deux besoins de routage différents.

La plupart des applications tournent sur `dockerVM` (une VM qui exécute Docker, au cas où ce ne serait pas évident), derrière Traefik. Pour ces services, OPNsense doit inspecter le Server Name Indication TLS, puis transmettre la connexion chiffrée à Traefik. Traefik reste responsable de ses propres certificats TLS.

D’autres services sont des interfaces d’infrastructure auxquelles je veux seulement accéder depuis les réseaux internes ou via mon VPN :

- Proxmox
- TrueNAS
- L’interface Web d’OPNsense

Pour ces services, HAProxy termine TLS et transmet le trafic HTTP au backend approprié. Je dois également faire fonctionner la configuration sur les deux nœuds de mon cluster OPNsense HA.

Dans ma configuration précédente, Caddy gérait ces deux types de trafic grâce à ses fonctions de reverse proxy et de proxy Layer4. La configuration originale est décrite dans mon article sur [ma configuration OPNsense HA]({{< ref "post/13-opnsense-full-configuration" >}}).

## Préparer HAProxy avant la bascule

J’installe le plugin communautaire `os-haproxy` sur le nœud maître OPNsense et je construis la nouvelle configuration alors que Caddy sert encore le trafic de production. Cela rend la migration moins stressante. En théorie, du moins.

Je commence par définir les serveurs réels et les pools de backend. `dockerVM` reçoit un backend TCP pour le TLS passthrough et un backend HTTP pour les challenges ACME. Les services d’infrastructure reçoivent des backends HTTP avec TLS activé vers leurs serveurs en amont.

Le backend Proxmox contient les trois nœuds Proxmox, tandis que TrueNAS et l’interface Web locale d’OPNsense disposent chacun de leur propre backend.

⚠️ Une petite surprise apparaît pendant les tests : les interfaces TrueNAS et Proxmox restent bloquées sur leur écran de chargement pendant un long moment. Désactiver HTTP/2 dans leurs pools de backend résout le problème. Ce n’est pas une correction particulièrement spectaculaire, mais c’est exactement le genre de détail qui fait durer une migration plus longtemps que prévu.

## Un port, plusieurs types de HTTPS

Au début, je teste les services d’infrastructure sur des ports différents. Cela fonctionne, mais ce n’est pas l’objectif. Je veux que `proxmox.vezpi.com` et `nas.vezpi.com` partagent le même port HTTPS public.

HAProxy peut sélectionner un backend HTTP grâce à l’en-tête `Host` une fois TLS terminé. Cela me donne un frontend pour les services d’infrastructure, mais ne résout pas le TLS passthrough vers Traefik. Un flux TLS ne peut pas être terminé par HAProxy tout en étant transmis tel quel.

💡 La solution est un dispatcher TCP sur le port `443`.

HAProxy inspecte le TLS ClientHello, lit le nom d’hôte SNI et prend une première décision de routage sans terminer la connexion :

- Les domaines gérés par Traefik vont directement vers `dockerVM`.
- Les domaines d’infrastructure vont vers un frontend HAProxy local qui gère le TLS offloading et sélectionne ensuite le backend HTTP final.

Le dispatcher a besoin d’un délai d’inspection afin de laisser à HAProxy le temps de lire le ClientHello :

```plaintext
tcp-request inspect-delay 5s
```

Cela suffit pour conserver le TLS intact jusqu’à Traefik, tout en permettant à HAProxy de router lui-même les interfaces d’infrastructure.

## Garder les services internes… internes

Exposer Proxmox ou TrueNAS sur internet serait une manière très efficace de me créer du travail pour plus tard. Le dispatcher doit donc également appliquer des règles d’accès.

Je définis mes réseaux internes, y compris le réseau VPN, dans une ACL. Les requêtes vers les noms d’hôte internes sont rejetées lorsque leur source ne correspond pas à cette ACL. Le même modèle fonctionne aussi pour les services internes hébergés sur `dockerVM`.

Au début, je crée une condition et une règle pour chaque nom d’hôte via l’interface du plugin. Cela convient pour deux ou trois services. Mon homelab possède cependant environ trente URLs, et je n’ai aucune envie de créer, nommer et maintenir une petite forêt de règles chaque fois que j’en ajoute une.

Les maps sont mieux adaptées. Chaque nom d’hôte correspond à une politique plutôt qu’à un backend directement, par exemple :

```plaintext
cloud.vezpi.com      EXTERNAL_DOCKERVM
git.vezpi.com        EXTERNAL_DOCKERVM
pdf.vezpi.com        INTERNAL_DOCKERVM
proxmox.vezpi.com    INTERNAL_INFRA
nas.vezpi.com        INTERNAL_INFRA
```

Le dispatcher TCP lit cette map et route le trafic en fonction de la politique :

```plaintext
tcp-request inspect-delay 5s

acl FROM_INTERNAL src 192.168.13.0/24 192.168.88.0/24 10.13.37.0/24 192.168.66.0/24

acl SERVICE_DEFINED req.ssl_sni,lower,map_dom(/tmp/haproxy/mapfiles/6a97dc93222c69.76162835.txt) -m found
acl SERVICE_EXTERNAL_DOCKERVM req.ssl_sni,lower,map_dom(/tmp/haproxy/mapfiles/6a97dc93222c69.76162835.txt) -m str EXTERNAL_DOCKERVM
acl SERVICE_INTERNAL_DOCKERVM req.ssl_sni,lower,map_dom(/tmp/haproxy/mapfiles/6a97dc93222c69.76162835.txt) -m str INTERNAL_DOCKERVM
acl SERVICE_INTERNAL_INFRA req.ssl_sni,lower,map_dom(/tmp/haproxy/mapfiles/6a97dc93222c69.76162835.txt) -m str INTERNAL_INFRA

tcp-request content reject if !SERVICE_DEFINED
tcp-request content reject if SERVICE_INTERNAL_DOCKERVM !FROM_INTERNAL
tcp-request content reject if SERVICE_INTERNAL_INFRA !FROM_INTERNAL

use_backend BP_DOCKERVM_HTTPS if SERVICE_EXTERNAL_DOCKERVM || SERVICE_INTERNAL_DOCKERVM
use_backend BP_INFRA_FORWARDER if SERVICE_INTERNAL_INFRA
```

Le nom du fichier est généré par le plugin et n’est pas particulièrement mémorable. C’est à ce moment que la configuration devient moins agréable qu’avec Caddy. L’interface graphique du plugin ne permet pas d’utiliser directement une map pour l’inspection SNI ; j’utilise donc le champ `Option pass-through` du frontend pour écrire moi-même les directives HAProxy.

Cela fonctionne bien, mais j’aurais préféré rester entièrement dans les conditions et les règles proposées par l’interface graphique.

## Gérer le HTTP et les certificats

HAProxy doit également gérer le trafic HTTP sur le port `80`. Pour les requêtes classiques, il n’est pas nécessaire d’exposer un service HTTP. L’exception importante concerne le chemin des challenges ACME, qui doit atteindre Traefik pour les domaines qu’il gère.

Le dispatcher HTTP vérifie que l’hôte demandé est défini dans la même map, n’accepte que `/.well-known/acme-challenge/` pour les domaines hébergés sur Docker, puis transmet la requête au backend HTTP de `dockerVM`.

Caddy gérait auparavant mes certificats. HAProxy ne le fait pas, j’installe donc le plugin `os-acme-client` sur OPNsense.

J’utilise un challenge DNS-01 OVH. Le client ACME reçoit des identifiants ayant la permission de gérer les enregistrements TXT de ma zone DNS, puis émet les certificats pour les services d’infrastructure :

- `proxmox.vezpi.com`
- `cerbere.vezpi.com`
- `nas.vezpi.com`

Je commence par émettre un certificat de test auprès de l’autorité de certification staging de Let’s Encrypt, puis je passe à l’autorité de production. Une automation redémarre HAProxy lorsque les certificats sont renouvelés, et le plugin installe automatiquement une vérification quotidienne du renouvellement.

Traefik continue de gérer ses propres certificats. HAProxy n’a besoin de certificats que pour les services où il termine lui-même TLS.

## La migration proprement dite

Une fois HAProxy prêt, la bascule finale est courte et volontairement ennuyeuse.

Je me connecte au maître OPNsense via son adresse IP plutôt que par le nom d’hôte actuellement servi par Caddy. Je déplace ensuite le dispatcher TCP HAProxy de son port de test vers `443`, et le dispatcher HTTP vers `80`.

À ce moment-là, je sais que désactiver Caddy va temporairement supprimer l’accès à tous les services proxifiés. Je désactive donc Caddy, j’applique la configuration HAProxy et je commence à vérifier les chemins importants.

Les services internes restent inaccessibles depuis l’extérieur et accessibles via le VPN. Les services publics derrière Traefik sont de nouveau disponibles. Enfin, je supprime la règle du firewall qui exposait le port de test.

🎯 La migration fonctionne et l’erreur aléatoire `SSL_ERROR_INTERNAL_ERROR_ALERT` a disparu.

## Synchroniser le nœud de secours

Le reverse proxy fait partie de ma configuration OPNsense hautement disponible, le nœud de secours a donc lui aussi besoin de HAProxy.

J’installe et je démarre `os-haproxy` sur le nœud de secours. De retour sur le maître, j’ajoute `HAProxy Load Balancer` aux services synchronisés par la haute disponibilité OPNsense, puis je lance une synchronisation complète.

Le client ACME ne prend pas en charge la HA dans cette configuration. Ce compromis me convient, car il ne renouvelle les certificats que tous les deux mois environ.

✅ Après avoir testé à la fois un switchover et un failover, les services restent accessibles. Ce genre de test est beaucoup plus relaxant une fois que le trafic passe réellement par le nouveau proxy.

## Conclusion

HAProxy résout le problème SSL qui m’a poussé à abandonner Caddy et me fournit le routage au niveau TCP dont j’ai besoin dans mon homelab. Le dispatcher basé sur des maps rend également l’ajout de nouveaux noms d’hôte raisonnablement simple, qu’il s’agisse de services publics, de services internes sur `dockerVM` ou de services d’infrastructure.

Cette migration rend cependant le compromis très clair. Caddy est beaucoup plus simple à configurer et sa gestion des certificats est merveilleusement pratique. HAProxy est plus flexible, mais le plugin OPNsense demande davantage de composants, notamment lorsque l’on mélange inspection SNI, TLS passthrough, TLS offloading, maps et ACL.

Pour l’instant, cette complexité supplémentaire en vaut la peine. Mes services sont de nouveau accessibles sans erreurs SSL aléatoires, les règles d’accès sont conservées et la configuration résiste à un failover du firewall.

C’est plutôt un bon résultat pour quelque chose qui a commencé avec une erreur agaçante dans un navigateur.
