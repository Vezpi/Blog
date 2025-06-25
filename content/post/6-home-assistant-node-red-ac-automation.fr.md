---
slug: ac-automation-home-assistant-node-red
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

## Ancien Workflow

J’avais déjà une solution plutôt efficace pour contrôler ma climatisation via Home Assistant et Node-RED, mais je voulais l’améliorer pour qu’elle prenne aussi en compte le taux d’humidité dans l’appartement. Mon automatisation actuelle, bien qu’elle fonctionne, n’était pas vraiment évolutive et assez difficile à maintenir.  
![Ancien workflow Node-RED pour contrôler la climatisation](img/node-red-ha-ac-automation-before.png)

## Nouveau Workflow

Plutôt que de bricoler ce flow existant, j’ai préféré repartir de zéro avec le même objectif : piloter le système de climatisation en prenant en compte tous les capteurs disponibles : thermomètres, humidité, capteurs d’ouverture, présence des occupants, moment de la journée, etc.

### Objectifs

L’idée est assez simple : ne plus avoir à penser à la climatisation, tout en restant efficace.

Mais concrètement, qu’est-ce que ça veut dire ? Je veux que la température et le taux d’humidité restent dans des valeurs confortables, que je sois présent ou non. Si j’ouvre les fenêtres, la clim doit s’arrêter. Si l’air est trop humide, je veux qu’il soit asséché. Si j’allume ou éteins manuellement la clim, je ne veux pas que ça écrase mes réglages. La nuit, je n’ai pas besoin de rafraîchir le salon et je veux aussi que le système soit silencieux, etc.

Pour m’aider à faire tout ça, j’utilise 4 [capteurs de température et d’humidité Aqara](https://eu.aqara.com/fr-eu/products/aqara-temperature-and-humidity-sensor), un dans chacune de mes pièces principales. J’utilise aussi quelques [capteurs d’ouverture Aqara](https://eu.aqara.com/fr-eu/products/aqara-door-and-window-sensor) pour savoir si une fenêtre est ouverte.

### Workflow

Laissez-moi vous présenter mon nouveau workflow de climatisation dans Node-RED, et vous expliquer en détail comment il fonctionne.

![New Node-RED air conditioning workflow](img/node-red-new-ac-workflow-with-legend.png)

#### #### 1. Capteurs de Température

Dans le premier nœud, j’ai regroupé tous les capteurs thermiques dans un seul `trigger state node`, en ajoutant non seulement la température mais aussi le taux d’humidité géré par chaque capteur. Ce nœud contient donc une liste de 8 entités (2 pour chaque capteur). À chaque fois qu’une de ces 8 valeurs change, le nœud est déclenché:
![Nœud trigger state dans Node-RED avec les 8 entités](img/node-red-temperature-sensors-trigger-node.png)

Chacun de mes capteurs thermiques porte un nom de couleur en français, car ils ont tous un autocollant coloré pour les distinguer :
- **Jaune** : Salon
- **Bleu** : Chambre
- **Rouge** : Bureau
- **Vert** : Chambre de mon fils

Le deuxième nœud est un `function node` dont le rôle est de déterminer à quelle pièce appartient le capteur :
```js
const association = {
    "temperature_jaune": "salon",
    "temperature_bleu": "chambre",
    "temperature_rouge": "couloir",
    "temperature_vert": "couloir"
};

// Match pattern like: sensor.temperature_rouge_temperature
const match = msg.topic.match(/^sensor\.(.+)_(temperature|humidity)$/);

if (!match) {
    node.warn("Topic format not recognized: " + msg.topic);
    return null;
}

msg.payload = { 
    room: association[match[1]],
    sensor: match[1]
};

return msg;
```

Pour le dernier nœud, dans la majorité des cas, les capteurs envoient deux messages simultanés : l’un pour la température, l’autre pour l’humidité. J’ai donc ajouté un `join node` pour fusionner ces deux messages s’ils sont envoyés dans la même seconde.  
![Join node in Node-RED to merge temperature and humidity](img/node-red-temperature-sensor-join-node.png)

#### 2. Notification

Il peut arriver que les capteurs de température n’envoient plus d’état pendant un certain temps, pour une raison ou une autre. Dans ce cas, ils renvoient simplement leur dernière valeur connue, ce qui peut bloquer l’unité de climatisation associée.

La solution que j’ai trouvée efficace consiste à envoyer une notification si un capteur n’a pas transmis de nouvelle valeur depuis plus de 3 heures. En fonctionnement normal, chaque capteur envoie une mise à jour environ toutes les 15 minutes.

Le premier nœud est un `function node` un peu technique, qui crée une variable de flux comme minuteur pour chaque capteur. Une fois le délai écoulé, un message est envoyé au nœud suivant :
```js
const sensor = msg.payload.sensor;
const timeoutKey = `watchdog_${sensor}`;
const messages = {
    "temperature_jaune": {"title": "Température Salon", "message": "Capteur de température du salon semble hors service"},
    "temperature_bleu": {"title": "Température Chambre", "message": "Capteur de température de la chambre semble hors service"},
    "temperature_rouge": {"title": "Température Bureau", "message": "Capteur de température du bureau semble hors service"},
    "temperature_vert": {"title": "Température Raphaël", "message": "Capteur de température de Raphaël semble hors service"}
};

// Clear existing timer
const existing = flow.get(timeoutKey);
if (existing) clearTimeout(existing);

// Set new timer
const timer = setTimeout(() => {
    node.send({
        payload: `⚠️ No update from ${sensor} in 3 hours.`,
        sensor: sensor,
        title: messages[sensor]["title"],
        message: messages[sensor]["message"]
    });
}, 3 * 60 * 60 * 1000); // 3 hours

flow.set(timeoutKey, timer);

return null; // Don't send anything now
```

Le second nœud est un `call service node` qui envoie une notification sur mon téléphone Android avec les informations fournies :  
![Node-RED call service node for notification](img/node-red-call-service-node-notification.png)

#### 3. Curseurs de température

Pour pouvoir ajuster la température sans avoir à modifier tout le workflow, j’ai créé deux entrées (ou helper) Home Assistant, de type _number_, pour chaque unité de climatisation, ce qui me fait un total de 6 entrées :  
![Curseur de température dans Home Assistant pour chaque unité](img/home-assistant-temperature-room-sliders.png)

Ces valeurs représentent la température de base utilisée pour le calcul des seuils, en fonction des offsets que je détaillerai plus loin.

Le premier nœud est un `trigger state node` qui regroupe les 6 entités. Si je modifie l’une de ces valeurs, le nœud est déclenché :  
![Node-RED trigger state node for sliders](img/node-red-trigger-state-nmode-for-sliders.png)

Le deuxième nœud est un `function node`, qui permet de déterminer la pièce concernée :
```js
const association = {
    "input_number.temp_ete_salon": "salon",
    "input_number.temp_hiver_salon": "salon",
    "input_number.temp_ete_chambre": "chambre",
    "input_number.temp_hiver_chambre": "chambre",
    "input_number.temp_ete_couloir": "couloir",
    "input_number.temp_hiver_couloir": "couloir"
};

msg.payload = { room: association[msg.topic] }; 
return msg;
```

#### 4. Interrupteurs

Dans Home Assistant, j’utilise d’autres entrées, mais cette fois sous forme de booléens. Le plus important est celui dédié à la climatisation, qui me permet de désactiver manuellement tout le workflow. J’en ai d’autres qui sont automatisés, par exemple pour le moment de la journée ou la détection de présence à la maison.

J’utilise un autre `trigger state node` qui regroupe tous mes interrupteurs sous forme de booléens, y compris un bouton de test utilisé pour le débogage :  
![Node-RED trigger state node for toggles](img/node-red-trigger-state-node-toggles.png)

Comme ces interrupteurs impactent tout l’appartement (et non une seule unité), le nœud suivant est un `change node` qui définit la valeur de la pièce à `partout` :  
![Node-RED change node to set room to partout](img/node-red-change-node-room-partout.png)

#### 5. Fenêtres

Les derniers déclencheurs sont les fenêtres. Si j’ouvre ou ferme une fenêtre située près d’une unité, cela active le workflow. J’ai des capteurs d’ouverture sur certaines fenêtres, mais pour l’unité du couloir, j’utilise l’état des fenêtres Velux. Certaines pièces ayant plusieurs fenêtres, j’ai créé une entrée de type groupe pour les regrouper.

Le premier nœud est le dernier `trigger state node`. La valeur retournée est une string qu’il faudra ensuite convertir en booléen :  
![Node-RED trigger state node for windows](img/node-red-trigger-state-node-windows.png)

Juste après, un autre `function node` permet d’identifier la pièce concernée :
```js
const association = {
    "binary_sensor.groupe_fenetre_salon": "salon",
    "binary_sensor.fenetre_chambre_contact": "chambre",
    "cover.groupe_fenetre_couloir": "couloir"
};

msg.payload = { 
    room: association[msg.topic]
};
return msg;
```

#### 6. Fenêtre Watchdog

Quand j’ouvre une fenêtre, ce n’est pas forcément pour la laisser ouverte longtemps. Je peux simplement faire sortir le chat ou jeter un œil au portail. Je ne veux pas que la climatisation se coupe dès que j’ouvre une fenêtre. Pour contourner cela, j’ai mis en place un watchdog pour chaque unité, afin de retarder l’envoi du message pendant un certain temps.

Le premier nœud est un `switch node`. En fonction de la pièce transmise par le nœud précédent, il envoie le message au _watchdog_ correspondant :  
![Node-RED switch node based on the room for the watchdog](img/node-red-switch-node-room-selector-watchdog.png)

Viennent ensuite les _watchdogs_, des `trigger nodes`, qui retardent le message pendant un certain temps, et prolongent ce délai si un autre message est reçu entre-temps :  
![Node-RED trigger node for window watchdog](img/node-red-trigger-node-window-watchdog.png)

#### 7. Climatisation Activée ?

Tous ces déclencheurs arrivent maintenant dans la chaîne de traitement, qui va déterminer ce que le système doit faire. Mais avant cela, on vérifie si l’automatisation est activée. J’ai ajouté ce kill switch au cas où, même si je l’utilise rarement.

Le premier nœud est un `delay node` qui régule le débit des messages entrants à 1 message par seconde :  
![Node-RED delay node to limit the rate to 1 message per second](img/node-red-delay-node-1-msg-per-second.png)

Le deuxième nœud est un `current state node` qui vérifie si le booléen `climatisation` est activé :  
![Node-RED current state node for climatisation](img/node-red-current-state-node-climatisation-enabled.png)

#### 8. Configuration des pièces

L’idée ici est d’associer la configuration de la pièce au message. Chaque pièce a sa propre configuration : quelle unité est utilisée, quels capteurs sont associés, et surtout, dans quelles conditions elle doit s’allumer ou s’éteindre.

Les unités de climatisation disposent de 4 modes :
- Refroidissement (Cool)
- Déshumidification (Dry)
- Ventilation (Fan)
- Chauffage (Heat)

Pour déterminer quel mode utiliser, j’utilise des seuils pour chaque mode et la vitesse de ventilation, avec différents offsets selon la situation. Je peux ainsi définir un offset spécifique la nuit ou en cas d’absence. Je peux aussi définir un offset sur `disabled`, ce qui forcera l’arrêt de l’unité.

Le premier nœud est un `switch node`, basé sur la valeur `room`, qui oriente le message vers la configuration associée. Si la pièce est `partout`, le message est dupliqué vers les 3 configurations de pièce :  
![Node-RED switch node for room configuration](img/node-red-switch-node-room-config.png)

Il est ensuite connecté à un `change node`, qui ajoute la configuration dans `room_config`. Voici un exemple avec la configuration du salon :
```json
{
    "threshold": {
        "cool": {
            "start": {
                "1": 1,
                "2": 1.5,
                "3": 2,
                "4": 2.5,
                "quiet": 0
            },
            "stop": -0.3,
            "target": -1,
            "offset": {
                "absent": 1,
                "vacances": "disabled",
                "fenetre": "disabled",
                "matin": "disabled",
                "jour": 0,
                "soir": 0,
                "nuit": "disabled"
            }
        },
        "dry": {
            "start": {
                "quiet": -1
            },
            "stop": -1.5,
            "offset": {
                "absent": "1.5",
                "vacances": "disabled",
                "fenetre": "disabled",
                "matin": "disabled",
                "jour": 0,
                "soir": 0,
                "nuit": "disabled"
            }
        },
        "fan_only": {
            "start": {
                "1": -0.3,
                "quiet": -0.5
            },
            "stop": -0.7,
            "offset": {
                "absent": "disabled",
                "vacances": "disabled",
                "fenetre": "disabled",
                "matin": "disabled",
                "jour": 0,
                "soir": 0,
                "nuit": "disabled"
            }
        },
        "heat": {
            "start": {
                "1": 0,
                "2": -1.5,
                "quiet": 0
            },
            "stop": 1,
            "target": 1,
            "offset": {
                "absent": -1.5,
                "vacances": -3,
                "fenetre": "disabled",
                "matin": 0,
                "jour": 0,
                "soir": 0,
                "nuit": -1.5
            }
        }
    },
    "unit": "climate.clim_salon",
    "timer": "timer.minuteur_clim_salon",
    "window": "binary_sensor.groupe_fenetre_salon",
    "thermometre": "sensor.temperature_jaune_temperature",
    "humidity": "sensor.temperature_jaune_humidity",
    "temp_ete": "input_number.temp_ete_salon",
    "temp_hiver": "input_number.temp_hiver_salon"
}
```

#### 9. 
#### 10. 
#### 11. 
#### 12. 
#### 13. 
#### 14. 
#### 15. 
#### 16. 
#### 17. 
3. 