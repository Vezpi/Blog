---
slug: migration-opnsense-proxmox-highly-available
title: migration-opnsense-proxmox-highly-available
description: migration-opnsense-proxmox-highly-available
date: 2025-11-07
draft: true
tags:
  - opnsense
  - high-availability
  - proxmox
categories:
  - homelab
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
- OS type: Linux (even if OPNsense is  based on FreeBSD)
- Machine type: `q35`
- BIOS: `OVMF (UEFI)`
- Disk: 20 GiB on Ceph distributed storage
- RAM: 4 GiB RAM, ballooning disabled
- CPU: 2 vCPU
- NICs, firewall disabled:
	1. `vmbr0` (*Mgmt*)
	2. `vlan20` (*WAN*)
	3. `vlan13` *(User)*
	4. `vlan37` *(IoT)*
	5. `vlan44` *(pfSync)*
	6. `vlan55` *(DMZ)*
	7. `vlan66` *(Lab)*
![proxmox-cerbere-vm-settings.png](img/proxmox-cerbere-vm-settings.png)

ℹ️ Now I clone that VM to create `cerbere-head2`, then I proceed with OPNsense installation. I don't want to go into much details about OPNsense installation, I already documented it in a previous [post]({{< ref "post/12-opnsense-virtualization-highly-available" >}}).

After the installation of both OPNsense instances, I give to each of them their IP in the *Mgmt* network:
- `cerbere-head1`: `192.168.88.2/24`
- `cerbere-head2`: `192.168.88.3/24`

While these routers are not managing the networks, I give them my current OPNsense routeur as gateway (`192.168.88.1`) to allow me to reach them from my laptop in another VLAN.

---
## Configure OPNsense

Initially, I thought about restoring my current OPNsense configuration and adapt it to the setup.

Then I decided to start over to document and share it. This part was getting so long that I prefered create a dedicated post instead.

📖 You can find the details of the full OPNsense configuration in that [article]({{< ref "post/13-opnsense-full-configuration" >}}), covering HA, DNS, DHCP, VPN and reverse proxy.

---
## Proxmox VM High Availability

Resources (VM or LXC) in Proxmox VE can be tagged as highly available, let see how to set it up.

### Proxmox HA Requirements

First, your Proxmox cluster must allow it. There are some requirements:
- At least 3 nodes to have quorum
- Shared storage for your resources
- Time synchronized
- Reliable network

A fencing mechanism must be enabled. Fencing is the process of isolating a failed cluster node to ensure it no longer accesses shared resources. This prevents split-brain situations and allows Proxmox HA to safely restart affected VMs on healthy nodes. By default, it is using Linux software watchdog, *softdog*, good enough for me.

In Proxmox VE 8, It was possible to create HA groups, depending of their resources, locations, etc. This has been replaced, in Proxmox VE 9, by HA affinity rules. This is actually the main reason behind my Proxmox VE cluster upgrade, which I've detailed in that [post]({{< ref "post/14-proxmox-cluster-upgrade-8-to-9-ceph" >}}).

### Configure VM HA

The Proxmox cluster is able to provide HA for the resources, but you need to define the rules.

In `Datacenter` > `HA`, you can see the status and manage the resources. In the `Resources` panel I click on `Add`. I need to pick the resource to configure as HA in the list, here `cerbere-head1` with ID 122. Then in the tooltip I can define the maximum of restart and relocate, I keep `Failback` enabled and the requested state to `started`:
![proxmox-add-vm-ha.png](img/proxmox-add-vm-ha.png)

The Proxmox cluster will now make sure this VM is started. I do the same for the other OPNsense VM, `cerbere-head2`.  

### HA Affinity Rules

Great, but I don't want them on the same node. This is when the new feature HA affinity rules, of Proxmox VE 9, come in. Proxmox allows to create node affinity and resource affinity rules. I don't mind on which node they run, but I don't want them together. I need a resource affinity rule.

In `Datacenter` > `HA` > `Affinity Rules`, I add a new HA resource affinity rule. I select both VMs and pick the option `Keep Separate`:
![proxmox-ha-resource-affinity-rule.png](img/proxmox-ha-resource-affinity-rule.png)

✅ My OPNsense VMs are now fully ready!

## TODO


Check conso Watt average: moyenne 85W
Check temp average (midnight): ~33°
## Switch



#### Backup OPNsense box

On my physical OPNsense instance, in `System` > `Configuration` > `Backups`

#### Disable DHCP on OPNsene box

In Services > ISC DHCPv4, and for all my interfaces, I disable the DHCP server.



#### Change OPNsense box IPs

In Interfaces, I the IP of each interfaces from .1 to .253
As soon as I click on Apply, I lost the communication, which is expected


#### Change VIP on VM

On my Master VM, In Interfaces > Virtual IPs > Settings, I change the VIP address for all interface
Then I click Apply


#### Remove GW on VM

In - # System: Gateways: Configuration, I disable the LAN_GW which is not needed anymore

#### Configure DHCP on both instance

In both VM, in - # Services: Dnsmasq DNS & DHCP, I enable the service
#### Enable DHCP on VM

Enable mdns repeate
In - # Services: mDNS Repeater, I enable and enable CARP Failover
reboot needed for CARP
#### Replicate configuration on VM

In - # System: High Availability: Status, Synchronize and reconfigure all

In my rack, I
Unplug OPNsense box WAN

Plug WAN on port 15

![Pasted_image_20251107104749.png](img/Pasted_image_20251107104749.png)

 
## Verify

Ping VIP OK
Vérifier interface OK
tests locaux (ssh, ping) OK

Basic (dhcp, dns, internet)
DHCP OK 
DNS NOK -> Restart Unbound service
Internet OK

Firewall -> Need some not critical opening
All sites -> OK
mDNS (chromecast) -> OK
VPN -> OK
TV -> OK
speedtest -> -15% bandwidth  (to confirm another time)
Vérifier tous les devices -> OK

DNS blocklist OK

Check load (ram, cpu) -> OK
#### Failover
In - # System: High Availability: Status, Synchronize and reconfigure all
In 


![Pasted_image_20251107214056.png](img/Pasted_image_20251107214056.png)
#### Test proxmox full shutdown
##  Problems

### Reverse Proxy
Every domains (reverse proxy/layer 4 proxy) give this error:
SSL_ERROR_INTERNAL_ERROR_ALERT
After checking the services synchronized thought XMLRPC Sync, Caddy and mDNS-repeater were not checked. It is because these services were installed after the initial configuration of the HA. 

Solution: Add Caddy to XMLRPC Sync
### DNS
While failover, the internet connection is clunky, really slow
No DNS, it is always DNS

no gateway for backup node -> rework script
Solution: Enable master node as gateway when backup
New script
```php
#!/usr/local/bin/php
<?php
/**
 * OPNsense CARP event script
 * - Enables/disables the WAN interface only when needed
 * - Avoids reapplying config when CARP triggers multiple times
 */

require_once("config.inc");
require_once("interfaces.inc");
require_once("util.inc");
require_once("system.inc");

// Read CARP event arguments
$subsystem = !empty($argv[1]) ? $argv[1] : '';
$type = !empty($argv[2]) ? $argv[2] : '';

// Accept only MASTER/BACKUP events
if (!in_array($type, ['MASTER', 'BACKUP'])) {
    // Ignore CARP INIT, DEMOTED, etc.
    exit(0);
}

// Validate subsystem name format, expected pattern: <ifname>@<vhid>
if (!preg_match('/^[a-z0-9_]+@\S+$/i', $subsystem)) {
    log_error("Malformed subsystem argument: '{$subsystem}'.");
    exit(0);
}

// Interface key to manage
$ifkey = 'wan';
// Determine whether WAN interface is currently enabled
$ifkey_enabled = !empty($config['interfaces'][$ifkey]['enable']) ? true : false;

// MASTER event
if ($type === "MASTER") {
    // Enable WAN only if it's currently disabled
    if (!$ifkey_enabled) {
        log_msg("CARP event: switching to '$type', enabling interface '$ifkey'.", LOG_WARNING);
        $config['interfaces'][$ifkey]['enable'] = '1';
        write_config("enable interface '$ifkey' due CARP event '$type'", false);
        interface_configure(false, $ifkey, false, false);
    } else {
        log_msg("CARP event: already '$type' for interface '$ifkey', nothing to do.");
    }

// BACKUP event
} else {
    // Disable WAN only if it's currently enabled
    if ($ifkey_enabled) {
        log_msg("CARP event: switching to '$type', disabling interface '$ifkey'.", LOG_WARNING);
        unset($config['interfaces'][$ifkey]['enable']);
        write_config("disable interface '$ifkey' due CARP event '$type'", false);
        interface_configure(false, $ifkey, false, false);
    } else {
        log_msg("CARP event: already '$type' for interface '$ifkey', nothing to do.");
    }
}
```
### Packets Drop

Problem while pinging bastion from user vlan, some pings are lost (9%)
same while pinging the main switch

no problem pinging dockerVM (vlan Lab)
no problem towards IoT vlan

problem from mgmt to any other network
not even a single ping to dockerVM

ping problem ->

Solution: disable Proxmox firewall on vmbr0 (and all interfaces) for the OPNsense VM


### Other

Warning rtsold <interface_up> vtnet1 is disabled. in the logs (OPNsense)

Error dhcp6c transmit failed: Can't assign requested address

## Last Failover

Everything is fine.
When entering CARP maintenance mode, no packet drop is observed.
For a failover, only one packet is dropped

![Pasted_image_20251115225054.png](img/Pasted_image_20251115225054.png)


backup node:
![Pasted_image_20251116202728.png](img/Pasted_image_20251116202728.png)

master node:
![Pasted_image_20251116203049.png](img/Pasted_image_20251116203049.png)

ragequit, disable ipv6
## Clean Up

Shutdown OPNsense
done: 16/11/2025 : 12h40

Check watt
Check temp

## Rollback