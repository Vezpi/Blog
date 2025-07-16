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

Dans cet article, je vais détailler chaque étape de l'installation d’un cluster Kubernetes simple, depuis la préparation des nœuds jusqu'au déploiement d'une application simple.

Je n'utiliserai aucun outil d'automatisation pour le moment, afin de mieux comprendre les étapes impliquées dans le bootstrap d’un cluster Kubernetes.

---
## Qu'est ce que Kubernetes

Kubernetes est une plateforme open-source qui orchestre des conteneurs sur un ensemble de machines. Elle gère le déploiement, la montée en charge et la santé des applications conteneurisées, ce qui vous permet de vous concentrer sur vos services plutôt que sur l’infrastructure sous-jacente.

Un cluster Kubernetes est composé de deux types de nœuds : les nœuds control plane (masters) et les workers. Le control plane assure la gestion globale du cluster, il prend les décisions de planification, surveille l’état du système et réagit aux événements. Les workers, eux, exécutent réellement vos applications, dans des conteneurs gérés par Kubernetes.

Dans cet article, nous allons mettre en place manuellement un cluster Kubernetes avec 3 nœuds control plane et 3 workers. Cette architecture reflète un environnement hautement disponible et proche de la production, même si l’objectif ici est avant tout pédagogique.

---
## Prepare the Nodes

    OS-level updates and basic tools

    Disabling swap and firewall adjustments

    Installing container runtime (e.g., containerd)

    Installing kubeadm and kubelet

    Installing kubeadm on bastion

    Enabling required kernel modules and sysctl settings

## Initialize the Cluster

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


