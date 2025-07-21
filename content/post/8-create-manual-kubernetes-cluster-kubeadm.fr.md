---
slug: create-manual-kubernetes-cluster-kubeadm
title: Créer un Cluster Kubernetes Hautement Disponible avec kubeadm sur des VMs
description: Guide étape par étape pour créer manuellement un cluster Kubernetes hautement disponible sur des machines virtuelles avec kubeadm.
date: 2025-07-18
draft: false
tags:
  - kubernetes
  - kubeadm
categories:
  - homelab
---

## Intro

Dans cet [article précédent]({{< ref "post/7-terraform-create-proxmox-module" >}}), j'expliquais comment déployer des VMs avec un module **Terraform** sur **Proxmox** et j'avais terminé avec 6 VMs, 3 nœuds masters et 3 nœuds workers, en m'appuyant sur un [template cloud-init]({{< ref "post/1-proxmox-cloud-init-vm-template" >}}).

Maintenant que l'infrastructure est prête, passons à l'étape suivante : **créer manuellement un cluster Kubernetes** avec `kubeadm`, hautement disponible utilisant `etcd` empilé.

Dans cet article, je vais détailler chaque étape de l'installation d’un cluster Kubernetes. Je n'utiliserai pas d'outil d'automatisation pour configurer les nœuds pour le moment, afin de mieux comprendre les étapes impliquées dans le bootstrap d’un cluster Kubernetes. L'automatisation sera couverte dans de futurs articles.

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
### Modules Noyau et Paramètres sysctl

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

### Amorcer le Cluster

Exécutez la commande suivante pour amorcer le cluster:
```bash
sudo kubeadm init \
  --control-plane-endpoint "k8s-lab.lab.vezpi.me:6443" \
  --upload-certs \
  --pod-network-cidr=10.10.0.0/16
```

**Explications** :
- `--control-plane-endpoint` : Nom DNS pour votre plan de contrôle.
- `--upload-certs` : Télécharge les certificats qui doivent être partagés entre toutes les masters du cluster.
- `--pod-network-cidr` : Sous-réseau à utiliser pour le CNI.

Cette étape va :
- Initialiser la base `etcd` et les composants du plan de contrôle.
- Configurer RBAC et les tokens d’amorçage.
- Afficher deux commandes `kubeadm join` importantes : une pour les **workers**, l’autre pour les **masters supplémentaires**.

ℹ️ Le nom DNS `k8s-lab.lab.vezpi.me` est géré dans mon homelab par **Unbound DNS**, cela résout sur mon interface d'**OPNsense** où un service **HAProxy** écoute sur le port 6443 et équilibre la charge entre les 3 nœuds du plan de contrôle.

Vous verrez aussi un message indiquant comment configurer l’accès `kubectl`.

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

### Configurer `kubectl`

Si vous préférez gérer votre cluster depuis le nœud master, vous pouvez simplement copier-coller depuis la sortie de la commande `kubeadm init` :
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Si vous préférez contrôler le cluster depuis autre part, dans mon cas depuis mon bastion LXC :
```bash
mkdir -p $HOME/.kube
rsync --rsync-path="sudo rsync" <master-node>:/etc/kubernetes/admin.conf $HOME/.kube/config
```

Vérifiez l'accès :
```bash
kubectl get nodes
```

ℹ️ You devriez voir seulement le premier master listé (dans l'état `NotReady` jusqu'à ce que le CNI soit déployé).

### Installer le Plugin CNI Cilium

Depuis la [documentation Cilium](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/), Il y a 2 manières principales pour installer le CNI : utiliser la **CLI Cilium** ou **Helm**, pour ce lab je vais utiliser l'outil CLI.

#### Installer la CLI Cilium 

La CLI Cilium peut être utilisée pour installer Cilium, inspecter l'état de l'installation Cilium et activer/désactiver diverses fonctionnalités (ex : `clustermesh`, `Hubble`) :
```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}
```

#### Installer Cilium

Installer Cilium dans le cluster Kubernetes pointé par le contexte `kubectl` :
```bash
cilium install
```
```plaintext
__   Using Cilium version 1.17.5
__ Auto-detected cluster name: kubernetes
__ Auto-detected kube-proxy has been installed
```
#### Valider l'Installation

Pour valider que Cilium a été installé correctement :
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

Une fois installé, le nœud master doit passer au statut `Ready`.
```plaintext
NAME          STATUS   ROLES           AGE   VERSION
apex-master   Ready    control-plane   99m   v1.32.7
```

---

## Ajouter les Nœuds Supplémentaires

Après avoir initialisé le premier nœud du control plane, vous pouvez maintenant **ajouter les autres nœuds** au cluster.

Il existe deux types de commandes `join` :
- Une pour rejoindre les **nœuds du control plane (masters)**
- Une pour rejoindre les **nœuds workers**

Ces commandes sont affichées à la fin de la commande `kubeadm init`. Si vous ne les avez pas copiées, il est possible de les **régénérer**.

⚠️ Les certificats et la clé de déchiffrement **expirent au bout de deux heures**.

### Ajouter des Masters

Vous pouvez maintenant ajouter d'autres nœuds du control plane en exécutant la commande fournie par `kubeadm init` :
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

#### Regénérer les Certificats

Si les certificats ont expiré, vous verrez un message d’erreur lors du `kubeadm join` :
```plaintext
[download-certs] Downloading the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
error execution phase control-plane-prepare/download-certs: error downloading certs: error downloading the secret: Secret "kubeadm-certs" was not found in the "kube-system" Namespace. This Secret might have expired. Please, run `kubeadm init phase upload-certs --upload-certs` on a control plane to generate a new one
```

Dans ce cas, vous pouvez **retélécharger les certificats** et générer une nouvelle clé de chiffrement à partir d’un nœud déjà membre du cluster :
```bash
sudo kubeadm init phase upload-certs --upload-certs
```
```plaintext
I0718 09:26:12.448472   18624 version.go:261] remote version is much newer: v1.33.3; falling back to: stable-1.32
[upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[upload-certs] Using certificate key:
7531149107ebc3caf4990f94d19824aecf39d93b84ee1b9c86aee84c04e76656
```

#### Générer un Token

Associé au certificat, vous aurez besoin d’un **nouveau token**, cette commande affichera directement la commande complète `join` pour un master :
```bash
sudo kubeadm token create --print-join-command --certificate-key <certificate-key>
```

Utilisez cette commande sur les nœuds à ajouter au cluster Kubernetes comme master.

### Ajouter des Workers

Vous pouvez rejoindre n'importe quel nombre de nœuds workers avec la commande suivante :
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

Encore une fois, si vous avez perdu l’output initial de `kubeadm init`, vous pouvez régénérer une nouvelle commande complète :
```bash
sudo kubeadm token create --print-join-command
```

Utilisez cette commande sur les nœuds à ajouter comme workers.

### Vérifier le Cluster

Depuis votre contrôleur, vous pouvez vérifier que tous les nœuds ont bien rejoint le cluster et sont dans l’état `Ready` :
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

Pour valider que le cluster a une bonne connectivité réseau :
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

⌛ Ce test de connectivité peut prendre jusqu’à **30 minutes**.

---
## Conclusion

🚀 Notre cluster Kubernetes hautement disponible est prêt !

Dans cet article, nous avons vu comment **créer manuellement un cluster Kubernetes** à l’aide de `kubeadm`, sur un ensemble de 6 machines Ubuntu (3 masters et 3 workers) préalablement déployées avec Terraform sur Proxmox.

Nous avons suivi les étapes suivantes :
- Préparation des nœuds avec les outils, modules noyau et runtime nécessaires
- Installation des paquets Kubernetes
- Initialisation du cluster depuis le premier nœud master
- Ajout des autres nœuds du plan de contrôle et les workers
- Vérification de l’état et du bon fonctionnement du cluster

Cette approche manuelle permet de mieux comprendre comment un cluster Kubernetes est construit en interne. C’est une excellente base avant de passer à l’automatisation dans les prochains articles, en utilisant des outils comme Ansible.

Restez connectés, la suite sera axée sur l’automatisation de tout ça !
