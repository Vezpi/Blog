---
slug: create-manual-kubernetes-cluster-kubeadm
title: Create a Highly Available Kubernetes Cluster with kubeadm on VMs
description: Step-by-step guide to manually build a highly available Kubernetes cluster on virtual machines using kubeadm
date: 2025-07-18
draft: false
tags:
  - kubernetes
  - highly-available
  - kubeadm
categories:
  - homelab
---

## Intro

In this [previous article]({{< ref "post/7-terraform-create-proxmox-module" >}}), I explained how to deploy VMs using a **Terraform** module with **Proxmox** and ended up with 6 VMs, 3 masters and 3 workers nodes, based on [cloud-init template]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}).

Now that the infrastructure is ready, let’s move on to the next step: **manually building a Kubernetes cluster** using `kubeadm`, highly available using stacked `etcd`.

In this post, I’ll walk through each step of the installation process of a Kubernetes cluster. I will not rely on automation tools to configure the nodes for now, to better understand what are the steps involved in a Kubernetes cluster bootstrapping. Automation will be covered in future posts.

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
  --control-plane-endpoint "k8s-lab.lab.vezpi.me:6443" \
  --upload-certs \
  --pod-network-cidr=10.10.0.0/16
```

**Explanation**:
- `--control-plane-endpoint`: DNS name for your control plane.
- `--upload-certs`: Upload the certificates that should be shared across all masters of the cluster.
- `--pod-network-cidr`: Subnet for the CNI.

This step will:
- Initialize the `etcd` database and control plane components.
- Set up RBAC and bootstrap tokens.
- Output two important `kubeadm join` commands: one for **workers**, and one for **additional control-plane nodes**.

ℹ️ The DNS name `k8s-lab.lab.vezpi.me` is handled in my homelab by **Unbound DNS**, this resolves on my **OPNsense** interface where a **HAProxy** service listen on the port 6443 and load balance between the 3 control plane nodes.

You’ll also see a message instructing you to set up your `kubectl` access.

```plaintext
I0718 07:18:29.306814   14724 version.go:261] remote version is much newer: v1.33.3; falling back to: stable-1.32
[init] Using Kubernetes version: v1.32.7
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
W0718 07:18:29.736833   14724 checks.go:846] detected that the sandbox image "registry.k8s.io/pause:3.8" of the container runtime is inconsistent with that used by kubeadm.It is recommended to use "registry.k8s.io/pause:3.10" as the CRI sandbox image.
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [apex-master k8s-lab.lab.vezpi.me kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.66.167]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [apex-master localhost] and IPs [192.168.66.167 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [apex-master localhost] and IPs [192.168.66.167 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "super-admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests"
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 501.894876ms
[api-check] Waiting for a healthy API server. This can take up to 4m0s
[api-check] The API server is healthy after 9.030595455s
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[upload-certs] Using certificate key:
70614009469f9fc7a97c392253492c509f1884281f59ccd7725b3200e3271794
[mark-control-plane] Marking the node apex-master as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node apex-master as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: 8etamd.g8whseg60kg09nu1
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes running the following command on each as root:

  kubeadm join k8s-lab.lab.vezpi.me:6443 --token 8etamd.g8whseg60kg09nu1 \
        --discovery-token-ca-cert-hash sha256:65c4da3121f57d2e67ea6c1c1349544c9e295d78790b199b5c3be908ffe5ed6c \
        --control-plane --certificate-key 70614009469f9fc7a97c392253492c509f1884281f59ccd7725b3200e3271794

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join k8s-lab.lab.vezpi.me:6443 --token 8etamd.g8whseg60kg09nu1 \
        --discovery-token-ca-cert-hash sha256:65c4da3121f57d2e67ea6c1c1349544c9e295d78790b199b5c3be908ffe5ed6c
```
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
rsync --rsync-path="sudo rsync" <master-node>:/etc/kubernetes/admin.conf $HOME/.kube/config
```

Verify your access:
```bash
kubectl get nodes
```

ℹ️ You should see only the first master listed (in `NotReady` state until the CNI is deployed).

### Install the CNI Plugin Cilium

From the [Cilium documentation](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/), there are 2 common ways for installing the CNI: using the **Cilium CLI** or **Helm**, for that lab I will use the CLI tool.

#### Install the Cilium CLI

The Cilium CLI can be used to install Cilium, inspect the state of a Cilium installation, and enable/disable various features (e.g. `clustermesh`, `Hubble`). Install it on your controller where `kubectl` is installed:
```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}
```

#### Install Cilium

Install Cilium into the Kubernetes cluster pointed to by your current `kubectl` context:
```bash
cilium install
```
```plaintext
__   Using Cilium version 1.17.5
__ Auto-detected cluster name: kubernetes
__ Auto-detected kube-proxy has been installed
```
#### Validate the Installation

To validate that Cilium has been properly installed:
```bash
cilium status --wait
```
```plaintext
    /__\
 /__\__/__\    Cilium:             OK
 \__/__\__/    Operator:           OK
 /__\__/__\    Envoy DaemonSet:    OK
 \__/__\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium-envoy             Desired: 1, Ready: 1/1, Available: 1/1
Deployment             cilium-operator          Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 1
                       cilium-envoy             Running: 1
                       cilium-operator          Running: 1
                       clustermesh-apiserver    
                       hubble-relay             
Cluster Pods:          0/2 managed by Cilium
Helm chart version:    1.17.5
Image versions         cilium             quay.io/cilium/cilium:v1.17.5@sha256:baf8541723ee0b72d6c489c741c81a6fdc5228940d66cb76ef5ea2ce3c639ea6: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.32.6-1749271279-0864395884b263913eac200ee2048fd985f8e626@sha256:9f69e290a7ea3d4edf9192acd81694089af048ae0d8a67fb63bd62dc1d72203e: 1
                       cilium-operator    quay.io/cilium/operator-generic:v1.17.5@sha256:f954c97eeb1b47ed67d08cc8fb4108fb829f869373cbb3e698a7f8ef1085b09e: 1
```

Once installed, the master node should transition to `Ready` status:
```plaintext
NAME          STATUS   ROLES           AGE   VERSION
apex-master   Ready    control-plane   99m   v1.32.7
```

---
## Join Additional Nodes

After initializing the first control plane node, you can now join the remaining nodes to the cluster.

There are two types of join commands:
- One for joining **control-plane (master) nodes**
- One for joining **worker nodes**

These commands were displayed at the end of the `kubeadm init` output. If you didn’t copy them, you can regenerate them. 

⚠️ The certificates and the decryption key expire after two hours.

### Additional Masters

You can now join any number of control-plane node by running the command  given by the `kubeadm init` command:
```bash
sudo kubeadm join <control-plane-endpoint> --token <token> --discovery-token-ca-cert-hash <discovery-token-ca-cert-hash> --control-plane --certificate-key <certificate-key>
```
```plaintext
[preflight] Running pre-flight checks
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[preflight] Use 'kubeadm init phase upload-config --config your-config.yaml' to re-upload it.
[preflight] Running pre-flight checks before initializing the new control plane instance
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
W0718 09:27:32.248290   12043 checks.go:846] detected that the sandbox image "registry.k8s.io/pause:3.8" of the container runtime is inconsistent with that used by kubeadm.It is recommended to use "registry.k8s.io/pause:3.10" as the CRI sandbox image.
[download-certs] Downloading the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[download-certs] Saving the certificates to the folder: "/etc/kubernetes/pki"
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [localhost vertex-master] and IPs [192.168.66.169 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [localhost vertex-master] and IPs [192.168.66.169 127.0.0.1 ::1]
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [k8s-lab.lab.vezpi.me kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local vertex-master] and IPs [10.96.0.1 192.168.66.169]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Valid certificates and keys now exist in "/etc/kubernetes/pki"
[certs] Using the existing "sa" key
[kubeconfig] Generating kubeconfig files
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[check-etcd] Checking that the etcd cluster is healthy
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 501.761616ms
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap
[etcd] Announced new etcd member joining to the existing etcd cluster
[etcd] Creating static Pod manifest for "etcd"
{"level":"warn","ts":"2025-07-18T09:27:36.040077Z","logger":"etcd-client","caller":"v3@v3.5.16/retry_interceptor.go:63","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc00037ab40/192.168.66.167:2379","attempt":0,"error":"rpc error: code = FailedPrecondition desc = etcdserver: can only promote a learner member which is in sync with leader"}
[...]
{"level":"warn","ts":"2025-07-18T09:27:44.976805Z","logger":"etcd-client","caller":"v3@v3.5.16/retry_interceptor.go:63","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc00037ab40/192.168.66.167:2379","attempt":0,"error":"rpc error: code = FailedPrecondition desc = etcdserver: can only promote a learner member which is in sync with leader"}
[etcd] Waiting for the new etcd member to join the cluster. This can take up to 40s
[mark-control-plane] Marking the node vertex-master as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node vertex-master as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]

This node has joined the cluster and a new control plane instance was created:

* Certificate signing request was sent to apiserver and approval was received.
* The Kubelet was informed of the new secure connection details.
* Control plane label and taint were applied to the new node.
* The Kubernetes control plane instances scaled up.
* A new etcd member was added to the local/stacked etcd cluster.

To start administering your cluster from this node, you need to run the following as a regular user:

        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config

Run 'kubectl get nodes' to see this node join the cluster.
```

#### Regenerate Certificates

If the certificate is expired, you would see a message like this on the `kubeadm join` command:
```plaintext
[download-certs] Downloading the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
error execution phase control-plane-prepare/download-certs: error downloading certs: error downloading the secret: Secret "kubeadm-certs" was not found in the "kube-system" Namespace. This Secret might have expired. Please, run `kubeadm init phase upload-certs --upload-certs` on a control plane to generate a new one
```

If so, re-upload the certificates and generate a new decryption key, use the following command on a control plane node that is already joined to the cluster:
```bash
sudo kubeadm init phase upload-certs --upload-certs
```
```plaintext
I0718 09:26:12.448472   18624 version.go:261] remote version is much newer: v1.33.3; falling back to: stable-1.32
[upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[upload-certs] Using certificate key:
7531149107ebc3caf4990f94d19824aecf39d93b84ee1b9c86aee84c04e76656
```
#### Generate Token

Paired with the certificate, you'll need a new token, this will print the whole join command as control plane: 
```bash
sudo kubeadm token create --print-join-command --certificate-key <certificate-key>
```

Use the command given to join the Kubernetes cluster on the desired node as master.

### Join Workers

You can join any number of worker nodes by running the following
```bash
sudo kubeadm join k8s-lab.lab.vezpi.me:6443 --token 8etamd.g8whseg60kg09nu1 \
        --discovery-token-ca-cert-hash sha256:65c4da3121f57d2e67ea6c1c1349544c9e295d78790b199b5c3be908ffe5ed6c
```
```plaintext
[preflight] Running pre-flight checks
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[preflight] Use 'kubeadm init phase upload-config --config your-config.yaml' to re-upload it.
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 506.731798ms
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

Again here if you missed the output of the `kubeadm init`, you can generate a new token and the full `join` command:
```bash
sudo kubeadm token create --print-join-command
```

Use the command given to join the Kubernetes cluster on the desired node as worker.

### Verify Cluster

From your controller, you can verify if all the nodes joined the cluster and are in the `Ready` status:
```bash
kubectl get node
```
```plaintext
NAME            STATUS   ROLES           AGE     VERSION
apex-master     Ready    control-plane   154m    v1.32.7
apex-worker     Ready    <none>          5m14s   v1.32.7
vertex-master   Ready    control-plane   26m     v1.32.7
vertex-worker   Ready    <none>          3m39s   v1.32.7
zenith-master   Ready    control-plane   23m     v1.32.7
zenith-worker   Ready    <none>          3m26s   v1.32.7
```

To validate that your cluster has proper network connectivity:
```bash
cilium connectivity test
```
```plaintext
__   Monitor aggregation detected, will skip some flow validation steps
   [kubernetes] Creating namespace cilium-test-1 for connectivity check...
__ [kubernetes] Deploying echo-same-node service...
__ [kubernetes] Deploying DNS test server configmap...
__ [kubernetes] Deploying same-node deployment...
__ [kubernetes] Deploying client deployment...
__ [kubernetes] Deploying client2 deployment...
__ [kubernetes] Deploying client3 deployment...
__ [kubernetes] Deploying echo-other-node service...
__ [kubernetes] Deploying other-node deployment...
__ [host-netns] Deploying kubernetes daemonset...
__ [host-netns-non-cilium] Deploying kubernetes daemonset...
__   Skipping tests that require a node Without Cilium
   [kubernetes] Waiting for deployment cilium-test-1/client to become ready...
__ [kubernetes] Waiting for deployment cilium-test-1/client2 to become ready...
__ [kubernetes] Waiting for deployment cilium-test-1/echo-same-node to become ready...
__ [kubernetes] Waiting for deployment cilium-test-1/client3 to become ready...
__ [kubernetes] Waiting for deployment cilium-test-1/echo-other-node to become ready...
__ [kubernetes] Waiting for pod cilium-test-1/client2-66475877c6-gpdkz to reach DNS server on cilium-test-1/echo-same-node-6c98489c8d-547mc pod...
__ [kubernetes] Waiting for pod cilium-test-1/client3-795488bf5-xrlbp to reach DNS server on cilium-test-1/echo-same-node-6c98489c8d-547mc pod...
__ [kubernetes] Waiting for pod cilium-test-1/client-645b68dcf7-ps276 to reach DNS server on cilium-test-1/echo-same-node-6c98489c8d-547mc pod...
__ [kubernetes] Waiting for pod cilium-test-1/client2-66475877c6-gpdkz to reach DNS server on cilium-test-1/echo-other-node-6d774d44c4-gzkmd pod...
__ [kubernetes] Waiting for pod cilium-test-1/client3-795488bf5-xrlbp to reach DNS server on cilium-test-1/echo-other-node-6d774d44c4-gzkmd pod...
__ [kubernetes] Waiting for pod cilium-test-1/client-645b68dcf7-ps276 to reach DNS server on cilium-test-1/echo-other-node-6d774d44c4-gzkmd pod...
__ [kubernetes] Waiting for pod cilium-test-1/client2-66475877c6-gpdkz to reach default/kubernetes service...
__ [kubernetes] Waiting for pod cilium-test-1/client3-795488bf5-xrlbp to reach default/kubernetes service...
__ [kubernetes] Waiting for pod cilium-test-1/client-645b68dcf7-ps276 to reach default/kubernetes service...
__ [kubernetes] Waiting for Service cilium-test-1/echo-other-node to become ready...
__ [kubernetes] Waiting for Service cilium-test-1/echo-other-node to be synchronized by Cilium pod kube-system/cilium-6824w
__ [kubernetes] Waiting for Service cilium-test-1/echo-other-node to be synchronized by Cilium pod kube-system/cilium-jc4fx
__ [kubernetes] Waiting for Service cilium-test-1/echo-same-node to become ready...
__ [kubernetes] Waiting for Service cilium-test-1/echo-same-node to be synchronized by Cilium pod kube-system/cilium-6824w
__ [kubernetes] Waiting for Service cilium-test-1/echo-same-node to be synchronized by Cilium pod kube-system/cilium-jc4fx
__ [kubernetes] Waiting for NodePort 192.168.66.166:32391 (cilium-test-1/echo-other-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.166:32055 (cilium-test-1/echo-same-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.172:32391 (cilium-test-1/echo-other-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.172:32055 (cilium-test-1/echo-same-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.167:32391 (cilium-test-1/echo-other-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.167:32055 (cilium-test-1/echo-same-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.168:32391 (cilium-test-1/echo-other-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.168:32055 (cilium-test-1/echo-same-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.169:32391 (cilium-test-1/echo-other-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.169:32055 (cilium-test-1/echo-same-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.170:32391 (cilium-test-1/echo-other-node) to become ready...
__ [kubernetes] Waiting for NodePort 192.168.66.170:32055 (cilium-test-1/echo-same-node) to become ready...
__ [kubernetes] Waiting for DaemonSet cilium-test-1/host-netns-non-cilium to become ready...
__ [kubernetes] Waiting for DaemonSet cilium-test-1/host-netns to become ready...
__   Skipping IPCache check
   Enabling Hubble telescope...
__   Unable to contact Hubble Relay, disabling Hubble telescope and flow validation: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp [::1]:4245: connect: connection refused"
     Expose Relay locally with:
   cilium hubble enable
   cilium hubble port-forward&
__   Cilium version: 1.17.5
  [cilium-test-1] Running 123 tests ...
[=] [cilium-test-1] Test [no-policies] [1/123]
[...]
[=] [cilium-test-1] Test [check-log-errors] [123/123]
.................................................
__ [cilium-test-1] All 73 tests (739 actions) successful, 50 tests skipped, 1 scenarios skipped.
```

⌛This connectivity test could take up to 30 minutes.

---
## Conclusion

🚀 Our highly available Kubernetes cluster is ready!

In this post, we walked through the **manual creation of a Kubernetes cluster** using `kubeadm`, on top of 6 Ubuntu VMs (3 masters and 3 workers) previously provisioned with Terraform on Proxmox.

We went step by step:
- Preparing the nodes with the required tools, kernel modules, and container runtime
- Installing the Kubernetes packages
- Bootstrapping the cluster from the first master node
- Joining additional control-plane and worker nodes
- Verifying that the cluster is healthy and ready

This manual approach helps to demystify how Kubernetes clusters are built behind the scenes. It’s a solid foundation before automating the process in future posts using tools like Ansible.

Stay tuned, next time we’ll look into automating all of this!


