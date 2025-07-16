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

I will not rely on automation tools to configure the nodes for now, to better understand what are the steps involved in a Kubernetes cluster bootstrapping.

---
## What is Kubernetes

Kubernetes is an open-source platform for orchestrating containers across a group of machines. It handles the deployment, scaling, and health of containerized applications, allowing you to focus on building your services rather than managing infrastructure details.

A Kubernetes cluster is made up of two main types of nodes: control plane (masters) nodes and worker nodes. The control plane is responsible for the overall management of the cluster, it makes decisions about scheduling, monitoring, and responding to changes in the system. The worker nodes are where your applications actually run, inside containers managed by Kubernetes.

In this post, we’ll manually set up a Kubernetes cluster with 3 control plane nodes (masters) and 3 workers. This structure reflects a highly available and production-like setup, even though the goal here is mainly to learn and understand how the components fit together.

The official documentation can be found [here](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/), I will use the version **v1.32**.

---
## Prepare the Nodes

I will perform the following steps on all 6 VMs (masters and workers).

### Hostname

Each VM has a unique **hostname** and all nodes must **resolve** each other.

The hostname is set upon the VM creation with cloud-init. But for demonstration purpose, I'll set it manually:
```bash
sudo hostnamectl set-hostname <hostname>
```

On my infrastructure, the nodes resolve the hostnames each other using my DNS server on that domain (`lab.vezpi.me`). In case you don't have a DNS server, you can hardcode the nodes IP in each `/etc/hosts` file:
```bash
192.168.66.168 apex-worker
192.168.66.167 apex-master
192.168.66.166 zenith-master
192.168.66.170 vertex-worker
192.168.66.169 vertex-master
192.168.66.172 zenith-worker
```

### 
OS Updates

My VMs are running **Ubuntu 24.04.2 LTS**. Cloud-init handles the updates after the provision in that case, let's make sure everything is up to date and install packages needed to add Kubernetes repository:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gpg
```

### Swap

The default behavior of a `kubelet` is to fail to start if **swap memory** is detected on a node. This means that swap should either be disabled or tolerated by `kubelet`. 

My VMs are not using swap, but here how to disable it:
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Firewall

For testing environment, I will just disable the local firewall (don't do that in production):
```bash
sudo systemctl disable --now ufw
```

For production, you want to allow the nodes to talk to each other on these ports:
#### Control plane
|Protocol|Direction|Port Range|Purpose|Used By|
|---|---|---|---|---|
|TCP|Inbound|6443|Kubernetes API server|All|
|TCP|Inbound|2379-2380|etcd server client API|kube-apiserver, etcd|
|TCP|Inbound|10250|Kubelet API|Self, Control plane|
|TCP|Inbound|10259|kube-scheduler|Self|
|TCP|Inbound|10257|kube-controller-manager|Self|

#### Worker
|Protocol|Direction|Port Range|Purpose|Used By|
|---|---|---|---|---|
|TCP|Inbound|10250|Kubelet API|Self, Control plane|
|TCP|Inbound|10256|kube-proxy|Self, Load balancers|
|TCP|Inbound|30000-32767|NodePort Services†|All

### Kernel Modules and Settings

Kubernetes needs 2 kernel modules:
- **overlay**: for facilitating the layering of one filesystem on top of another
- **br_netfilter**: for enabling bridge network connections

Let's enable them:
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Some kernel settings related to network are also needed:
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Container Runtime

You need to install a **container runtime** into each node in the cluster so that Pods can run there. I will use `containerd`:
```bash
sudo apt install -y containerd
```

Create the default configuration:
```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
```

Enable `systemd` cgroup driver:
```bash
sudo sed -i 's/^\(\s*SystemdCgroup\s*=\s*\)false/\1true/' /etc/containerd/config.toml
```

Restart `containerd` service
```bash
sudo systemctl restart containerd
```


	
    Installing kubeadm and kubelet

    Installing kubeadm on bastion


	
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


