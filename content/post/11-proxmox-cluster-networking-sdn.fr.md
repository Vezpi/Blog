---
slug: proxmox-cluster-networking-sdn
title: Simplifier la gestion des VLAN dans Proxmox VE avec le SDN
description: Découvrez comment centraliser la configuration des VLAN dans Proxmox VE grâce aux zones SDN et aux VNets, pour un réseau plus simple et cohérent.
date: 2025-09-12
draft: false
tags:
  - proxmox
categories:
  - homelab
---

## Intro

Quand j’ai construit mon cluster **Proxmox VE 8** pour la première fois, le réseau n’était pas ma priorité. Je voulais simplement remplacer rapidement un vieux serveur physique, alors j’ai donné la même configuration de base à chacun de mes trois nœuds, créé le cluster et commencé à créer des VM :  
![Configuration réseau d’un nœud Proxmox](img/proxmox-node-network-configuration.png)

Cela a bien fonctionné pendant un moment. Mais comme je prévois de virtualiser mon routeur **OPNsense**, j’ai besoin de quelque chose de plus structuré et cohérent. C’est là que la fonctionnalité **S**oftware-**D**efined **N**etworking (SDN) de Proxmox entre en jeu.

---
## Mon Réseau Homelab

Par défaut, chaque nœud Proxmox dispose de sa propre zone locale, appelée `localnetwork`, qui contient le pont Linux par défaut (`vmbr0`) comme VNet :  
![Proxmox default `localnetwork` zones](img/proxmox-default-localnetwork-zone.png)

C’est suffisant pour des configurations isolées, mais rien n’est coordonné au niveau du cluster.

Mon objectif est simple : déclarer les VLAN que j’utilise déjà dans mon réseau, afin de pouvoir y rattacher des VM facilement depuis n’importe quel nœud.

Voici la liste des VLAN que j’utilise actuellement :

| Nom       | ID   | Usage                          |
| --------- | ---- | ------------------------------ |
| Mgmt      | 1    | Administration                 |
| User      | 13   | Réseau domestique              |
| IoT       | 37   | IoT et équipements non fiables |
| DMZ       | 55   | Services exposés à Internet    |
| Lab       | 66   | Réseau de lab                  |
| Heartbeat | 77   | Heartbeat du cluster Proxmox   |
| Ceph      | 99   | Stockage Ceph                  |
| VPN       | 1337 | Réseau WireGuard               |

---
## Aperçu du SDN Proxmox

Le Software-Defined Networking de Proxmox permet de définir des zones et réseaux virtuels à l’échelle du cluster. Au lieu de répéter la configuration des VLAN sur chaque nœud, le SDN offre une vue centralisée et assure la cohérence.

En interne, Proxmox repose essentiellement sur les fonctionnalités réseau standard de Linux, ce qui évite d’ajouter des dépendances externes et garantit la stabilité.

Les configurations SDN sont stockées dans `/etc/pve/sdn` et répliquées sur l’ensemble du cluster. Les changements sont appliqués de manière atomique (on prépare les modifications puis on clique sur `Apply`), ce qui rend les déploiements plus sûrs.

### Zones

Une **Zone** définit un domaine réseau séparé. Les zones peuvent couvrir certains nœuds et contenir des **VNets**.

Proxmox prend en charge plusieurs types de zones :
- **Simple** : pont isolé (bridge) avec routage L3/NAT
- **VLAN** : segmentation classique via VLAN
- **QinQ** : empilement de VLAN (IEEE 802.1ad)
- **VXLAN** : réseau L2 via encapsulation UDP
- **EVPN** : VXLAN avec BGP pour du routage L3 dynamique

Comme mon réseau domestique utilise déjà des VLAN, j’ai créé une **zone VLAN** appelée `homelan`, en utilisant `vmbr0` comme pont et en l’appliquant à tout le cluster :  
![Create a VLAN zone in the Proxmox SDN](img/proxmox-create-vlan-zone-homelan.png)

### VNets

Un **VNet** est un réseau virtuel à l’intérieur d’une zone. Dans une zone VLAN, chaque VNet correspond à un ID VLAN spécifique.

J’ai commencé par créer `vlan55` dans la zone `homelan` pour mon réseau DMZ :  
![Create a VNet for VLAN 55 in the homelan zone](img/proxmox-create-vlan-vnet-homelan.png)

Puis j’ai ajouté les VNets correspondant à la plupart de mes VLAN, puisque je prévois de les rattacher à une VM OPNsense :  
![All my VLANs created in the Proxmox SDN](img/proxmox-sdn-all-vlan-homelan.png)

Enfin, j’ai appliqué la configuration dans **Datacenter → SDN** :  
![Application de la configuration SDN dans Proxmox](img/proxmox-apply-sdn-homelan-configuration.png)

---
## Test de la Configuration Réseau

Dans une vieille VM que je n'utilise plus, je remplace l'actuel `vmbr0` avec le VLAN tag 66 par mon nouveau VNet `vlan66`:
![Change the network bridge in a VM](img/proxmox-change-vm-nic-vlan-vnet.png)

Après l'avoir démarrée, la VM obtient une IP du DHCP d'OPNsense sur ce VLAN, ce qui est super. J'essaye également de ping une autre machine et ça fonctionne :
![Ping another machine in the same VLAN](img/proxmox-console-ping-vm-vlan-66.png)

---
## Mise à jour de Cloud-Init et Terraform

Pour aller plus loin, j’ai mis à jour le pont réseau utilisé dans mon **template cloud-init**, dont j'avais détaillé la création dans [cet article]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}).  
Comme avec la VM précédente, j’ai remplacé `vmbr0` et le tag VLAN 66 par le nouveau VNet `vlan66`.

J’ai aussi adapté mon code **Terraform** pour refléter ce changement :  
![Mise à jour du code Terraform pour vlan66](img/terraform-code-update-vlan66.png)

Ensuite, j’ai validé qu’aucune régression n’était introduite en déployant une VM de test :
```bash
terraform apply -var 'vm_name=vm-test-vnet'
```
```plaintext
data.proxmox_virtual_environment_vms.template: Reading...
data.proxmox_virtual_environment_vms.template: Read complete after 0s [id=23b17aea-d9f7-4f28-847f-41bb013262ea]
[...]
Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + vm_ip = (known after apply)

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

proxmox_virtual_environment_file.cloud_config: Creating...
proxmox_virtual_environment_file.cloud_config: Creation complete after 1s [id=local:snippets/vm.cloud-config.yaml]
proxmox_virtual_environment_vm.vm: Creating...
proxmox_virtual_environment_vm.vm: Still creating... [10s elapsed]
[...]
proxmox_virtual_environment_vm.vm: Still creating... [3m0s elapsed]
proxmox_virtual_environment_vm.vm: Creation complete after 3m9s [id=119]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

vm_ip = "192.168.66.181"
```

La création s’est déroulée sans problème, tout est bon :
![VM déployée par Terraform sur vlan66](img/proxmox-terraform-test-deploy-vlan66.png)

---
## Conclusion

La mise en place du SDN Proxmox avec une **zone VLAN** est simple et très pratique. Au lieu de définir manuellement un VLAN sur chaque VM, je sélectionne désormais directement le bon VNet, et tout reste cohérent dans le cluster.

| Étape                | Avant SDN                     | Après SDN                           |
| -------------------- | ----------------------------- | ----------------------------------- |
| Rattacher une VM     | `vmbr0` + tag VLAN manuel     | Sélection du VNet approprié         |
| VLANs sur les nœuds  | Config répété sur chaque nœud | Centralisé via le SDN du cluster    |
| Gestion des adresses | Manuel ou via DHCP uniquement | IPAM optionnel via sous-réseaux SDN |

Mon cluster est maintenant prêt à héberger mon **routeur OPNsense**, et cette base ouvre la voie à d’autres expérimentations, comme les overlays VXLAN ou l’EVPN avec BGP.

À suivre pour la prochaine étape !

