---
slug:
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - high-availability
  - proxmox
categories:
---

## Intro

In my previous post, I've set up a PoC to validate the possibility to create a cluster of 2 **OPNsense** VMs in **Proxmox VE** and make the firewall highly available.

This time, I will cover the creation of my future OPNsense cluster from scratch, plan the cut over and finally migrate from my current physical box.

## Build the Foundation

For the real thing, I'll have to connect the WAN, coming from my ISP box, to my main switch. For that I have to add a VLAN to transport this flow to my Proxmox nodes.

### UniFi

The first thing I do is to configure my layer 2 network which is managed by UniFi.

In the UniFi controller, in `Settings` > `Networks`, I add a `New Virtual Network`. I name it `WAN` and give it the VLAN ID 20:
![unifi-add-vlan-for-wan.png](img/unifi-add-vlan-for-wan.png)

I will plug my ISP box on the port 15 of my switch, which is disabled for now. I set it as active, set the native VLAN on the newly created one `WAN (20)` and disable trunking:
![unifi-enable-port-wan-vlan.png](img/unifi-enable-port-wan-vlan.png)

Once this setting applied, I make sure that only the ports where are connected my Proxmox nodes propagate this VLAN on their trunk. We are done with UniFi configuration.

### Proxmox SDN

Now that the VLAN can reach my nodes, I want to handle it in the Proxmox SDN.

In `Datacenter` > `SDN` > `VNets`, I create a new VNet, name it `vlan20` to follow my own naming convention, give it the `WAN` alias and use the tag (ID) 20:
![proxmox-sdn-new-vnet-wan.png](img/proxmox-sdn-new-vnet-wan.png)

Next I apply this configuration and we are done with the SDN.

## Create the VMs

