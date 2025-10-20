---
slug:
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - high-availability
  - proxmox
categories:
---

## Intro

In my previous [post]({{< ref "post/12-opnsense-virtualization-highly-available" >}}), I've set up a PoC to validate the possibility to create a cluster of 2 **OPNsense** VMs in **Proxmox VE** and make the firewall highly available.

This time, I will cover the creation of my future OPNsense cluster from scratch, plan the cut over and finally migrate from my current physical box.

---
## Build the Foundation

For the real thing, I'll have to connect the WAN, coming from my ISP box, to my main switch. For that I have to add a VLAN to transport this flow to my Proxmox nodes.

### UniFi

The first thing I do is to configure my layer 2 network which is managed by UniFi. There I need to create two VLANs:
- *WAN* (20): transport the WAN between my ISP box and my Proxmox nodes.
- *pfSync* (44), communication between my OPNsense nodes.

In the UniFi controller, in `Settings` > `Networks`, I add a `New Virtual Network`. I name it `WAN` and give it the VLAN ID 20:
![unifi-add-vlan-for-wan.png](img/unifi-add-vlan-for-wan.png)

I do the same thing again for the `pfSync` VLAN with the VLAN ID 44.

I will plug my ISP box on the port 15 of my switch, which is disabled for now. I set it as active, set the native VLAN on the newly created one `WAN (20)` and disable trunking:
![unifi-enable-port-wan-vlan.png](img/unifi-enable-port-wan-vlan.png)

Once this setting applied, I make sure that only the ports where are connected my Proxmox nodes propagate these VLAN on their trunk. 

We are done with UniFi configuration.

### Proxmox SDN

Now that the VLAN can reach my nodes, I want to handle it in the Proxmox SDN.

In `Datacenter` > `SDN` > `VNets`, I create a new VNet, name it `vlan20` to follow my own naming convention, give it the *WAN* alias and use the tag (ID) 20:
![proxmox-sdn-new-vnet-wan.png](img/proxmox-sdn-new-vnet-wan.png)

I also create the `vlan44` for the *pfSync* VLAN, then I apply this configuration and we are done with the SDN.

---
## Create the VMs

Now that the VLAN configuration is done, I can start buiding the virtual machines on Proxmox.

The first VM is named `cerbere-head1` (I didn't tell you? My current firewall is named `cerbere`, it makes even more sense now!) Here are the settings:
- OS type: Linux
- Machine type: `q35`
- BIOS: `OVMF (UEFI)`
- Disk: 20 GiB on Ceph storage
- CPU/RAM: 2 vCPU, 4 GiB RAM
- NICs:
	1. `vmbr0` (*Mgmt*)
	2. `vlan20` (*WAN*)
	3. `vlan13` *(User)*
	4. `vlan37` *(IoT)*
	5. `vlan44` *(pfSync)*
	6. `vlan55` *(DMZ)*
	7. `vlan66` *(Lab)*
![proxmox-cerbere-vm-settings.png](img/proxmox-cerbere-vm-settings.png)

ℹ️ Now I clone that VM to create `cerbere-head2`, then I proceed with OPNsense installation. I don't want to go into much details about OPNsense installation, I already documented it in the previous [post]({{< ref "post/12-opnsense-virtualization-highly-available" >}}).

After the installation of both OPNsense instances, I give to each of them their IP in the *Mgmt* network:
- `cerbere-head1`: `192.168.88.2/24`
- `cerbere-head2`: `192.168.88.3/24`

While these routers are not managing the networks, I give them my current OPNsense routeur as gateway (`192.168.88.1`) to able to reach them from my PC in another VLAN.

---
## Configure OPNsense

Initially I thought about restoring my current OPNsense config on the VM. But as I didn't document the configuration process the first time, I take the opportunity to start over.

I'll start with the elements that needs to be configured on both firewalls, where each has its own parameters. After I'll create the OPNsense cluster, then configure the master node only as the configuration will be duplicated on the other node.
### System

I start by the basic, in `System` > `Settings` > `General`:
- **Hostname**: `cerbere-head1` (`cerbere-head2` for the second one).
- **Domain**: `mgmt.vezpi.com`.
- **Time zone**: `Europe/Paris`.
- **Language**: `English`.
- **Theme**: `opnsense-dark`.
- **Prefer IPv4 over IPv6**: tick the box to prefer IPv4.

Then, in `System` > `Access` > `Users`, I create a new user, I don't like sticking with the defaults `root`. I add this user in the `admins`  group, while removing `root` from it.

In `System` > `Settings` > `Administration`, I change several things:
- **TCP port**: from `443` to `4443`, to free port 443 for the reverse proxy coming next.
-  **Alternate Hostnames**: `cerbere.vezpi.com` which will be the URL to reach the firewall by the reverse proxy.
- **Access log**: enabled.
- **Secure Shell Server**: enabled.
- **Authentication Method:** permit password login (no `root` login).
- **Sudo**: `No password`.
Once I click `Save`, I follow the link given to reach the WebGUI on port `4443`.

Time for updates, in System > Firmware > Status, I click on `Check for updates`.  An update is available, I close the banner, head to the bottom and click on `Update`. I'm warned that this update requires a reboot.

Once updated and rebooted, I go to `System` > `Firmware` > `Plugins`, I tick the box to show community plugins. For now I only install the QEMU guest agent, `os-qemu-guest-agent`, to allow communication between the VM and the Proxmox host. 

This requires a shutdown. On Proxmox, I enable the `QEMU Guest Agent` in the VM options:
![proxmox-opnsense-enable-qemu-guest-agent.png](img/proxmox-opnsense-enable-qemu-guest-agent.png)

Finally I restart the VM. Once started, from the Proxmox WebGUI, I can see the IPs of the VM which confirms the guest agent is working.
### Interfaces

On both firewalls, I assign the remaining NICs to new interfaces adding a description. The VMs have 7 interfaces, I carefully compare the MAC addresses to not mix them up:
![opnsense-assign-interfaces.png](img/opnsense-assign-interfaces.png)

In the end, the interfaces configuration looks like this:

| Interface | Mode           | `cerbere-head1` | `cerbere-head2` |
| --------- | -------------- | --------------- | --------------- |
| *LAN*     | Static IPv4    | 192.168.88.2/24 | 192.168.88.3/24 |
| *WAN*     | DHCPv4 + SLAAC | Enabled         | Disabled        |
| *User*    | Static IPv4    | 192.168.13.2/24 | 192.168.13.3/24 |
| *IoT*     | Static IPv4    | 192.168.37.2/24 | 192.168.37.3/24 |
| *pfSync*  | Static IPv4    | 192.168.44.1/30 | 192.168.44.2/30 |
| *DMZ*     | Static IPv4    | 192.168.55.2/24 | 192.168.55.3/24 |
| *Lab*     | Static IPv4    | 192.168.66.2/24 | 192.168.66.3/24 |
I don't configure Virtual IP yet, I'll manage that once high availability has been setup.

### High Availability

From here we can associate both instances to create a cluster. The last thing I need to do, is to allow the communication on the *pfSync* interface. By default, no communication is allowed on the new interfaces.

From `Firewall` > `Rules` > `pfSync`, I create a new rule on each firewall:
- **Action**: Pass
- **Quick**: tick the box to apply immediately on match
- **Interface**: *pfSync*
- **Direction**: in
- **TCP/IP Version**: IPv4
- **Protocol**: any
- **Source**: *pfSync* net
- **Destination**: *pfSync* net
- **Log**: tick the box to log packets
- **Category**: OPNsense
- **Description**: pfSync

Next, I head to `System` > `High Availability` > `Settings`:
- **Master** (`cerbere-head1`):
	- **Synchronize all states via**: *pfSync*
	- **Synchronize Peer IP**: `192.168.44.2`
	- **Synchronize Config**: `192.168.44.2`
	- **Remote System Username**: `<username>`
	- **Remote System Password**: `<password>`
	- **Services**: Select All
- **Backup** (`cerbere-head2`):
	- **Synchronize all states via**: *pfSync*
	- **Synchronize Peer IP**: `192.168.44.1`
	- **Synchronize Config**: `192.168.44.1`
⚠️ Do not fill the XMLRPC Sync fields, only to be filled on the master.

In the section `System` > `High Availability` > `Status`, I can verify is the synchronization is working. On this page I can replicate any or all services from my master to my backup node:
![opnsense-high-availability-status.png](img/opnsense-high-availability-status.png)

### Virtual IPs

Now that HA is configured, I can give my networks a VIP shared across my nodes. In `Interfaces` > `Virtual IPs` > `Settings`, I create one VIP for each of my networks using CARP (Common Address Redundancy Protocol). The target is to reuse the IP addresses used by my current OPNsense instance, but as it is still routing my network, I use different IPs for the configuration phase:
![opnsense-interface-virtual-ips.png](img/opnsense-interface-virtual-ips.png)

### Firewall

Let's configure the core feature of OPNsense, the firewall. I don't want to go too crazy with the rules. I only need to configure the master, thanks to the replication.

Basically I have 2 kinds of networks, those which I trust, and those which I don't. From this standpoint, I will create two zones. 

Globally, on my untrusted networks, I will allow access to the DNS and to the internet, not on the other networks. On the other hand, my trusted networks would have the possibility to reach other VLANs.

To begin, in `Firewall` > `Groups`, I create 2 groups to regroup my interfaces:
- **Trusted**: *Mgmt*, *User*
- **Untrusted**: *IoT*, *DMZ*, *Lab*

Next, in `Firewall` > `Aliases`, I create an alias `InternalNetworks` to regroup all my internal networks:
![opnsense-create-alias-internalnetworks.png](img/opnsense-create-alias-internalnetworks.png)

For all my networks, I want to allow DNS querry on the local DNS. In `Firewall` > `Rules` > `Floating`, let's create the first rule:

| Field                      | Value                                 |
| -------------------------- | ------------------------------------- |
| **Action**                 | Pass                                  |
| **Quick**                  | Apply the action immediately on match |
| **Interface**              | Trusted, Untrusted                    |
| **Direction**              | in                                    |
| **TCP/IP Version**         | IPv4                                  |
| **Protocol**               | TCP/UDP                               |
| **Source**                 | InternalNetworks                      |
| **Destination**            | This Firewall                         |
| **Destination port range** | from: DNS - to: DNS                   |
| **Log**                    | Log packets                           |
| **Category**               | DNS                                   |
| **Description**            | DNS query                             |

Next I want to allow connections towards the internet. At the same place I create a second rule:

| Field                      | Value                                 |
| -------------------------- | ------------------------------------- |
| **Action**                 | Pass                                  |
| **Quick**                  | Apply the action immediately on match |
| **Interface**              | Trusted, Untrusted                    |
| **Direction**              | in                                    |
| **TCP/IP Version**         | IPv4+IPv6                             |
| **Protocol**               | any                                   |
| **Source**                 | InternalNetworks                      |
| **Destination / Invert**   | Invert the sense of the match         |
| **Destination**            | InternalNetworks                      |
| **Destination port range** | from: any - to: any                   |
| **Log**                    | Log packets                           |
| **Category**               | Internet                              |
| **Description**            | Internet                              |

Finally, I want to allow anything from my trusted networks. In `Firewall` > `Rules` > `Trusted`, I create the rule:

| Field                      | Value                                 |
| -------------------------- | ------------------------------------- |
| **Action**                 | Pass                                  |
| **Quick**                  | Apply the action immediately on match |
| **Interface**              | Trusted                               |
| **Direction**              | in                                    |
| **TCP/IP Version**         | IPv4+IPv6                             |
| **Protocol**               | any                                   |
| **Source**                 | Trusted net                           |
| **Destination**            | any                                   |
| **Destination port range** | from: any - to: any                   |
| **Log**                    | Log packets                           |
| **Category**               | Trusted                               |
| **Description**            | Trusted                               |

Great, with these 3 rules, I cover the basics. The remaining rules would be to allow specific equipment to reach out to something else. For example my home assistant instance want to connect to my TV, both are on different VLAN, hence I need a rule to allow it. I won't cover that in this post.

### DHCP

For the DHCP, I choose Dnsmasq. In my current installation I use ISC DHCPv4, but as it is now deprecated, I prefer to replace it. Dnsmasq will also act as DNS, but only for my local zones. 

Beware because it is not synchronizing leases in HA. To workaround this, both firewalls will serve DHCP at the same time, with slight different configuration to not overlap. 

In `Services` > `Dnsmasq DNS & DHCP` > `General`, I configure the master firewall as follow:
- **Default**
	- **Enable**: Yes
	- **Interface**: *Mgmt*, *User*, *IoT*, *DMZ* and *Lab*
- **DNS**
	- **Listen por**t: 53053
- **DNS Query Forwarding** 
	- **Do not forward to system defined DNS servers**: Enabled
- **DHCP**
	- **DHCP FQDN**: Enabled
	- **DHCP local domain**: Enabled
	- **DHCP authoritative**: Enabled
	- **DHCP reply delay**: 0
	- **DHCP register firewall rules**: Enabled
	- **Disable HA sync**: Enabled

On the backup node, I configure it the same, the only difference will be the **DHCP reply delay** which I set to **10**. This will let the time to my master node to fulfill requests if it is alive.

Next I configure the DHCP ranges. Both firewalls will have different ranges, the backup node will have smaller ones. On the master, they are configured as follow:
![opnsense-dnsmasq-dhcp-ranges.png](img/opnsense-dnsmasq-dhcp-ranges.png)

Then I set some DHCP options for each domain: the `router`, the `dns-server` and the `domain-name`:
![opnsense-dnsmasq-dhcp-options.png](img/opnsense-dnsmasq-dhcp-options.png)

Finally in in the `Hosts` tab, I define static DHCP mappings but also static IP not managed by the DHCP, to have them registered in the DNS:
![opnsense-dnsmasq-dhcp-hosts.png](img/opnsense-dnsmasq-dhcp-hosts.png)

### DNS

For the DNS, I will use Unbound. It is a validating, recursive, caching DNS resolver built into OPNsense, which can:
- Resolve queries from the root servers.
- Cache results for faster responses.
- Check domain authenticity with DNSSEC.
- Block domains based of blacklist.
- Add custom records.

For the local zones, I will use forward the requests to Dnsmasq, hence I will not registering DHCP leases in Unbound.

Let's configure it, in `Services` > `Unbound DNS` > `General`:
![opnsense-unbound-general-settings.png](img/opnsense-unbound-general-settings.png)

 Then I configure the blocklist in `Services` > `Unbound DNS` > `Blocklist`. I enable it and select the `[hagezi] Multi PRO mini` list. Initially I was using AdGuard Home, but I want to give this blocklist feature a chance.

To maintain the service of to date, in `System` > `Settings` > `Cron`, I add my first job that runs every night at 2AM to `Update Unbound DNSBLs`.

Finally I configure query forwarding for my local domains. In `Services` > `Unbound DNS` > `Query Forwarding`, I add each of my local domains with their reverse lookup (PTR record). The forwarded server is Dnsmasq which I'll configure next:
![opnsense-unbound-dns-query-forwarding.png](img/opnsense-unbound-dns-query-forwarding.png)

### VPN

When I'm not home, I still want to be able to reach my services and enjoy my DNS ad blocker. For that I'm setting up a VPN, with **WireGuard**. It's fast, secure and easy to set up.

In `VPN` > `WireGuard` > `Instances`, I create a new one:
- **Enabled**: Yes
- **Name**: *Homelan*
- **Public/Private keys**: Key-pair generated
- **Listen port**: `61337`
- **Tunnel address**: `10.13.37.1/24`
- **Depend on (CARP)**: on *lan* (vhid 1)

Once configured, I enable WireGuard and apply the configuration.

Next in the `Peer generator` tab, I fulfill the empty fields for my first device:
- **Endpoint**: `vezpi.com`
- **Name**: *S25Ultra*
- **DNS Servers**: `10.13.37.1`

Before clicking `Store and generate next`, from my device, I configure the peer by capturing the QR code. Finally I can save that peer and start over for new ones.

To allow connections from outside, I need to create a firewall rule on the WAN interface:

| Field                      | Value                                 |
| -------------------------- | ------------------------------------- |
| **Action**                 | Pass                                  |
| **Quick**                  | Apply the action immediately on match |
| **Interface**              | WAN                                   |
| **Direction**              | in                                    |
| **TCP/IP Version**         | IPv4                                  |
| **Protocol**               | UDP                                   |
| **Source**                 | any                                   |
| **Destination**            | WAN address                           |
| **Destination port range** | from: 61337 - to: 61337               |
| **Log**                    | Log packets                           |
| **Category**               | VPN                                   |
| **Description**            | WireGuard                             |

### Reverse Proxy

The next feature I need is a reverse proxy, to redirect incoming HTTPS requests, to reach my services, such as this blog. For that I use **Caddy**. This service is not installed by default, I need to add a plugin.

On both firewalls, In `System` > `Firmware` > `Plugins`, I tick the box to show community plugins and install `os-caddy`.

I refresh the page and, on the master, in `Services` > `Caddy` > `General Settings`:
- **Enable Caddy**: Yes
- **Enable Layer4 Proxy**: Yes
- **ACME**: `<email address>`
- **Auto HTTPS**: On (default)

There are two types of redirections, the `Reverse Proxy` and the `Layer4 Proxy`. The first one is for HTTPS only, where Caddy will manage the SSL.

#### HTTPS Proxy

In `Services` > `Caddy` > `Reverse Proxy`, I define the services directly managed by Caddy.

These services should not be exposed to everyone. In the `Access` tab, I create a list, called `Internal`, of allowed networks, including my LAN and VPN networks.

Then in the `Domains` tab, I add my domains. For example, this is here I define `cerbere.vezpi.com`, my URL to reach my OPNsense WebGUI:
- **Enable**: Yes
- **Frontend**
	- **Protocol**: `https://`
	- **Domain**: `cerbere.vezpi.com`
	- **Port**: leave empty
	- **Certificate**: Auto HTTPS
	- **Description**: OPNsense
- **Access**
	- **Access List**: `Internal`
	- **HTTP Access Log**: Enabled

Finally in the `Handlers` tab, I define to which upstream these domains are forwarded to. For `cerbere.vezpi.com` I define this:
- **Enabled**: Yes
- **Frontend**
	- **Domain**: `https://cerbere.vezpi.com`
	- **Subdomain**: None
- **Handler**
	- **Path**: any
- **Access**
	- **Access List**: None
- **Directive**
	- **Directive**: `reverse_proxy`
- **Upstream**
	- **Protocol**: `https://`
	- **Upstream Domain**: `127.0.0.1`
	- **Upstream Port**: `4443`
	- **TLS Insecure Skip Verify**: Enabled
	- **Description**: OPNSense

#### Layer4 Proxy

Most of my services are behind another reverse proxy on my network, Traefik. To let it manage normally its domains, I forward them using `Layer4 Routes`. It prevents Caddy to terminate SSL, the HTTPS stream is left intact.

In `Services` > `Caddy` > `Layer4 Proxy`, I create 3 routes.

The first one is for internet exposed services, like this blog or my Gitea instance:
- Enabled: Yes
- Sequence: 1
- Layer 4
	- Routing Type: listener_wrappers
- Layer 7
	- Matchers: TLS (SNI Client Hello)
	- Domain: `blog.vezpi.com` `git.vezpi.com`
	- Terminate SSL: No
- Upstream
	- Upstream Domain: `192.168.66.50`
	- Upstream Port: `443`
	- Proxy Protocol: v2
	- Description: External Traefik HTTPS dockerVM

The second one is for internal only services. It is configured pretty much the same but using  access list:
- Sequence: 2
- Access
	- Remote IP: `192.168.13.0/24` `192.168.88.0/24` `10.13.37.0/24`

The third one is for Traefik HTTP challenges for Let's Encrypt:
- Sequence: 3
- Layer 7
	- Matchers: HTTP (Host Header)
	- Domain: `blog.vezpi.com` `git.vezpi.com` etc.
- Upstream:
	- Upstream Port: 80
	- Proxy Protocol: Off (default)

Finally, I need to allow connection of these ports on the firewall, one rule for HTTPS and another for HTTP:

| Field                      | Value                                 |
| -------------------------- | ------------------------------------- |
| **Action**                 | Pass                                  |
| **Quick**                  | Apply the action immediately on match |
| **Interface**              | WAN                                   |
| **Direction**              | in                                    |
| **TCP/IP Version**         | IPv4                                  |
| **Protocol**               | TCP                                   |
| **Source**                 | any                                   |
| **Destination**            | WAN address                           |
| **Destination port range** | from: HTTPS - to: HTTPS               |
| **Log**                    | Log packets                           |
| **Category**               | Caddy                                 |
| **Description**            | Caddy HTTPS                           |

### mDNS Repeater

The last service I want to setup in OPNsense is a mDNS repeater. This is useful for some devices to announce themselves on the network, when not on the same VLAN, such as my printer or my Chromecast. The mDNS repeater get the message from an interface to send it to another one.

This service is also not installed by default, on both firewalls, In `System` > `Firmware` > `Plugins`, I tick the box to show community plugins and install `os-mdns-repeater`.

Then in `Services` > `mDNS Repeater`, the configuration is pretty straight forward:
- Enable: Yes
- Enable CARP Failover: Yes
- Listen Interfaces: *IoT*, *User*

### Service Synchronization

The final step is to synchronize all the services between the master and the backup node in the cluster. First in `System` > `High Availability` > `Status`, I click the button to `Synchronize and reconfigure all`.

Then I want to make sure that future changes are synchronized if I omit to replicate them myself. In `System` > `Settings` > `Cron`, I add a new job that runs every night to `HA update and reconfigure backup`.



## Switch

Configure DHCP on both instance
Enable DHCP
Change VIP
Replicate configuration
## Verify



Firewall
All sites
mDNS (chromecast)
VPN

DNS blocklist
