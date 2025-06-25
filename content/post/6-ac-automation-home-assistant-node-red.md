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

In my apartment I have a Daikin air conditioning system, to cool it down in summer, but also warm it up in winter. It is composed of 3 indoor units:
- Living room
- Master bedroom
- Hallway (in front of my office and my kid's room)

I always find it boring to have to turn them on when I needed, I forgot to turn them off when I should and I was constantly chasing the remote.

What if I could automate it? After all, I already use Home Assistant to control many devices at home, controlling the AC seems natural to me. 

### Home Assistant

Home Assistant is the brain of my smart home. It connects all my devices (lights, sensors, shutters, etc.) under a single interface. What makes it so powerful is the ability to create automations: if something happens, then do something else. Simple things like “turn on the kitchen light when the motion sensor is triggered” are a breeze. For more advanced workflows, it offers YAML-based scripts with conditions, delays, triggers, and templates.

That said, once automations start getting more complex, like reacting to multiple sensors, time ranges, or presence detection, they can quickly turn into long, hard-to-follow blocks of code. It’s easy to lose track of what does what, especially when you want to tweak just one small part weeks later.

### Node-RED

That’s exactly why I turned to Node-RED. It’s a visual tool that lets you build logic using blocks called “nodes,” which you connect with wires to create flows. Each node performs a small task: trigger at a certain time, check a condition, send a command to a device, etc. Instead of writing YAML, you just drag, drop, and connect.

Node-RED does not replace Home Assistant, it empowers it. I won't cover the installation of Node-RED neither the integration in HA, I've done that 2 years ago, but for that I remember, this is quite straightforward.

## Previous Workflow

I was already having a good solution to control my AC from Home Assistant with Node-RED, but I wanted to enhance it to also handle the humidity level at home. My current workflow, despite being functional, was not really scalable and quite hard to maintain.
![Ancien workflow Node-RED pour contrôler la climatisation](img/node-red-ha-ac-automation-before.png)

## New Workflow

Instead of tweaking this workflow, I created a new one from scratch, with the same goal in mind: control the AC system by taking into account all available sensors: thermometers, humidity, door sensors, occupant presence, time of day, etc.

### Objectives

The idea is pretty simple: do not having to think about AC while still being efficient.

That being said, what does that mean? I want to keep the temperature and humidity level in check, whenever I'm here or not. If I open the windows, it should stop blowing. If it is too wet, I want to dry the air. If I turn the AC on or off manually, I don't want it to overwrite my setting. If it's night, I don't need to cool my living-room and I want it quiet, etc.

To help me achieve that, I'm using 4 [Aqara temperature and humidity sensors](https://eu.aqara.com/en-eu/products/aqara-temperature-and-humidity-sensor), one in each of my main room. I'm also using some [Aqara door sensors](https://eu.aqara.com/en-eu/products/aqara-door-and-window-sensor, to detect it windows are open.

### Workflow

Let me introduce my new AC workflow within Node-RED and explain what it does in detail 

![New Node-RED air conditioning workflow](img/node-red-new-ac-workflow-with-legend.png)

#### 1. Temperature Sensors

In the first node, I combined all the temperature sensors together in one `trigger state node`, but I also added humidity levels in addition to the temperature, managed by the sensor. The node then contains 8 entities in a list (2 for each of my sensor). Each time one value change out of these 8 entities, the node is triggered:
![Nœud trigger state dans Node-RED avec les 8 entités](img/node-red-temperature-sensors-trigger-node.png)

Each of my temperature sensors are named with a color in French, because each has its own color sticker to distinguish them:
- **Jaune**: Living room
- **Bleu**: Bedroom
- **Rouge**: Office
- **Vert**: Kid's bedroom

The second node is a `function node` which has the role the determine the room of the sensor (`function node` is written in **JavaScript**):
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

For the last node, most of the time, the sensors will send two messages at the same time, one containing the temperature value and the other, the humidity level. I added a `join node` to combined the two messages if they are sent within the same second:
![Join node in Node-RED to merge temperature and humidity](img/node-red-temperature-sensor-join-node.png)

#### 2. Notification

It can happen that the temperature sensors are not sending states anymore for some reason. In that case, they will always return their last value, which would lock the associated AC unit.

The workaround I found effective is to send a notification if the sensor did not send a new value in the last 3 hours. In normal situation, the sensor send an update approximately every 15 minutes.

The first node is a `function node` a bit tricky which will generate flow variable as timer for each sensor. When the timeout is reach, it sends a message to the next node:
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

The second node is a `call service node` which send a notification on my Android device with the value given:
![Node-RED call service node for notification](img/node-red-call-service-node-notification.png)

#### 3. Temperature Sliders

To have a control over the temperature without having to change the workflow, I created two Home Assistant helper, as number, which I can adjust for each unit, giving me 6 helpers in total:
![Curseur de température dans Home Assistant pour chaque unité](img/home-assistant-temperature-room-sliders.png)

These values are the base temperature used for the calculation of the threshold, depending off the offset which I will detail further.

The first node is a `trigger state node`, with all 6 entities combined. If I change one value, the node is triggered:
![Node-RED trigger state node for sliders](img/node-red-trigger-state-nmode-for-sliders.png)

The second node is a `function node`, to determine the room affected:
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

#### 4. Toggles

In Home Assistant, I'm using other helper but as boolean, the most important is the AC one, where I can manually disable the whole workflow. I have other which are automated, for the time of the day or for detect presence at home.

I have another `trigger state node` with all my toggles as boolean, including a test button, for debug purpose:
![Node-RED trigger state node for toggles](img/node-red-trigger-state-node-toggles.png)

As toggles affect the whole apartment and not a single unit, the next node is a `change node`, which set the room value to `partout` (everywhere):
![Node-RED change node to set room to partout](img/node-red-change-node-room-partout.png)

#### 5. Windows

The last triggers are my windows, if I open or close a window next to my unit, it triggers the workflow. I have door sensor for some of my doors, but for the hallway unit, I'm using the Velux windows state. Some rooms have more than one, I created a group helper for them.

The first node is the last `trigger state node`, the returned value is a string which I will have to convert later into boolean:
![Node-RED trigger state node for windows](img/node-red-trigger-state-node-windows.png)

Connected to it, again a `function node` to select the affect room:
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

#### 6. Window Watchdog

When I open a window, it is not necessarily to let it open for a long time. I could just let the cat out or having a look at my portal. I don't want my AC tuned off as soon as open it. To workaround that I created a watchdog for each unit, to delay the message for some time.

The first node is a `switch node`, based on the room given by the previous node, it will send the message to the associated watchdog:
![Node-RED switch node based on the room for the watchdog](img/node-red-switch-node-room-selector-watchdog.png)

After are the watchdogs, `trigger nodes`, which will delay the message by some time and extend the delay if another message if received:
![Node-RED trigger node for window watchdog](img/node-red-trigger-node-window-watchdog.png)

#### 7. AC Enabled ?

All these triggers are now entering the computing pipeline, to determine what the system must do with the action. But before, it is checking if the automation is even enabled. I add this kill switch, just in case, but I rarely use it anyway.

The first node is a `delay node` which regulate the rate of every incoming messages to 1 per second:
![Node-RED delay node to limit the rate to 1 message per second](img/node-red-delay-node-1-msg-per-second.png)

The second node is a `current state node` which checks if the `climatisation` boolean is enabled:
![Node-RED current state node for climatisation](img/node-red-current-state-node-climatisation-enabled.png)
#### 8. Room Configuration

The idea here is to attach the configuration of the room to the message. Each room have their own configuration, which unit is used, which sensors and more importantly, when should they be turned on and off. 

AC units have 4 mode which can be used:
- Cool
- Dry
- Fan
- Heat

To determine which mode should be used, I'm using threshold for each mode and unit fan's speed, with different offset depending the situation. I can then define a offset during the night or when I'm away. I can also set the offset to `disabled`, which will force the unit to shut down.

The first node is a `switch node`, based on the `room` value, which will route the message to the associated room configuration. When the room is `partout` (everywhere), the message is split to all 3 room configuration:
![Node-RED switch node for room configuration](img/node-red-switch-node-room-config.png)

It is connected to a `change node` which will attach the configuration to the `room_config`, here an example with the living-room configuration:
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