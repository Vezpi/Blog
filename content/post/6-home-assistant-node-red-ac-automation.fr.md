---
slug: home-assistant-node-red-ac-automation
title: home-assistant-node-red-ac-automation
description: 
date: 
draft: true
tags: 
categories:
---
## Intro

Dans mon appartement, j’ai un système de climatisation Daikin, qui me permet de rafraîchir en été mais aussi de chauffer en hiver. Il est composé de 3 unités intérieures :
- Salon
- Chambre parentale
- Couloir (juste en face de mon bureau et de la chambre de mon fils)

J’ai toujours trouvé ça pénible de devoir les allumer manuellement quand j’en avais besoin, et j’oubliais souvent de les éteindre ensuite, sans parler de la télécommande que je passais mon temps à chercher.

Et si je pouvais automatiser tout ça ? Après tout, j’utilise déjà Home Assistant pour piloter beaucoup de choses chez moi, alors contrôler la clim, ça me semble logique.

### Home Assistant

Home Assistant, c’est le cerveau de ma maison connectée. Il relie tous mes appareils (lumières, capteurs, volets, etc.) dans une interface unique. Sa vraie force, c’est la possibilité de créer des automatisations : _si quelque chose se passe, alors fais ça_. Des actions simples comme “allumer la lumière de la cuisine quand un mouvement est détecté” se mettent en place en quelques clics. Et pour des scénarios plus avancés, Home Assistant propose un système de scripts en YAML avec des conditions, des minuteries, des déclencheurs, et même du templating.

Mais dès qu’on commence à faire des automatisations un peu complexes, qui dépendent de plusieurs capteurs, d’horaires spécifiques ou de la présence de quelqu’un, ça devient vite difficile à lire. Les blocs de code YAML s’allongent, et on ne sait plus trop ce qui fait quoi, surtout quand on veut corriger un petit détail plusieurs semaines plus tard.

### Node-RED

C’est exactement pour ça que je suis passé à Node-RED. C’est un outil visuel qui permet de construire des logiques avec des blocs appelés “nœuds”, qu’on relie entre eux avec des flèches pour créer un **flow**. Chaque nœud fait une petite action : déclencher à une certaine heure, vérifier une condition, envoyer une commande à un appareil, etc. Au lieu d’écrire du YAML, on glisse les éléments, on les connecte, et c’est tout.

Node-RED ne remplace pas Home Assistant, il le renforce. Je ne détaillerai pas l'installation de Node-RED ni son intégration à HA, je l'ai fait il y a deux ans, mais de mémoire c'est assez simple.

## Previous Workflow

I was already having a good solution to control my AC from Home Assistant with Node-RED, but I wanted to enhance it to also handle the humidity level at home. My current workflow, despite being functional, was not really scalable and quite hard to maintain.
![Ancien workflow Node-RED du contrôle de la climatisation](img/node-red-ha-ac-automation-before.png)

Instead of tweaking this workflow, I created a new one from scratch, with the same goal in mind: control the AC system by taking into account all available sensors: thermometers, humidity, door sensors, occupant presence, time of day, etc.

## New Workflow







![node-red-new-ac-workflow-with-legend.png](img/node-red-new-ac-workflow-with-legend.png)