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
![Ancien workflow Node-RED du contrôle de la climatisation](img/node-red-ha-ac-automation-before.png)

Instead of tweaking this workflow, I created a new one from scratch, with the same goal in mind: control the AC system by taking into account all available sensors: thermometers, humidity, door sensors, occupant presence, time of day, etc.

## New Workflow








![node-red-new-ac-workflow-with-legend.png](img/node-red-new-ac-workflow-with-legend.png)