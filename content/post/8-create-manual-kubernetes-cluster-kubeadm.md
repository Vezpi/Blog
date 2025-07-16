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

In this [previous article]({{< ref "post/7-terraform-create-proxmox-module" >}}), I explained how to deploy 6 VMs using **Terraform** on **Proxmox**, 3 masters and 3 workers nodes, based on [cloud-init template]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}).

Now that the infrastructure is ready, let’s move on to the next step: **manually building a Kubernetes cluster** using `kubeadm`.

In this post, I’ll walk through each step of the installation process of a simple Kubernetes cluster, from preparing the nodes to deploying a simple application.

I will not rely on automation tools for now, to better understand what are the steps involved in a Kubernetes cluster bootstrapping.

---
## What is Kubernetes

Kubernetes is an open-source platform for orchestrating containers across a group of machines. It handles the deployment, scaling, and health of containerized applications, allowing you to focus on building your services rather than managing infrastructure details.

A Kubernetes cluster is made up of two main types of nodes: control plane (masters) nodes and worker nodes. The control plane is responsible for the overall management of the cluster, it makes decisions about scheduling, monitoring, and responding to changes in the system. The worker nodes are where your applications actually run, inside containers managed by Kubernetes.

In this post, we’ll manually set up a Kubernetes cluster with 3 control plane nodes (masters) and 3 workers. This structure reflects a highly available and production-like setup, even though the goal here is mainly to learn and understand how the components fit together.

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


