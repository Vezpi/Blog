---
slug: automate-cloud-init-template-rebuild
title: Automatiser la mise à jour d'un template Cloud-Init Proxmox avec Ansible
description: J'ai automatisé la reconstruction de mon template cloud-init Ubuntu dans Proxmox avec Ansible pour accélérer et fiabiliser le déploiement de VM Kubernetes.
date: 2026-09-13
draft: true
tags:
  - proxmox
  - cloud-init
  - ansible
  - semaphore-ui
categories:
  - homelab
---
## Introduction

J'avais déjà un template cloud-init Ubuntu dans Proxmox, basé sur la configuration décrite dans [cet article précédent]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}). Il fonctionnait bien, notamment lorsque je devais déployer plusieurs machines virtuelles avec Terraform.

Il restait cependant un problème. Chaque nouvelle VM devait encore mettre à jour ses paquets après sa création. Lorsque je déployais trois VM, l'ensemble du processus prenait plus de six minutes, dont environ la moitié était consacrée à la mise à jour des paquets.

Je vais utiliser ce template assez souvent au cours des prochains mois pour créer des clusters Kubernetes. Mettre à jour chaque VM après chaque déploiement deviendrait rapidement répétitif, j'ai donc décidé d'automatiser la reconstruction du template.

L'objectif est simple : reconstruire régulièrement le template cloud-init Ubuntu avec la dernière cloud image, afin que les nouvelles VM démarrent à partir d'une base plus récente.

## L'approche

La solution est un playbook Ansible exécuté via Semaphore UI. Le playbook s'exécute sur mes nœuds Proxmox et prend en charge tout le cycle de vie du template :

- Vérifier si le template existe déjà.
- Vérifier si la cloud image Ubuntu actuelle est disponible.
- Trouver l'hôte Proxmox qui doit effectuer la reconstruction.
- Télécharger la dernière image lorsque cela est nécessaire.
- Détruire l'ancien template lorsque l'image a changé.
- Recréer la VM et la convertir à nouveau en template.

Le playbook utilise le VMID `900` et cible actuellement la cloud image Ubuntu `noble` :

📝 Le playbook final complet est disponible sur [GitHub](https://github.com/Vezpi/Homelab/blob/main/ansible/proxmox/cloudinit_template.yml).

```yaml
vars:
  template_vmid: 900
  template_os: ubuntu
  os_release: noble

  template_name: "{{template_os}}-{{ os_release }}-cloud"

  image_filename: "{{ os_release }}-server-cloudimg-amd64.img"
  image_url: "https://cloud-images.ubuntu.com/{{ os_release }}/current/{{ image_filename }}"
  image_dest: "/var/lib/vz/template/iso/{{ image_filename }}"

  iso_storage: local
  vm_storage: ceph-workload

  template_memory: 2048
  template_cores: 1
```

Conserver ces valeurs dans des variables facilite l'adaptation du playbook à une autre version d'Ubuntu ou à un autre template.

## Trouver le bon hôte Proxmox

Ma première exécution a échoué car le template n'existait pas sur l'hôte Proxmox sélectionné dans Semaphore UI. Cette erreur a clairement montré la limitation : le playbook ne pouvait pas supposer que le template ou son image était disponible sur un nœud précis.

Dans le cluster Proxmox, l'image peut être présente sur un hôte alors qu'un autre dispose de davantage d'espace libre. J'ai donc ajouté un petit processus de sélection.

Tout d'abord, chaque nœud vérifie si le VMID du template existe et si la cloud image est présente localement. Il enregistre également l'espace libre disponible sur le système de fichiers racine :

```yaml
- name: Check whether the template VMID already exists
  ansible.builtin.command: qm status {{ template_vmid }}
  register: template_status
  changed_when: false
  failed_when: false

- name: Check if the cloud image file exists
  ansible.builtin.stat:
    path: "{{ image_dest }}"
  register: image_exists
  changed_when: false
  failed_when: false

- name: Set candidate information
  ansible.builtin.set_fact:
    has_image_file: "{{ image_exists.stat.exists }}"
    root_free_space: "{{ (ansible_facts['mounts'] | selectattr('mount', 'equalto', '/') | first).size_available }}"
```

L'hôte cible est ensuite sélectionné en deux étapes. Un nœud qui possède déjà l'image est privilégié. Si aucun nœud ne la possède, le playbook choisit celui qui dispose du plus grand espace disponible :

```yaml
- name: Select target host
  ansible.builtin.set_fact:
    target_host: >-
      {{ (ansible_play_hosts
          | map('extract', hostvars)
          | selectattr('has_image_file', 'equalto', true)
          | sort(attribute='root_free_space', reverse=true)
          | map(attribute='inventory_hostname')
          | first)
          | default(ansible_play_hosts
          | map('extract', hostvars)
          | sort(attribute='root_free_space', reverse=true)
          | map(attribute='inventory_hostname')
          | first,
          true) }}
  run_once: true
```

Cela évite de lier l'automatisation à un nœud Proxmox spécifique et fournit également un emplacement de repli cohérent pour le téléchargement de l'image.

## Télécharger l'image et reconstruire le template

Une fois l'hôte cible sélectionné, Ansible télécharge l'image uniquement lorsqu'elle n'est pas déjà disponible :

```yaml
- name: Download the current Ubuntu cloud image
  ansible.builtin.get_url:
    url: "{{ image_url }}"
    dest: "{{ image_dest }}"
    force: false
    mode: "0644"
  register: image_download
  when: inventory_hostname == target_host
```

Le résultat de cette tâche est important. Le template existant est détruit uniquement lorsqu'une nouvelle image a été téléchargée. Si le template est absent, le playbook le reconstruit également :

```yaml
- name: Destroy existing template if present
  ansible.builtin.command: qm destroy {{ template_vmid }} --purge
  when:
    - template_status.rc == 0
    - image_download.changed
```

La VM est ensuite créée avec la même configuration principale que mon template d'origine : deux gigaoctets de mémoire, un cœur CPU, UEFI, un disque EFI, une interface réseau VirtIO et une console série.

```yaml
- name: Create the base VM shell
  ansible.builtin.command: >
    qm create {{ template_vmid }}
    --memory {{ template_memory }}
    --core {{ template_cores }}
    --net0 virtio,bridge=vmbr0
    --scsihw virtio-scsi-pci
    --bios ovmf
    --machine q35
    --efidisk0 {{ vm_storage }}:0,pre-enrolled-keys=0
    --name {{ template_name }}

- name: Import the cloud image as the primary disk
  ansible.builtin.command: qm set {{ template_vmid }} --scsi0 {{ vm_storage }}:0,import-from={{ image_dest }}

- name: Attach a cloud-init drive
  ansible.builtin.command: qm set {{ template_vmid }} --scsi1 {{ vm_storage }}:cloudinit

- name: Set boot order to the primary disk
  ansible.builtin.command: qm set {{ template_vmid }} --boot order=scsi0

- name: Add serial console for cloud-init consoles
  ansible.builtin.command: qm set {{ template_vmid }} --serial0 socket --vga serial0

- name: Convert the VM to a template
  ansible.builtin.command: qm template {{ template_vmid }}
```

Le bloc de reconstruction s'exécute uniquement sur l'hôte sélectionné et seulement lorsque l'image a changé ou que le template n'existe pas. Les exécutions répétées restent ainsi sans effet lorsqu'il n'y a rien à mettre à jour.

## L'exécuter avec Semaphore UI

J'ai créé une tâche dans Semaphore UI pour exécuter le playbook Ansible. Le premier lancement a mis en évidence la dépendance à un hôte défini en dur. Après avoir ajouté la logique de sélection de l'hôte, le playbook s'est comporté comme prévu.

Semaphore UI me permet de lancer facilement la reconstruction manuellement lorsque cela est nécessaire. Plus important encore, il me permet de planifier la tâche : je l'ai donc configurée pour s'exécuter chaque semaine.

Le template est ainsi automatiquement actualisé, sans que je doive me souvenir de télécharger une nouvelle image Ubuntu avant de créer un cluster.

## Notifications

J'ai également ajouté une tâche de notification optionnelle à la fin du playbook. Elle envoie un message via Ntfy lorsque le template a été mis à jour :

```yaml
- name: Send notification
  ansible.builtin.uri:
    url: "{{ ntfy_url }}/{{ ntfy_topic }}"
    method: POST
    user: "{{ ntfy_user }}"
    password: "{{ lookup('env', 'NTFY_PASSWORD') }}"
    force_basic_auth: true
    body: |
      The {{ template_os | capitalize }} {{ os_release }} cloud-init template has been successfully updated on {{ inventory_hostname }}.
    headers:
      Title: "Cloud-init template updated"
      Priority: "min"
      Tags: "white_check_mark"
  when: ntfy_url is defined
```

La notification est optionnelle car la tâche est conditionnée par `ntfy_url is defined`. Je peux donc utiliser le même playbook sans configurer Ntfy, tout en recevant une confirmation discrète lorsque les notifications sont activées.

## Résultats

Après avoir fusionné le playbook dans la branche principale et planifié son exécution hebdomadaire, mon template cloud-init reste automatiquement à jour.

J'ai ensuite déployé les mêmes trois VM avec mon projet Terraform. La durée du déploiement est passée de plus de six minutes à environ trois minutes. L'étape de mise à jour des paquets n'a plus besoin d'effectuer tout le travail sur chaque nouvelle VM, car le template contient déjà une cloud image Ubuntu plus récente.

C'est particulièrement utile pour mes prochains clusters Kubernetes. Terraform peut continuer à créer les VM à partir du même template, tandis qu'Ansible se charge de le maintenir à jour en arrière-plan.

## Conclusion

Le template cloud-init initial a résolu le problème de la création de VM Proxmox cohérentes. Il manquait toutefois un moyen de le maintenir à jour sans le reconstruire manuellement.

Le playbook Ansible gère désormais ce cycle de vie et fonctionne sur l'ensemble de mon cluster Proxmox, au lieu de supposer qu'un seul nœud contient toujours le template. Semaphore UI fournit à la fois l'exécution manuelle et la planification hebdomadaire, tandis que Ntfy m'envoie une simple confirmation lorsqu'une mise à jour réussit.

Le résultat est un déploiement de VM plus rapide et une base beaucoup plus pratique pour créer des clusters Kubernetes.
