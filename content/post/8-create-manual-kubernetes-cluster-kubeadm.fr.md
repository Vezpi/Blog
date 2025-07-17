---
slug: create-manual-kubernetes-cluster-kubeadm
title: Template
description: 
date: 
draft: true
tags: 
categories:
---

## Intro

Dans cet [article précédent]({{< ref "post/7-terraform-create-proxmox-module" >}}), j'expliquais comment déployer 6 VMs avec **Terraform** sur **Proxmox**, 3 nœuds masters et 3 nœuds workers, en m'appuyant sur un [template cloud-init]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}).

Maintenant que l'infrastructure est prête, passons à l'étape suivante : **créer manuellement un cluster Kubernetes** avec `kubeadm`.

Dans cet article, je vais détailler chaque étape de l'installation d’un cluster Kubernetes simple, depuis la préparation des nœuds jusqu'au déploiement d'une application basique.

Je n'utiliserai pas d'outil d'automatisation pour configurer les nœuds pour le moment, afin de mieux comprendre les étapes impliquées dans le bootstrap d’un cluster Kubernetes. L'automatisation sera couverte dans de futurs articles.

---
## Qu'est ce que Kubernetes

Kubernetes est une plateforme open-source qui orchestre des containers sur un ensemble de machines. Elle gère le déploiement, la montée en charge et la santé des applications conteneurisées, ce qui vous permet de vous concentrer sur vos services plutôt que sur l’infrastructure sous-jacente.

Un cluster Kubernetes est composé de deux types de nœuds : les nœuds control plane (masters) et les workers. Le control plane assure la gestion globale du cluster, il prend les décisions de planification, surveille l’état du système et réagit aux événements. Les workers, eux, exécutent réellement vos applications, dans des containers gérés par Kubernetes.

Dans cet article, nous allons mettre en place manuellement un cluster Kubernetes avec 3 nœuds control plane et 3 workers. Cette architecture reflète un environnement hautement disponible et proche de la production, même si l’objectif ici est avant tout pédagogique.

La documentation officielle se trouve [ici](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/), je vais utiliser la version **v1.32**.

---
## Préparer les Nœuds

Je vais exécuter les étapes suivantes sur les **6 VMs** (masters et workers).

### Hostname

Chaque VM possède un **nom d’hôte unique** et tous les nœuds doivent pouvoir **se résoudre entre eux**.

Le nom d’hôte est défini à la création de la VM via cloud-init. Mais pour la démonstration, je vais le définir manuellement :
```bash
sudo hostnamectl set-hostname <hostname>
```

Dans mon infrastructure, les nœuds se résolvent via mon serveur DNS sur le domaine `lab.vezpi.me`. Si vous n’avez pas de DNS, vous pouvez inscrire manuellement les IPs des nœuds dans le fichier `/etc/hosts` :
```bash
192.168.66.168 apex-worker
192.168.66.167 apex-master
192.168.66.166 zenith-master
192.168.66.170 vertex-worker
192.168.66.169 vertex-master
192.168.66.172 zenith-worker
```

### Mises à jour Système

Mes VMs tournent sous **Ubuntu 24.04.2 LTS**. Cloud-init s’occupe des mises à jour après le provisionnement, mais on s’assure quand même que tout est bien à jour et on installe les paquets nécessaires pour ajouter le dépôt Kubernetes :
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gpg
```

### Swap

Par défaut, `kubelet` ne démarre pas si une **mémoire swap** est détectée sur un nœud. Il faut donc la désactiver ou la rendre tolérable par `kubelet`.

Mes VMs ne disposent pas de swap, mais voici comment le désactiver si besoin :
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Pare-feu

Dans ce lab, je désactive simplement le pare-feu local (à ne pas faire en production) :
```bash
sudo systemctl disable --now ufw
```

En production, vous devez autoriser la communication entre les nœuds sur les ports suivants :
#### Control Plane

| Protocole | Direction | Ports     | Usage                   | Utilisé par          |
| --------- | --------- | --------- | ----------------------- | -------------------- |
| TCP       | Entrant   | 6443      | API server Kubernetes   | Tous                 |
| TCP       | Entrant   | 2379-2380 | API client etcd         | kube-apiserver, etcd |
| TCP       | Entrant   | 10250     | API Kubelet             | Plan de contrôle     |
| TCP       | Entrant   | 10259     | kube-scheduler          | Lui-même             |
| TCP       | Entrant   | 10257     | kube-controller-manager | Lui-même             |
#### Worker

| Protocole | Direction | Ports       | Usage             | Utilisé par    |
| --------- | --------- | ----------- | ----------------- | -------------- |
| TCP       | Entrant   | 10250       | API Kubelet       | Control plane  |
| TCP       | Entrant   | 10256       | kube-proxy        | Load balancers |
| TCP       | Entrant   | 30000-32767 | Services NodePort | Tous           |
### Modules noyau et paramètres sysctl

Kubernetes requiert l’activation de deux modules noyau :
- **overlay** : pour permettre l’empilement de systèmes de fichiers.
- **br_netfilter** : pour activer le filtrage des paquets sur les interfaces bridge.

Activation des modules :
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Appliquer les paramètres noyau nécessaires pour la partie réseau :
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Runtime de Containers

Chaque nœud du cluster doit disposer d’un **runtime de containers** pour pouvoir exécuter des Pods. J’utilise ici `containerd` :
```bash
sudo apt install -y containerd
```

Créer la configuration par défaut :
```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
```

Utiliser `systemd` comme pilote de _cgroup_ :
```bash
sudo sed -i 's/^\(\s*SystemdCgroup\s*=\s*\)false/\1true/' /etc/containerd/config.toml
```

Redémarrer et activer le service `containerd` :
```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Paquets Kubernetes

Dernière étape : installer les paquets Kubernetes. On commence par ajouter le dépôt officiel et sa clé de signature.

Ajouter la clé :
```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Ajouter le dépôt :
```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Installer ensuite les paquets nécessaires :
- `kubeadm` : l’outil pour initier un cluster Kubernetes.
- `kubelet` : l’agent qui s’exécute sur tous les nœuds et qui gère les pods/containers.
- `kubectl` : l’outil en ligne de commande pour interagir avec le cluster.

Sur les nœuds, on installe `kubelet` et `kubeadm`, puis on les fige :
```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm
sudo apt-mark hold kubelet kubeadm
```

ℹ️ Je ne gérerai pas le cluster depuis les nœuds eux-mêmes, j’installe `kubectl` sur mon contrôleur LXC à la place :
```bash
sudo apt-get update
sudo apt-get install -y kubectl
sudo apt-mark hold kubectl
```

---
## Initialiser le Cluster

Une fois tous les nœuds préparés, on peut initialiser le **plan de contrôle** Kubernetes sur le **premier nœud master**.

### Initialisation

Exécutez la commande suivante pour lancer la création du cluster:
```bash
sudo kubeadm init \
  --control-plane-endpoint "apex-master.lab.vezpi.me:6443" \
  --upload-certs \
  --pod-network-cidr=10.10.0.0/16
```

**Explications** :
- `--control-plane-endpoint` : un nom DNS pour votre plan de contrôle.
- `--upload-certs` : permet d’ajouter d’autres nœuds maîtres ensuite.
- `--pod-network-cidr` : le sous-réseau à utiliser pour le réseau des Pods (compatible avec Cilium).

Cette étape va :
- Initialiser etcd et les composants du plan de contrôle.
- Configurer RBAC et les tokens d’amorçage.
- Afficher deux commandes `kubeadm join` importantes : une pour les **workers**, l’autre pour les **maîtres supplémentaires**.

Vous verrez aussi un message indiquant comment configurer l’accès `kubectl`.

## Create the Cluster

    Running kubeadm init

    Configuring kubectl on the bastion

    Installing the CNI plugin Cilium


## Join Additional Nodes

### 	Join Masters

    Creating the control-plane join command

    Syncing PKI and etcd certs

    Running kubeadm join on master 2 and 3
### 	Join Workers

    Generating and running the worker kubeadm join command

    Verifying node status


## Deploying a Sample Application

    Creating a simple Deployment and Service

    Exposing it via NodePort or LoadBalancer

    Verifying functionality

## Conclusion

    Summary of the steps

    When to use this manual method


