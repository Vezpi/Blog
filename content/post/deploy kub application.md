---
slug: 
title: Template
description: 
date: 
draft: true
tags:
  - kubernetes
  - helm
  - bgp
  - opnsense
  - cilium
  - nginx-ingress-controller
  - cert-manager
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

By default, BGP is disabled by default, both on my OPNsense router and in Cilium. Let’s enable it on both ends.

#### On OPNsense

According to the [official OPNsense documentation](https://docs.opnsense.org/manual/dynamic_routing.html#bgp-section), enabling BGP requires installing a plugin.

Head to `System` > `Firmware` > `Plugins` and install the `os-frr` plugin:  
![  ](img/opnsense-add-os-frr-plugin.png)
Install `os-frr` plugin in OPNsense

Once installed, enable the plugin under `Routing` > `General`:  
![  ](img/opnsense-enable-routing-frr-plugin.png)
Enable routing in OPNsense

Then navigate to the `BGP` section. In the **General** tab:
- Tick the box to enable BGP.
- Set your **BGP ASN**. I used `64512`, the first private ASN from the reserved range (see [ASN table](https://en.wikipedia.org/wiki/Autonomous_system_\(Internet\)#ASN_Table)):
![  ](img/opnsense-enable-bgp.png)
General BGP configuration in OPNsense

Now create your BGP neighbors. I’m only peering with my **worker nodes** (since only they run workloads). For each neighbor:
- Set the node’s IP in `Peer-IP`
- Use `64513` as the **Remote AS** (Cilium’s ASN)
- Set `Update-Source Interface` to `Lab`
- Tick `Next-Hop-Self`:  
![  ](img/opnsense-bgp-create-neighbor.png)
BGP neighbor configuration in OPNsense

Here’s how my neighbor list looks once complete:  
![  ](img/opnsense-bgp-nieghbor-list.png)
BGP neighbor list

Don’t forget to create a firewall rule allowing BGP (port `179/TCP`) from the **Lab** VLAN to the firewall:  
![  ](img/opnsense-create-firewall-rule-bgp-peering.png)
Allow TCP/179 from Lab to OPNsense

#### In Cilium

I already had Cilium installed and couldn’t find a way to enable BGP with the CLI, so I simply reinstalled it with the BGP option:

```bash
cilium uninstall
cilium install --set bgpControlPlane.enabled=true
```

Next, I want only **worker nodes** to establish BGP peering. I add a label to each one for the future `nodeSelector`:
```bash
kubectl label node apex-worker node-role.kubernetes.io/worker=""
kubectl label node vertex-worker node-role.kubernetes.io/worker=""
kubectl label node zenith-worker node-role.kubernetes.io/worker=""
```
```plaintext
NAME            STATUS   ROLES           AGE    VERSION
apex-master     Ready    control-plane   5d4h   v1.32.7
apex-worker     Ready    worker          5d1h   v1.32.7
vertex-master   Ready    control-plane   5d1h   v1.32.7
vertex-worker   Ready    worker          5d1h   v1.32.7
zenith-master   Ready    control-plane   5d1h   v1.32.7
zenith-worker   Ready    worker          5d1h   v1.32.7
```

For the entire BGP configuration, I need:
- **CiliumBGPClusterConfig**: BGP settings for the Cilium cluster, including its local ASN and its peer
- **CiliumBGPPeerConfig**: Sets BGP timers, graceful restart, and route advertisement settings.
- **CiliumBGPAdvertisement**: Defines which Kubernetes services should be advertised via BGP.
- **CiliumLoadBalancerIPPool**: Configures the range of IPs assigned to Kubernetes LoadBalancer services.

```yaml
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-cluster
spec:
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker: "" # Only for worker nodes
  bgpInstances:
  - name: "cilium-bgp-cluster"
    localASN: 64513 # Cilium ASN
    peers:
    - name: "pfSense-peer"
      peerASN: 64512 # OPNsense ASN
      peerAddress: 192.168.66.1  # OPNsense IP
      peerConfigRef:
        name: "bgp-peer"
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: bgp-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisement
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: "Service"
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - { key: somekey, operator: NotIn, values: [ never-used-value ] }
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "dmz"
spec:
  blocks:
  - start: "192.168.55.20" # LB Range Start IP
    stop: "192.168.55.250" # LB Range End IP
```

Apply it:
```bash
kubectl apply -f bgp.yaml 

ciliumbgpclusterconfig.cilium.io/bgp-cluster created
ciliumbgppeerconfig.cilium.io/bgp-peer created
ciliumbgpadvertisement.cilium.io/bgp-advertisement created
ciliumloadbalancerippool.cilium.io/dmz created
```

If everything works, you should see the BGP sessions **established** with your workers:
```bash
cilium bgp peers

Node            Local AS   Peer AS   Peer Address   Session State   Uptime   Family         Received   Advertised
apex-worker     64513      64512     192.168.66.1   established     6m30s    ipv4/unicast   1          2    
vertex-worker   64513      64512     192.168.66.1   established     7m9s     ipv4/unicast   1          2    
zenith-worker   64513      64512     192.168.66.1   established     6m13s    ipv4/unicast   1          2
```

### Deploying a `LoadBalancer` Service with BGP

Let’s quickly validate that the setup works by deploying a test `Deployment` and `LoadBalancer` `Service`:
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: test-lb
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    svc: test-lb
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      svc: test-lb
  template:
    metadata:
      labels:
        svc: test-lb
    spec:
      containers:
      - name: web
        image: nginx
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
```

Check if it gets an external IP:
```bash
kubectl get services test-lb

NAME         TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)        AGE
test-lb      LoadBalancer   10.100.167.198   192.168.55.20   80:31350/TCP   169m
```

The service got the first IP from our defined pool: `192.168.55.20`.

Now from any device on the LAN, try to reach that IP on port 80:
![Test LoadBalancer service with BGP](img/k8s-test-loadbalancer-service-with-bgp.png)

✅ Our pod is reachable through BGP-routed `LoadBalancer` IP, first step successful!

---
## Kubernetes Ingress

We managed to expose a pod externally using a `LoadBalancer` service and a BGP-assigned IP address. This approach works great for testing, but it doesn't scale well.

Imagine having 10, 20, or 50 different services, would I really want to allocate 50 IP addresses, and clutter my firewall and routing tables with 50 BGP entries? Definitely not.

That’s where **Ingress** kicks in.

### What Is a Kubernetes Ingress?

A **Kubernetes Ingress** is an API object that manages **external access to services** in a cluster, typically HTTP and HTTPS, all through a single entry point.

Instead of assigning one IP per service, you define routing rules based on:
- **Hostnames** (`app1.vezpi.me`, `blog.vezpi.me`, etc.)
- **Paths** (`/grafana`, `/metrics`, etc.)

With Ingress, I can expose multiple services over the same IP and port (usually 443 for HTTPS), and Kubernetes will know how to route the request to the right backend service.

Here is an example of a simple `Ingress`, routing traffic of `test.vezpi.me` to the `test-lb` service on port 80:
```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
spec:
  rules:
    - host: test.vezpi.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: test-lb
                port:
                  number: 80
```

### Ingress Controller

On its own, an Ingress is just a set of routing rules. It doesn’t actually handle traffic. To bring it to life, I need an **Ingress Controller** which will:
- Watches the Kubernetes API for `Ingress` resources.
- Opens HTTP(S) ports on a `LoadBalancer` or `NodePort` service.
- Routes traffic to the correct `Service` based on the `Ingress` rules.

Think of it as a reverse proxy (like NGINX or Traefik), but integrated with Kubernetes.

Since I’m looking for something simple, stable, well-maintained, and with a large community, I went with **NGINX Ingress Controller**.
### Install NGINX Ingress Controller

I install it using Helm, I set `controller.ingressClassResource.default=true` to define `nginx` as default for all my future ingresses:
```bash
helm install ingress-nginx \
  --repo=https://kubernetes.github.io/ingress-nginx \
  --namespace=ingress-nginx \
  --create-namespace ingress-nginx \
  --set controller.ingressClassResource.default=true
```
```plaintext
NAME: ingress-nginx
LAST DEPLOYED: Wed Jul 23 15:44:47 2025
NAMESPACE: ingress-nginx
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the load balancer IP to be available.
You can watch the status by running 'kubectl get service --namespace ingress-nginx ingress-nginx-controller --output wide --watch'

An example Ingress that makes use of the controller:
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: example
    namespace: foo
  spec:
    ingressClassName: nginx
    rules:
      - host: www.example.com
        http:
          paths:
            - pathType: Prefix
              backend:
                service:
                  name: exampleService
                  port:
                    number: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
      - hosts:
        - www.example.com
        secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
```

My NGINX Ingress Controller is now installed and its service picked the 2nd IP in the load balancer range, `192.168.55.21`:
```bash
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE   SELECTOR
ingress-nginx-controller   LoadBalancer   10.106.236.13   192.168.55.21   80:31195/TCP,443:30974/TCP   75s   app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress-nginx,app.kubernetes.io/name=ingress-nginx
```

>💡 I want to make sure my controller will always pick the same IP. 

I will create 2 separate pools, one dedicated for the Ingress Controller with only one IP, and another one for anything else.
```yaml
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "ingress-nginx"
spec:
  blocks:
  - cidr: "192.168.55.55/32" # Ingress Controller IP
  serviceSelector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/component: controller
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "default"
spec:
  blocks:
  - start: "192.168.55.100" # LB Start IP
    stop: "192.168.55.250" # LB Stop IP
  serviceSelector:
	matchExpressions:
	- key: app.kubernetes.io/name
	  operator: NotIn
	  values:
		- ingress-nginx
```

After replacing the previous pool by these two, my Ingress Controller got the desired IP `192.168.55.55` and my `test-lb` service picked the first one `192.168.55.100` in the new range as expected.
```bash
NAMESPACE       NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
default         test-lb                              LoadBalancer   10.100.167.198   192.168.55.100   80:31350/TCP                 6h34m
ingress-nginx   ingress-nginx-controller             LoadBalancer   10.106.236.13    192.168.55.55    80:31195/TCP,443:30974/TCP   24m
```

### Associate a Service to an Ingress

Now let’s wire up a service to this controller.

We transform our `LoadBalancer` service to a standard `ClusterIP` and add a minimal Ingress definition to expose my test pod over HTTP:
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: test-lb
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
  selector:
    svc: test-lb
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
spec:
  rules:
    - host: test.vezpi.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: test-lb
                port:
                  number: 80  
```


![Pasted_image_20250803215654.png](img/Pasted_image_20250803215654.png)

---
## Secure Connection with TLS

oneline to explain how to use https

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


