---
slug: 
title: Template
description: 
date: 
draft: true
tags: 
categories:
---

## Intro

After building my own Kubernetes cluster in my homelab using `kubeadm` in [that post]({{< ref "post/8-create-manual-kubernetes-cluster-kubeadm" >}}), my next challenge is to expose a simple pod externally, reachable with an URL and secured with a TLS certificate verified by Let's Encrypt.

To achieve this, I needed to configure several components:
- **Service**: Expose the pod inside the cluster and provide an access point.
- **Ingress**: Define routing rules to expose HTTP(S) services externally.
- **Ingress Controller**: Listen to Ingress resources and handles actual traffic routing.
- **TLS Certificates**: Secure traffic with HTTPS using certificates from Let’s Encrypt.

This post will guide you through each step, to understand how external access works in Kubernetes, in a homelab environment.

Let’s dive in.

---
## Helm

To install the external components needed in this setup (like the Ingress controller or cert-manager), I’ll use **Helm**, the de facto package manager for Kubernetes.
### Why Helm

Helm simplifies the deployment and management of Kubernetes applications. Instead of writing and maintaining large YAML manifests, Helm lets you install applications with a single command, using versioned and configurable charts.
### Install Helm

I installed Helm on my LXC bastion host, which already has access to the Kubernetes cluster:
```bash
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install helm
```

---
## Kubernetes Services

Before we can expose a pod externally, we need a way to make it reachable inside the cluster. That’s where Kubernetes Services come in.

A Service provides a stable, abstracted network endpoint for a set of pods. This abstraction ensures that even if the pod’s IP changes (for example, when it gets restarted), the Service IP remains constant.

There are several types of Kubernetes Services, each serving a different purpose:

#### ClusterIP

This is the default type. It exposes the Service on a cluster-internal IP. It is only accessible from within the cluster. Use this when your application does not need to be accessed externally.

#### NodePort

This type exposes the Service on a static port on each node’s IP. You can access the service from outside the cluster using `http://<NodeIP>:<NodePort>`. It’s simple to set up, great for testing.

#### LoadBalancer

This type provisions an external IP to access the Service. It usually relies on cloud provider integration, but in a homelab (or bare-metal setup), we can achieve the same effect using BGP.

---
## Expose a `LoadBalancer` Service with BGP

Initially, I considered using **MetalLB** to expose service IPs to my home network. That’s what I used in the past when relying on my ISP box as the main router. But after reading this post, [Use Cilium BGP integration with OPNsense](https://devopstales.github.io/kubernetes/cilium-opnsense-bgp/), I realized I could achieve the same (or even better) using BGP with my **OPNsense** router and **Cilium**, my CNI.
### What Is BGP?

BGP (Border Gateway Protocol) is a routing protocol used to exchange network routes between systems. In the Kubernetes homelab context, BGP allows your Kubernetes nodes to advertise IPs directly to your network router or firewall. Your router then knows how to reach the IPs managed by your cluster.

So instead of MetalLB managing IP allocation and ARP replies, your nodes directly tell your router: “Hey, I own 192.168.1.240”.
### Legacy MetalLB Approach

Without BGP, MetalLB in Layer 2 mode works like this:
- Assigns a LoadBalancer IP (e.g., `192.168.1.240`) from a pool.
- One node responds to ARP for that IP on your LAN.

Yes, MetalLB can also work with BGP, but what if my CNI (Cilium) can handle it out of the box?
### BGP with Cilium

With Cilium + BGP, you get:
- Cilium’s agent on the node advertises LoadBalancer IPs over BGP.
- Your router learns that IP and routes to the correct node.
- No need for MetalLB.

### BGP Setup

BGP is 

#### On OPNsense

Following the [OPNsense BGP documentation](https://docs.opnsense.org/manual/dynamic_routing.html#bgp-section), to enable BGP, I need to install a plugin. Go to `System` > `Firmware` > `Plugins` and install the `os-frr` plugin:
![opnsense-add-os-frr-plugin.png](img/opnsense-add-os-frr-plugin.png)

First, enable the plugin in the `Routing` > `General`:
![opnsense-enable-routing-frr-plugin.png](img/opnsense-enable-routing-frr-plugin.png)

Then, go to the `BGP` section, enable it in the `General` tab by ticking the box. Set the BGP AS Number, I set `64512` as it is the first in the AS (autonomous System) private range, you can find the ranges [here](https://en.wikipedia.org/wiki/Autonomous_system_(Internet)#ASN_Table):
![opnsense-enable-bgp.png](img/opnsense-enable-bgp.png)

Now create the neighbors, I will add the 3 workers, I don't add the masters as they won't run any workload. I set the node IP in the `Peer-IP` field. For the `Remote AS`, I use the same number for all the node: `64513`, I set the Interface name in `Update-Source Interface`, which is `Lab`. Finally I tick the box for `Next-Hop-Self`:
![opnsense-bgp-create-neighbor.png](img/opnsense-bgp-create-neighbor.png)

Finally, my neighbor list look like this:
![opnsense-bgp-nieghbor-list.png](img/opnsense-bgp-nieghbor-list.png)


#### In Cilium

### Deploying a LoadBalancer with BGP
#### Using an IP Address
#### Using a URL

---
## Kubernetes Ingress

TODO add why we need service  
### What is a Kubernetes Ingress

explain what is an Ingress and its purpose

### How Ingress Work


---
## Ingress Controller

### What is an Ingress Controller

explain what is an Ingress Controller and its purpose

### Which Ingress Controller to Use

comparison between ingress controller
which one I picked and why
### Install NGINX Ingress Controller

detail installation of NGINX Ingress Controller
verify ingress controller service
### Associate a Service to an Ingress


oneline to explain how to use https

---
## Secure Connection with TLS

to use https

### Cert-Manager

#### Install Cert-Manager

install with helm
#### Setup Cert-Manager

verify clusterissuer

### Add TLS in an Ingress

ingress tls code

verify 

---
## Conclusion


