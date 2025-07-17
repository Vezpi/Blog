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

In this post, I’ll walk through each step of the installation process of a simple Kubernetes cluster, from preparing the nodes to deploying a basic application.

I will not rely on automation tools to configure the nodes for now, to better understand what are the steps involved in a Kubernetes cluster bootstrapping. Automation will be covered in future posts.

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

### OS Updates

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

For this lab, I will just disable the local firewall (don't do that in production):
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
| Protocol | Direction | Port Range  | Purpose            | Used By              |
| -------- | --------- | ----------- | ------------------ | -------------------- |
| TCP      | Inbound   | 10250       | Kubelet API        | Self, Control plane  |
| TCP      | Inbound   | 10256       | kube-proxy         | Self, Load balancers |
| TCP      | Inbound   | 30000-32767 | NodePort Services† | All                  |

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

Enable `systemd` *cgroup* driver:
```bash
sudo sed -i 's/^\(\s*SystemdCgroup\s*=\s*\)false/\1true/' /etc/containerd/config.toml
```

Restart and enable the `containerd` service
```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Kubernetes Packages

Last step: install the Kubernetes packages. I start with adding the repository and its signing key.

Add the key:
```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Add the repository:
```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Finally I can install the needed packages:
- `kubeadm`: the command to bootstrap the cluster.
- `kubelet`: the component that runs on all of the machines in your cluster and does things like starting pods and containers.
- `kubectl`: the command line util to talk to your cluster.

On the nodes, update the `apt` package index, install `kubelet` and `kubeadm`, and pin their version:
```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm
sudo apt-mark hold kubelet kubeadm
```

ℹ️ I will not manage the cluster from my nodes, I install `kubectl` on my LXC controller instead:
```bash
sudo apt-get update
sudo apt-get install -y kubectl
sudo apt-mark hold kubectl
```

---
## Initialize the Cluster

Once all nodes are prepared, it’s time to initialize the Kubernetes control plane on the **first master node**.

### Initialization
Run the following command to bootstrap the cluster:
```bash
sudo kubeadm init \
  --control-plane-endpoint "apex-master.lab.vezpi.me:6443" \
  --upload-certs \
  --pod-network-cidr=10.10.0.0/16
```

**Explanation**:
- `--control-plane-endpoint`: a DNS name for your control plane.
- `--upload-certs`: Upload the certificates that should be shared across all the control-plane instances to the cluster.
- `--pod-network-cidr`: The subnet for your CNI.

This step will:
- Initialize the `etcd` database and control plane components.
- Set up RBAC and bootstrap tokens.
- Output two important `kubeadm join` commands: one for **workers**, and one for **additional control-plane nodes**.

You’ll also see a message instructing you to set up your `kubectl` access.

### Configure `kubectl` 

If you want to manage your cluster from your master node, you can simply copy paste from the output of the `kubeadm init` command:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

If you prefer to control the cluster from elsewhere, in my case my from my LXC bastion:
```bash
mkdir -p $HOME/.kube
scp <master node>:/etc/kubernetes/admin.conf $HOME/.kube/config
chmod 600 ~/.kube/config
```

Verify your access:
```bash
kubectl get nodes
```

ℹ️ You should see only the first master listed (in "NotReady" state until the CNI is deployed).

### Install the CNI plugin Cilium

From the [Cilium documentation](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/), there are 2 common ways for installing the CNI: using the **Cilium CLI** or **Helm**, for that lab I will use the CLI tool.

#### Install the Cilium CLI

The Cilium CLI can be used to install Cilium, inspect the state of a Cilium installation, and enable/disable various features (e.g. `clustermesh`, `Hubble`):
```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}
```

#### Install Cilium

Install Cilium into the Kubernetes cluster pointed to by your current kubectl context:
```bash
cilium install --version 1.17.6
```

#### Validate the installation

To validate that Cilium has been properly installed, you can run:
```bash
cilium status --wait
```

Run the following command to validate that your cluster has proper network connectivity:
```bash
cilium connectivity test
```

Once installed, the master node should transition to **Ready** status.

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


