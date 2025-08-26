---
slug: ac-automation-home-assistant-node-red
title: Automatisation complète de la clim avec Home Assistant et Node-RED
description: Comment j’automatise ma clim avec Home Assistant et Node-RED pour réagir à la température, l’humidité et à tous les évènements quotidiens.
date: 2025-06-27
draft: false
tags:
  - home-automation
  - home-assistant
  - node-red
categories:
  - automation
---
## Intro

Dans mon appartement, j’ai un système de climatisation Daikin, qui me permet de rafraîchir en été mais aussi de chauffer en hiver. Il est composé de 3 unités intérieures :
- Salon
- Chambre parentale
- Couloir (juste en face de mon bureau et de la chambre de mon fils)

J’ai toujours trouvé ça pénible de devoir les allumer manuellement quand j’en avais besoin, et j’oubliais souvent de les éteindre ensuite, sans parler de la télécommande que je passais mon temps à chercher.

Et si je pouvais automatiser tout ça ? Après tout, j’utilise déjà Home Assistant pour piloter beaucoup de choses chez moi, alors contrôler la clim, ça me semble logique.

### Home Assistant

Home Assistant, c’est le cerveau de ma maison connectée. Il relie tous mes appareils (lumières, capteurs, volets, etc.) dans une interface unique. Sa vraie force, c’est la possibilité de créer des automatisations : si quelque chose se passe, alors fait ça. Des actions simples comme “allumer la lumière de la cuisine quand un mouvement est détecté” se mettent en place en quelques clics. Et pour des scénarios plus avancés, Home Assistant propose un système de scripts en YAML avec des conditions, des minuteries, des déclencheurs, et même du templating.

Mais dès qu’on commence à faire des automatisations un peu complexes, qui dépendent de plusieurs capteurs, d’horaires spécifiques ou de la présence de quelqu’un, ça devient vite difficile à lire. Les blocs de code YAML s’allongent, et on ne sait plus trop ce qui fait quoi, surtout quand on veut corriger un petit détail plusieurs semaines plus tard.

### Node-RED

C’est exactement pour ça que je suis passé à Node-RED. C’est un outil visuel qui permet de construire des logiques avec des blocs appelés “nœuds”, qu’on relie entre eux avec des flèches pour créer un **flow**. Chaque nœud fait une petite action : déclencher à une certaine heure, vérifier une condition, envoyer une commande à un appareil, etc. Au lieu d’écrire du YAML, on glisse les éléments, on les connecte, et c’est tout.

Node-RED ne remplace pas Home Assistant, il le renforce. Je ne détaillerai pas l'installation de Node-RED ni son intégration à HA, je l'ai fait il y a deux ans, mais de mémoire c'est assez simple.

## Ancien Workflow

J’avais déjà une solution plutôt efficace pour contrôler ma climatisation via Home Assistant et Node-RED, mais je voulais l’améliorer pour qu’elle prenne aussi en compte le taux d’humidité dans l’appartement. Mon workflow actuel, bien qu’il fonctionne, n’était pas vraiment évolutif et assez difficile à maintenir :  
![Ancien workflow Node-RED pour contrôler la climatisation](img/node-red-ha-ac-automation-before.png)

## Nouveau Workflow

Plutôt que de bricoler ce flow existant, j’ai préféré repartir de zéro avec le même objectif : piloter le système de climatisation en prenant en compte tous les capteurs disponibles : thermomètres, humidité, capteurs d’ouverture, présence des occupants, moment de la journée, etc.

### Objectifs

L’idée est assez simple : ne plus avoir à penser à la climatisation, tout en restant efficace.

Mais concrètement, qu’est-ce que ça veut dire ? Je veux que la température et le taux d’humidité restent dans des valeurs confortables, que je sois présent ou non. Si j’ouvre les fenêtres, la clim doit s’arrêter. Si l’air est trop humide, je veux qu’il soit asséché. Si j’allume ou éteins manuellement la clim, je ne veux pas que ça écrase mes réglages. La nuit, je n’ai pas besoin de rafraîchir le salon et je veux aussi que le système soit silencieux, etc.

Pour m’aider à faire tout ça, j’utilise 4 [capteurs de température et d’humidité Aqara](https://eu.aqara.com/fr-eu/products/aqara-temperature-and-humidity-sensor), un dans chacune de mes pièces principales. J’utilise aussi quelques [capteurs d’ouverture Aqara](https://eu.aqara.com/fr-eu/products/aqara-door-and-window-sensor) pour savoir si une fenêtre est ouverte.

### Workflow

Laissez-moi vous présenter mon nouveau workflow de climatisation dans Node-RED, et vous expliquer en détail comment il fonctionne :  
![New Node-RED air conditioning workflow](img/node-red-new-ac-workflow-with-legend.png)

#### #### 1. Capteurs de Température

Dans le premier nœud, j’ai regroupé tous les capteurs thermiques dans un seul `trigger state node`, en ajoutant non seulement la température mais aussi le taux d’humidité géré par chaque capteur. Ce nœud contient donc une liste de 8 entités (2 pour chaque capteur). À chaque fois qu’une de ces 8 valeurs change, le nœud est déclenché :  
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

Pour le dernier nœud, dans la majorité des cas, les capteurs envoient deux messages simultanés : l’un pour la température, l’autre pour l’humidité. J’ai donc ajouté un `join node` pour fusionner ces deux messages s’ils sont envoyés dans la même seconde :  
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

#### 3. Curseurs de Température

Pour pouvoir ajuster la température sans avoir à modifier tout le workflow, j’ai créé deux entrées (ou helper) Home Assistant, de type number, pour chaque unité de climatisation, ce qui me fait un total de 6 entrées :  
![Curseur de température dans Home Assistant pour chaque unité](img/home-assistant-temperature-room-sliders.png)

Ces valeurs représentent la température de base utilisée pour le calcul des seuils, en fonction des offsets que je détaillerai plus loin.

Le premier nœud est un `trigger state node` qui regroupe les 6 entités. Si je modifie l’une de ces valeurs, le nœud est déclenché :  
![Node-RED trigger state node for sliders](img/node-red-trigger-state-mode-for-sliders.png)

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

#### #### 9. Calcul

Maintenant que le message contient la configuration de la pièce, on entre dans la phase de calcul. On dispose du nom de l’unité de climatisation, des capteurs associés, de la température de base souhaitée et de l’offset à appliquer. À partir de ces données, on récupère les états actuels et on effectue les calculs.

Le premier nœud est un `delay node` qui régule le débit des messages entrants, car le bloc précédent a potentiellement généré trois messages si toutes les pièces sont concernées.

Le deuxième nœud est le plus important du workflow, un `function node` qui remplit plusieurs rôles :

- Récupère les états des capteurs depuis Home Assistant
- Calcule les seuils des modes à partir des offsets
- Désactive certains modes si les conditions sont remplies
- Injecte les valeurs dans le `payload`
```js
// --- Helper: Get Home Assistant state by entity ID ---
function getState(entityId) {
    return global.get("homeassistant.homeAssistant.states")[entityId]?.state;
}

// --- Determine current time period based on sensors ---
const periods = ["jour", "soir", "nuit", "matin"];
msg.payload.period = periods.find(p => getState(`binary_sensor.${p}`) === 'on') || 'unknown';

// --- Determine presence status (absent = inverse of presence) ---
const vacances = getState("input_boolean.absent");
const absent = getState("input_boolean.presence") === 'on' ? 'off' : 'on';

/**
 * Recursively adds the base temperature and offset to all numeric start values in a threshold config
 */
function applyOffsetToThresholds(threshold, baseTemp, globalOffset) {
    for (const [key, value] of Object.entries(threshold)) {
        if (key === "offset") continue;

        if (typeof value === 'object') {
            applyOffsetToThresholds(value, baseTemp, globalOffset);
        } else {
            threshold[key] += baseTemp + globalOffset;
        }
    }
}

/**
 * Calculates the global offset for a mode, based on presence, vacation, window, and time of day
 */
function calculateGlobalOffset(offsets, modeName, windowState, disabledMap) {
    let globalOffset = 0;

    for (const [key, offsetValue] of Object.entries(offsets)) {
        let conditionMet = false;

        if (key === msg.payload.period) conditionMet = true;
        else if (key === "absent" && absent === 'on') conditionMet = true;
        else if (key === "vacances" && vacances === 'on') conditionMet = true;
        else if ((key === "fenetre" || key === "window") && windowState === 'on') conditionMet = true;

        if (conditionMet) {
            if (offsetValue === 'disabled') {
                disabledMap[modeName] = true;
                return 0; // Mode disabled immediately
            }

            globalOffset += parseFloat(offsetValue);
        }
    }

    return globalOffset;
}

/**
 * Main logic: compute thresholds for the specified room using the provided config
 */
const cfg = msg.payload.room_config;
const room = msg.payload.room;

// Normalize window sensor state
const rawWindow = getState(cfg.window);
const window = rawWindow === 'open' ? 'on' : rawWindow === 'closed' ? 'off' : rawWindow;

// Gather temperatures
const temps = cfg.thermometre.split(',')
    .map(id => parseFloat(getState(id)))
    .filter(v => !isNaN(v));

const temp_avg = temps.reduce((a, b) => a + b, 0) / temps.length;
const temp_min = Math.min(...temps);
const temp_max = Math.max(...temps);

// Gather humidity
const humidities = cfg.humidity.split(',')
    .map(id => parseFloat(getState(id)))
    .filter(v => !isNaN(v));

const humidity_avg = humidities.reduce((a, b) => a + b, 0) / humidities.length;
const humidity_min = Math.min(...humidities);
const humidity_max = Math.max(...humidities);

// Get base temps
const temp_ete = parseFloat(getState(cfg.temp_ete));
const temp_hiver = parseFloat(getState(cfg.temp_hiver));

// Process modes
const { threshold } = cfg;
const modes = ["cool", "dry", "fan_only", "heat"];
const disabled = {};

for (const mode of modes) {
    const baseTemp = (mode === "heat") ? temp_hiver : temp_ete;
    const globalOffset = calculateGlobalOffset(threshold[mode].offset, mode, window, disabled);

    applyOffsetToThresholds(threshold[mode], baseTemp, globalOffset);
}

// Final message
msg.payload = {
    ...msg.payload,
    unit: cfg.unit,
    timer: cfg.timer,
    threshold,
    window,
    temp: {
        min: temp_min,
        max: temp_max,
        avg: Math.round(temp_avg * 100) / 100
    },
    humidity: {
        min: humidity_min,
        max: humidity_max,
        avg: Math.round(humidity_avg * 100) / 100
    },
    disabled
};

return msg;
```

Le troisième nœud est un `filter node`, qui ignore les messages suivants ayant un contenu similaire :  
![Node-RED filter node to block similar message](img/node-red-filter-node-blocker.png)

Le quatrième nœud vérifie si un verrou est actif à l’aide d’un `current state node`. On regarde si le minuteur associé à l’unité est inactif. Si ce n’est pas le cas, le message est ignoré :  
![Node-RED current state node for timer lock](img/node-red-current-state-node-lock-timer.png)

Le dernier nœud est un autre `current state node` qui permet de récupérer l’état actuel de l’unité et ses propriétés :  
![Node-RED current state node to get current unit state](img/node-red-current-state-node-get-unit-state.png)

#### 10. État Cible

Après les calculs, il s'agit maintenant de déterminer quel doit être le mode cible, quelle action effectuer pour converger vers ce mode à partir de l’état actuel, et le cas échéant, quelle vitesse de ventilation utiliser pour ce mode.

Les trois nœuds suivants sont des `function nodes`. Le premier détermine le mode cible à adopter parmi : `off`, `cool`, `dry`, `fan_only` et `heat` :
```js
const minHumidityThreshold = 52;
const maxHumidityThreshold = 57;

// Helper: check if mode can be activated or stopped
function isModeEligible(mode, temps, humidity, thresholds, currentMode) {
    const isCurrent = (mode === currentMode);
    const threshold = thresholds[mode];

    if (msg.payload.disabled?.[mode]) return false;

    // Determine which temperature to use for start/stop:
    // start: temp.max (except heat uses temp.min)
    // stop: temp.avg
    let tempForCheckStart;
    if (mode === "heat") {
        tempForCheckStart = temps.min;  // heat start uses min temp
    } else {
        tempForCheckStart = temps.max;  // others start use max temp
    }
    const tempForCheckStop = temps.avg;

    // Dry mode also depends on humidity thresholds
    // humidity max for start, humidity avg for stop
    let humidityForCheckStart = humidity.max;
    let humidityForCheckStop = humidity.avg;

    // For heat mode (inverted logic)
    if (mode === "heat") {
        if (!isCurrent) {
            const minStart = Math.min(...Object.values(threshold.start));
            return tempForCheckStart < minStart;
        } else {
            return tempForCheckStop < threshold.stop;
        }
    }

    // For dry mode (humidity-dependent)
    if (mode === "dry") {
        // Skip if humidity too low
        if (humidityForCheckStart <= (isCurrent ? minHumidityThreshold : maxHumidityThreshold)) return false;

        const minStart = Math.min(...Object.values(threshold.start));
        if (!isCurrent) {
            return tempForCheckStart >= minStart;
        } else {
            return tempForCheckStop >= threshold.stop;
        }
    }

    // For cool and fan_only
    if (!isCurrent) {
        const minStart = Math.min(...Object.values(threshold.start));
        return tempForCheckStart >= minStart;
    } else {
        return tempForCheckStop >= threshold.stop;
    }
}

// --- Main logic ---
const { threshold, temp, humidity, current_mode, disabled } = msg.payload;

const priority = ["cool", "dry", "fan_only", "heat"];
let target_mode = "off";

// Loop through priority list and stop at the first eligible mode
for (const mode of priority) {
    if (isModeEligible(mode, temp, humidity, threshold, current_mode)) {
        target_mode = mode;
        break;
    }
}

msg.payload.target_mode = target_mode;

if (target_mode === "cool" || target_mode === "heat") {
  msg.payload.set_temp = true;
}

return msg;
```

Le second compare le mode actuel avec le mode cible et choisit l’action à effectuer :
- **check** : le mode actuel est identique au mode cible.
- **start** : l’unité est éteinte, mais un mode actif est requis.
- **change** : l’unité est allumée, mais le mode cible est différent du mode actuel (et n’est pas `off`).
- **stop** : l’unité est allumée mais doit être arrêtée.
```js
let action = "check"; // default if both are same

if (msg.payload.current_mode === "off" && msg.payload.target_mode !== "off") {
    action = "start";
} else if (msg.payload.current_mode !== "off" && msg.payload.target_mode !== "off" && msg.payload.current_mode !== msg.payload.target_mode) {
    action = "change";
} else if (msg.payload.current_mode !== "off" && msg.payload.target_mode === "off") {
    action = "stop";
}

msg.payload.action = action;
return msg;
```

Le dernier nœud détermine la vitesse de ventilation appropriée pour le mode cible, en fonction des seuils définis :
```js
// Function to find the appropriate speed key based on temperature and mode
function findSpeed(thresholdStart, temperature, mode) {
  let closestSpeed = 'quiet';
  let closestTemp = mode === 'heat' ? Infinity : -Infinity;

  for (const speedKey in thresholdStart) {
    if (speedKey !== 'quiet') {
      const tempValue = thresholdStart[speedKey];
      if (mode === 'heat') {
        if (tempValue >= temperature && tempValue <= closestTemp) {
          closestSpeed = speedKey;
          closestTemp = tempValue;
        }
      } else { // cool, fan_only
        if (tempValue <= temperature && tempValue >= closestTemp) {
          closestSpeed = speedKey;
          closestTemp = tempValue;
        }
      }
    }
  }
  return closestSpeed;
}

if (msg.payload.target_mode && msg.payload.target_mode !== "off" && msg.payload.target_mode !== "dry") {
  const modeData = msg.payload.threshold[msg.payload.target_mode];
  if (modeData && modeData.start) {
    if (msg.payload.target_mode === "heat") {
      msg.payload.speed = findSpeed(modeData.start, msg.payload.temp.min, 'heat');
    } else {
      msg.payload.speed = findSpeed(modeData.start, msg.payload.temp.max, 'cool');
    }
  } else {
    node.error("Invalid mode data or missing 'start' thresholds", msg);
  }
} else {
  // No need for speed in 'off' or 'dry' modes
  msg.payload.speed = null;
}

return msg;
```

#### 11. Choix de l'Action

En fonction de l’action à effectuer, le `switch node` va router le message vers le bon chemin :  
![Node-RED `switch node` pour sélectionner l’action](img/node-red-switch-node-select-action.png)

#### 12. Démarrage

Lorsque l’action est `start`, il faut d’abord allumer l’unité. Cela prend entre 20 et 40 secondes selon le modèle, et une fois démarrée, l’unité est verrouillée pendant un court laps de temps pour éviter les messages suivants.

Le premier nœud est un `call service node` utilisant le service `turn_on` sur l’unité de climatisation :  
![Node-RED call service node with turn_on service](img/node-red-call-service-node-turn-on.png)

Le second nœud est un autre `call service node` qui va démarrer un minuteur de verrouillage (lock timer) pour cette unité pendant 45 secondes :  
![Node-RED call service node to start the unit timer](img/node-red-call-service-node-start-timer.png)

Le dernier est un `delay node` de 5 secondes, pour laisser le temps à l’intégration Daikin de Home Assistant de refléter le nouvel état.

---

#### 13. Changement

L’action `change` est utilisée pour passer d’un mode à un autre, mais aussi juste après l’allumage.

Le premier nœud est un `call service node` utilisant le service `set_hvac_mode` sur l’unité de climatisation :  
![Node-RED call service node with set_hvac_mode service](img/node-red-call-service-node-set-hvac-mode.png)

Le nœud suivant est un `delay node` de 5 secondes.

Le dernier vérifie, avec un `switch node`, si la température cible doit être définie. Cela n’est nécessaire que pour les modes `cool` et `heat` :  
![Node-RED switch node for set_temp](img/node-red-switch-node-set-temp.png)

---

#### 14. Définir la Température Cible

La température cible est uniquement pertinente pour les modes `cool` et `heat`. Avec une climatisation classique, vous définissez une température à atteindre — c’est exactement ce qu’on fait ici. Mais comme chaque unité utilise son propre capteur interne pour vérifier cette température, je ne leur fais pas vraiment confiance. Si la température cible est déjà atteinte selon l’unité, elle ne soufflera plus du tout.

Le premier nœud est un autre `call service node` utilisant le service `set_temperature` :  
![Node-RED call service node with set_temperature service](img/node-red-call-service-node-set-temperature-service.png)

Encore une fois, ce nœud est suivi d’un `delay node` de 5 secondes.

#### 15. Vérification

L’action `check` est utilisée presque tout le temps. Elle consiste uniquement à vérifier et comparer la vitesse de ventilation souhaitée, et à la modifier si nécessaire.

Le premier nœud est un `switch node` qui vérifie si la valeur `speed` est définie :  
![Node-RED switch node to test if speed is defined](img/node-red-switch-node-fan-speed.png)

Le deuxième est un autre `switch node` qui compare la valeur `speed` avec la vitesse actuelle :  
![Node-Red switch node to compare speed](img/node-red-switch-node-compare-speed.png)

Enfin, le dernier nœud est un `call service node` utilisant le service `set_fan_mode` pour définir la vitesse du ventilateur :  
![Node-RED call service node with set_fan_mode](img/node-red-call-service-node-set-fan-mode.png)

#### 16. Arrêt

Lorsque l’action est `stop`, l’unité de climatisation est simplement arrêtée.

Le premier nœud est un `call service node` utilisant le service `turn_off` :  
![Node-RED call service node with turn_off service](img/node-red-call-service-node-turn-off.png)

Le deuxième nœud est un autre `call service node` qui va démarrer le minuteur de verrouillage de cette unité pour 45 secondes.

#### 17. Intervention Manuelle

Parfois, pour une raison ou une autre, on souhaite utiliser la climatisation manuellement. Dans ce cas, on ne veut pas que le flux Node-RED vienne écraser notre réglage manuel, du moins pendant un certain temps.  
Node-RED utilise son propre utilisateur dans Home Assistant, donc si une unité change d’état sans cet utilisateur, c’est qu’une intervention manuelle a eu lieu.

Le premier nœud est un `trigger state node`, qui envoie un message dès qu’une unité AC change d’état :  
![node-red-trigger-state-unit-change.png](img/node-red-trigger-state-unit-change.png)

Le deuxième est un `function node` qui associe l’unité avec son minuteur :
```js
const association = {
    "climate.clim_salon": "timer.minuteur_clim_salon",
    "climate.clim_chambre": "timer.minuteur_clim_chambre",
    "climate.clim_couloir": "timer.minuteur_clim_couloir"
};

msg.payload = association[msg.topic]; 
return msg;
```

Le troisième est un `switch node` qui laisse passer le message uniquement si le `user_id` **n’est pas** celui de Node-RED :  
![Node-RED switch node not specific user_id](img/node-red-switch-node-user-id.png)

Le quatrième est un autre `switch node` qui vérifie que le champ `user_id` **est bien défini** :  
![Node-RED switch node check user_id not null](img/node-red-switch-node-check-user-id.png)

Enfin, le dernier nœud est un `call service node` utilisant le service `start` sur le minuteur de l’unité, avec sa durée par défaut (60 minutes) :  
![Node-RED call service node start timer with default duration](img/node-red-call-service-node-start-unit-timer.png)

## TL;DR

Avec cette configuration, mon système de climatisation est entièrement automatisé, du refroidissement en été au chauffage en hiver, tout en gardant un œil sur le taux d’humidité.

Cela m’a demandé pas mal de réflexion, d’ajustements et de tests, mais au final je suis vraiment satisfait du résultat. C’est pourquoi je le partage ici, pour vous donner des idées sur ce qu’on peut faire en domotique.

Si vous pensez que certaines choses pourraient être faites autrement, n’hésitez pas à me contacter pour en discuter ou me proposer de nouvelles idées !

