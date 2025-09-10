---
slug: opnsense-virtualizaton-highly-available
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - proxmox
categories:
  - homelab
---
## Intro

I recently encountered my first real problem, my physical **OPNsense** box crashed because of a kernel panic, I've detailed what happened in that [post]({{< ref "post/10-opnsense-crash-disk-panic" >}}).

After this event, I came up with an idea to enhance the stability of the lab: **Virtualize OPNsense**.

The idea is pretty simple on paper, create an OPNsense VM on the **Proxmox** cluster and replace the current physical box by this VM. The challenge would be to have both the LAN and the WAN on the same physical link, involving serious 
This would require some modification at the network level and is quite critical to implement.