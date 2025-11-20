---
slug: migration-opnsense-proxmox-highly-available
title: migration-opnsense-proxmox-highly-available
description: migration-opnsense-proxmox-highly-available
date: 2025-11-20
draft: true
tags:
  - opnsense
  - high-availability
  - proxmox
categories:
  - homelab
---
## Intro

Final stage of my **OPNsense** virtualization journey!

Some months ago, my physical [OPNsense box crashed]({{< ref "post/10-opnsense-crash-disk-panic" >}}) because of a hardware failure. This leads my home in the dark, literally. No network, no lights.

💡 To avoid being in that situation again, I imagine a way to virtualize my OPNsense firewall into my **Proxmox VE** cluster. The last time, I've set up a [proof of concept]({{< ref "post/12-opnsense-virtualization-highly-available" >}}) to validate this solution: create a cluster of two **OPNsense** VMs in Proxmox and make the firewall highly available.

This time, I will cover the creation of my future OPNsense cluster from scratch, plan the cut over and finally migrate from my current physical box. Let's go!

---
## The VLAN Configuration

For my plans, I'll have to connect the WAN, coming from my ISP box, to my main switch. For that I create a dedicated VLAN to transport this flow to my Proxmox nodes.

### UniFi

The first thing I do is to configure my layer 2 network which is managed by UniFi. There I need to create two VLANs:
- *WAN* (20): transport the WAN between my ISP box and my Proxmox nodes.
- *pfSync* (44), communication between my OPNsense nodes.

In the UniFi controller, in `Settings` > `Networks`, I add a `New Virtual Network`. I name it `WAN` and give it the VLAN ID 20:
![unifi-add-vlan-for-wan.png](img/unifi-add-vlan-for-wan.png)

I do the same thing again for the `pfSync` VLAN with the VLAN ID 44.

I plan to plug my ISP box on the port 15 of my switch, which is disabled for now. I set it as active, set the native VLAN on the newly created one `WAN (20)` and disable trunking:
![unifi-enable-port-wan-vlan.png](img/unifi-enable-port-wan-vlan.png)

Once this setting applied, I make sure that only the ports where are connected my Proxmox nodes propagate these VLAN on their trunk. 

I'm done with UniFi configuration.

### Proxmox SDN

Now that the VLAN can reach my nodes, I want to handle it in the Proxmox SDN. I've configured the SDN in [that article]({{< ref "post/11-proxmox-cluster-networking-sdn" >}}).

In `Datacenter` > `SDN` > `VNets`, I create a new VNet, call it `vlan20` to follow my own naming convention, give it the *WAN* alias and use the tag (VLAN ID) 20:
![proxmox-sdn-new-vnet-wan.png](img/proxmox-sdn-new-vnet-wan.png)

I also create the `vlan44` for the *pfSync* VLAN, then I apply this configuration and we are done with the SDN.

---
## Create the VMs

Now that the VLAN configuration is done, I can start buiding the virtual machines on Proxmox.

The first VM is named `cerbere-head1` (I didn't tell you? My current firewall is named `cerbere`, it makes even more sense now!). Here are the settings:
- **OS type**: Linux (even if OPNsense is  based on FreeBSD)
- **Machine type**: `q35`
- **BIOS**: `OVMF (UEFI)`
- **Disk**: 20 GiB on Ceph distributed storage
- **RAM**: 4 GiB RAM, ballooning disabled
- **CPU**: 2 vCPU
- **NICs**, firewall disabled:
	1. `vmbr0` (*Mgmt*)
	2. `vlan20` (*WAN*)
	3. `vlan13` *(User)*
	4. `vlan37` *(IoT)*
	5. `vlan44` *(pfSync)*
	6. `vlan55` *(DMZ)*
	7. `vlan66` *(Lab)*
![proxmox-cerbere-vm-settings.png](img/proxmox-cerbere-vm-settings.png)

ℹ️ Now I clone that VM to create `cerbere-head2`, then I proceed with OPNsense installation. I don't want to go into much details about OPNsense installation, I already documented it in the [proof of concept]({{< ref "post/12-opnsense-virtualization-highly-available" >}}).

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

---
## Migration

🚀 Time to make it real!

I'm not gonna lie, I'm quite excited. I'm working for this moment for days. 

### The Migration Plan

I have my physical OPNsense box directly connected to my ISP box. I want to swap it for the VM cluster. To avoid writing the word OPNsense on each line, I'll simply name it the box and the VM.

Here is the plan:
1. Backup of the box configuration.
2. Disable DHCP server on the box.
3. Change IP addresses of the box.
4. Change VIP on the VM.
5. Disable gateway on VM.
6. Configure DHCP on both VMs.
7. Enable mDNS repeater on VM.
8. Replicate services on VM.
9. Ethernet cable swap.
### Rollback Strategy

None. 😎

I'm kidding, the rollback consists of restoring the box configuration, shutdown the OPNsense VMs and plug back the Ethernet cable into the box.

### Verification Plan

To validate the migration, I'm drawing up a checklist:
1. WAN DHCP lease in the VM.
2. Ping from my PC to the VIP of the User VLAN.
3. Ping cross VLAN.
4. SSH into my machines.
5. Renew DHCP lease.
6. Check `ipconfig`
7. Test internet website.
8. Check firewall logs.
9. Check my webservices.
10. Verify if my internal webservices are not accessible from outside.
11. Test VPN.
12. Check all IoT devices.
13. Check Home Assistant features.
14. Check if the TV works.
15. Test the Chromecast.
16. Print something.
17. Verify DNS blocklist.
18. Speedtest.
19. Switchover.
20. Failover.
21. Disaster Recovery.
22. Champaign!

Will it work? Let's find out! 

### Migration Steps

1. **Backup of the box configuration.**

On my physical OPNsense instance, in `System` > `Configuration` > `Backups`, I click the `Download configuration` button which give me the precious XML file. The one that saved my ass the [last time]({{< ref "post/10-opnsense-crash-disk-panic" >}}).

2. **Disable DHCP server on the box.**

In `Services` > `ISC DHCPv4`, and for all my interfaces, I disable the DHCP server. I only serve DHCPv4 in my network.

3. **Change IP addresses of the box.**

In `Interfaces`, and for all my interfaces, I modify the IP of the firewall, from `.1` to `.253`. I want to reuse the same IP address as VIP, and have this instance still reachable if needed.

As soon as I click on `Apply`, I lost the communication, which is expected.

4. **Change VIP on the VM.**

On my master VM, In `Interfaces` > `Virtual IPs` > `Settings`, I change the VIP address for each interface and set it to `.1`.

5. **Disable gateway on VM.**

In `System` > `Gateways` > `Configuration`, I disable the `LAN_GW` which is not needed anymore.

6. **Configure DHCP on both VMs.**

In both VM, in `Services` > `Dnsmasq DNS & DHCP`, I enable the service on my 5 interfaces.

7. **Enable mDNS repeater on VM.**

In `Services` > `mDNS Repeater`, I enable the service and also enable CARP Failover.

The service does not start. I'll see that problem later.

8. **Replicate services on VM.**

In `System` > `High Availability` > `Status`, I click the button to `Synchronize and reconfigure all`.

9. **Ethernet cable swap.**

Physically in my rack, I unplug the Ethernet cable from the WAN port (`igc0`) of my physical OPNsense box and plug it into the port 15 of my UniFi switch.

---
## Verification

😮‍💨 I take a deep breath and start the verification phase.

### Checklist

- ✅ WAN DHCP lease in the VM.
- ✅ Ping from my PC to the VIP of the User VLAN.
- ⚠️ Ping cross VLAN.
Pings are working, but I observe some drops, about 10%.
- ✅ SSH into my machines.
- ✅ Renew DHCP lease.
- ✅ Check `ipconfig`
- ❌ Test internet website. → ✅

A few websites are working, everything is incredibly slow... It must be the DNS. I try to lookup a random domain, it is working. But I can't lookup google.com. I restart the Unbound DNS service, everything works now. It is always the DNS.
- ⚠️ Check firewall logs.

Few flows are blocks, not mandatory.
- ✅Check my webservices.
- ✅Verify if my internal webservices are not accessible from outside.
- ✅ Test VPN.
- ✅ Check all IoT devices.
- ✅ Check Home Assistant features.
- ✅Check if the TV works.
- ❌ Test the Chromecast.

It is related to the mDNS service not able to start. I can start it if I uncheck the `CARP Failover` option. the Chromecast is visible now. → ⚠️
- ✅Print something.
- ✅Verify DNS blocklist.
- ✅Speedtest

I observe roughly 15% of decrease bandwidth (from 940Mbps to 825Mbps). 
- ❌ Switchover

The switchover barely works, a lot of dropped packets during the switch. The service provided is not great: no more internet and my webservices are not reachable.
- ⌛ Failover
- ⌛ Disaster Recovery

To be tested later.

📝 Well, the results are pretty good, not perfect, but satisfying!
###  Problem Solving

I focus on resolving remaining problems experienced during the tests.

1. **DNS**

During the switchover, the internet connection is not working. No DNS, it is always DNS.

It's because the backup node does not have a gateway while passive. No gateway prevents the DNS to resolve. After the switchover, it still has unresolved domains in its cache. This problem also lead to another issue, while passive, I can't update the system.

**Solution**: Set a gateway in the *Mgmt* interface pointing to the other node, with a higher priority number than the WAN gateway (higher number means lower priority). This way, that gateway is not active while the node is master.

2. **Reverse Proxy**

During the switchover, every webservices which I host (reverse proxy/layer 4 proxy) give this error: `SSL_ERROR_INTERNAL_ERROR_ALERT`. After checking the services synchronized throught XMLRPC Sync, Caddy and mDNS-repeater were not selected. It is because these services were installed after the initial configuration of the HA. 

**Solution**: Add Caddy to XMLRPC Sync.

3. **Packet Drops**

I observe about 10% packet drops for pings from any VLAN to the *Mgmt* VLAN. I don't have this problem for the other VLANs.

The *Mgmt* VLAN is the native one in my network, it might be the reason behind this issue. This is the only network not defined in the Proxmox SDN. I don't want to have to tag this VLAN.

**Solution**: Disable the Proxmox firewall of this interface for the VM. I actually disable them all and update the documentation above. I'm not sure why this cause that kind of problem, but disabling it fixed my issue (I could reproduce the behavior while activating the firewall again).

4. **CARP Script**

During a switchover, the CARP event script is triggered as many times as the number of interfaces. I have 5 virtual IPs, the script reconfigure my WAN interface 5 times.

**Solution**: Rework the script to get the WAN interface state and only reconfigure the inteface when needed:
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

5. **mDNS Repeater**

The mDNS repeater does not want to start when I select the option for `CARP Failover`.

**Solution**: The machine requires a reboot to start this service CARP aware.

6. **IPv6 Address**

My `cerbere-head1` node is crying in the log file while the other does not. Here are the messages spit every seconds while it is master:
```plaintext
Warning rtsold <interface_up> vtnet1 is disabled. in the logs (OPNsense)
```

Another one I'm having several times after a switchback:
```plaintext
Error dhcp6c transmit failed: Can't assign requested address
```

This is related to IPv6. I observe that my main node does not have a global IPv6 address, only a link-local. Also, it does not have a IPv6 gateway. My secondary node, in the other hand, has both addresses and the gateway.

I'm no IPv6 expert, after searching for a couple of hours, I give up the IPv6. If someone out here can help, it would be really appreciated!

**Workaround**: Remove DHCPv6 for my WAN interface. 

### Confirmation

Now that everything is fixed, I can evaluate the failover performance.

1. **Switchover**

When manually entering CARP maintenance mode from the WebGUI interface, no packet drop is observed. Impressive.

2. Failover

To simulate a failover, I kill the active OPNsense VM. Here I observe only one packet dropped. Awesome.

![opnsense-ping-failover.png](img/opnsense-ping-failover.png)

3. Disaster Recovery

A disaster recovery is what would happen after a full Proxmox cluster stop, after an electrical outage for example. I didn't have the time (or the courage) to do that, I'd prefer to prepare a bit better to avoid collateral damages. But surely, this kind of scenario must be evaluated.

### Extras

Leaving aside the fact that this new setup is more resilient, I have few more bonuses.

My rack is tiny and the space is tight. The whole thing is heating quite much, exceeding 40°C on top of the rack in summer. Reducing the number of machines powered up lower the temperature. I've gained **1,5°C** after shutting down the old OPNsense box, cool!

Power consumption is also a concern, my tiny datacenter was drawing 85W on average. Here again I could observe a small decrease, about 8W lower. Considering that this run 24/7, not negligible.

Finally I also removed the box itself and the power cable. Slots are very limited, another good point.

---
## Conclusion

🎉 I did it guys! I'm very proud of the results, proud of myself.

From my [first OPNsense box crash]({{< ref "post/10-opnsense-crash-disk-panic" >}}), the thinking about a solution, the HA [proof of concept]({{< ref "post/12-opnsense-virtualization-highly-available" >}}), to this migration. This has been a quite long project, but extremly interesting.

🎯 This is great to set objectives, but this is even better when you reach them.

Now I'm going to leave OPNsense aside for a bit, to be able to re-focus on my Kubernetes journey!

As always, if you have questions, remarks or a solution for my IPv6 problem, I'll be really happy to share with you