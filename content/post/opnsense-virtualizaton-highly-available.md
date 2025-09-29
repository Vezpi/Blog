---
slug: opnsense-virtualization-highly-available
title: Template
description:
date:
draft: true
tags:
  - opnsense
  - proxmox
  - high-availability
categories:
  - homelab
---
## Intro

I recently encountered my first real problem, my physical **OPNsense** box crashed because of a kernel panic, I've detailed what happened in that [post]({{< ref "post/10-opnsense-crash-disk-panic" >}}). 

That failure made me rethink my setup. A unique firewall is a single point of failure, so to improve resilience I decided to take a new approach: **virtualize OPNsense**.

Of course, just running one VM wouldn’t be enough. To get real redundancy, I need two OPNsense instances in **High Availability**, with one active and the other standing by.

Before rolling this out in my network, I wanted to demonstrate the idea in my homelab. 
In this post, I’ll walk through the proof of concept: deploying two OPNsense VMs inside a **Proxmox VE** cluster and configuring them to provide a highly available firewall.

---
## Current Infrastructure

At the edge of my setup, my ISP modem, a *Freebox* in bridge mode, connects directly to the `igc0` interface of my OPNsense box, serving as the **WAN**. On `igc1`, the **LAN** is linked to my main switch using a trunk port, with VLAN 1 as the native VLAN for my management network.

The switch also connects my three Proxmox nodes, each on trunk ports with the same native VLAN. Every node has two NICs: one for general networking and the other dedicated to the Ceph storage network, which runs through a separate 2.5 Gbps switch.

Since the OPNsense crash, I’ve simplified things by removing the LACP link, it wasn’t adding real value:
![homelan-current-physical-layout.png](img/homelan-current-physical-layout.png)


Until recently, Proxmox networking on my cluster was very basic: each node was configured individually with no real overlay logic. That changed after I explored Proxmox SDN, where I centralized VLAN definitions across the cluster. I described that step in [this article]({{< ref "post/11-proxmox-cluster-networking-sdn" >}}).

---
## Proof of Concept

Time to move into the lab. Here are the main steps:
1. Add some VLANs in my Homelab
2. Create Fake ISP router
3. Build two OPNsense VMs
4. Configure high availability
5. Test failover

![Diagram of the POC for OPNsense high availability](img/poc-opnsense-diagram.png)

### Add VLANs in my Homelab

For this experiment, I create 3 new VLANs:
- **VLAN 101**: *POC WAN* 
- **VLAN 102**: *POC LAN*
- **VLAN 103**: *POC pfSync*

In the Proxmox UI, I navigate to `Datacenter` > `SDN` > `VNets` and I click `Create`:
![Create POC VLANs in the Proxmox SDN](img/proxmox-sdn-create-poc-vlans.png)

Once the 3 new VLAN have been created, I apply the configuration.

Additionally, I add these 3 VLANs in my UniFi Controller. Here only the VLAN ID and name are needed, since the controller will propagate them through the trunks connected to my Proxmox VE nodes.

### Create Fake ISP Box VM

To simulate my current ISP modem, I built a VM named `fake-freebox`. This VM routes traffic between the _POC WAN_ and _POC LAN_ networks and runs a DHCP server that serves only one lease, just like my real Freebox in bridge mode.

This VM has 2 NICs, I configure Netplan with:
- `eth0` (*POC WAN* VLAN 101): static IP address `10.101.0.254/24`
- enp6s19 (Lab VLAN 66): DHCP address given by my current OPNsense router, my upstream
```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.101.0.254/24
    enp6s19:
      dhcp4: true
```

I enable packet forward to allow this VM to route traffic:
```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Then I set up masquerading so packets leaving through the lab network wouldn’t be dropped by my production OPNsense:
```bash
sudo iptables -t nat -A POSTROUTING -o enp6s19 -j MASQUERADE
sudo apt install iptables-persistent -y
sudo netfilter-persistent save
```

I install `dnsmasq` as a lightweight DHCP server:
```bash
sudo apt install dnsmasq -y
```

I configure `/etc/dnsmasq.conf` to serve exactly one lease (`10.101.0.150`) with DNS pointing to my real OPNsense router, in the *Lab* VLAN:
```
interface=eth0
bind-interfaces
dhcp-range=10.101.0.150,10.101.0.150,255.255.255.0,12h
dhcp-option=3,10.101.0.254      # default gateway = this VM
dhcp-option=6,192.168.66.1      # DNS server  
```

I restart the dnsmasq service to apply the configuration:
```bash
sudo systemctl restart dnsmasq
```

The `fake-freebox` VM is now ready to serve DHCP on VLAN 101 and serve only one lease.

### Build OPNsense VMs

First I download the OPNsense ISO and upload it to one of my Proxmox nodes:
![Upload the OPNsense ISO into Proxmox](img/proxmox-upload-opnsense-iso.png)

#### VM Creation

I create the first VM `poc-opnsense-1`, with the following settings:
- OS type:  Linux(even though OPNsense is FreeBSD-based)
- Machine type: `q35`
- BIOS: `OVMF (UEFI)`, EFI storage on my Ceph pool
- Disk: 20 GiB also on Ceph
- CPU/RAM: 2 vCPU, 2 GiB RAM
- NICs:
	1. VLAN 101 (POC WAN)
	2. VLAN 102 (POC LAN)
	3. VLAN 103 (POC pfSync)
![OPNsense VM settings in Proxmox](img/proxmox-create-poc-vm-opnsense.png)

ℹ️ Before booting it, I clone this VM to prepare the second one: `poc-opnsense-2`

On first boot, I hit an “access denied” error. To fix this, I enter the BIOS, go to **Device Manager > Secure Boot Configuration**, uncheck _Attempt Secure Boot_, and restart the VM:
![Disable Secure Boot in Proxmox BIOS](img/proxmox-disable-secure-boot-option.png)

#### OPNsense Installation

The VM boots on the ISO, I touch nothing until I get into the login screen:
![OPNsense CLI login screen in LiveCD](img/opnsense-vm-installation-welcome.png)

I log in as `installer` / `opnsense` and launch the installer. I select the QEMU hard disk of 20GB as destination and launch the installation:
![OPNsense installation progress bar](img/opnsense-vm-installation-progress-bar.png)

Once the installation is finished, I remove the ISO from the drive and restart the machine.

#### OPNsense basic configuration

After reboot, I log in as `root` / `opnsense` and get into the CLI menu:
![OPNsense CLI login screen after fresh installation](img/opnsense-vm-installation-cli-menu.png)

Using option 1, I reassigned interfaces:
![OPNsense interface configuration using CLI](img/opnsense-vm-installation-assign-interfaces.png)

The WAN interface successfully pulled `10.101.0.150/24` from the `fake-freebox`. I set the LAN interface to `10.102.0.2/24` and configured a DHCP pool from `10.102.0.10` to `10.102.0.99`:
![OPNsense WAN interface getting IP from `fake-freebox` VM](img/opnsense-vm-installation-interfaces-configured.png)

✅ The first VM is ready, I start over for the second OPNsense VM, `poc-opnsense-2` which will have the IP `10.102.0.3`

### Configure OPNsense Highly Available

Now both of the OPNsense VMs are operational, I want to configure the instances from their WebGUI. To be able to do that, I need to have access from the *POC LAN* VLAN to the OPNsense interfaces in that network. Simple way to do that, connect a Windows VM in that VLAN and browse to the OPNsense IP address on port 443:
![OPNsense WebGUI from Windows VM](img/opnsense-vm-webgui-from-poc-lan.png)

#### Add pfSync Interface

The first thing I do is to assign the third NIC, the `vtnet2` to the *pfSync* interface. This network will be used by the firewalls to communicate between each others, this is one the VLAN *POC pfSync*:
![Add pfSync interface in OPNsense](img/opnsense-vm-assign-pfsync-interface.png)

I enable the interface on each instance and configure it with a static IP address:
- **poc-opnsense-1**: `10.103.0.2/24`
- **poc-opnsense-2**: `10.103.0.3/24`

On both instances, I create a firewall rule to allow communication coming from this network on that *pfSync* interface:
![Create new firewall rule on pfSync interface to allow any traffic in that network](img/opnsense-vm-firewall-allow-pfsync.png)

#### Setup High Availability

Then I configure the HA in `System` > `High Availability` > `Settings`. On the master (`poc-opnsense-1`) I configure both the `General Settings` and the `Synchronization Settings`. On the backup (`poc-opnsense-2`) I only configure the `General Settings`:
![OPNsense High Availability settings](img/opnsense-vm-high-availability-settings.png)

Once applied, I can verify that it is ok on the `Status` page:
![OPNsense High Availability status](img/opnsense-vm-high-availability-status.png)

#### Create Virtual IP Address

Now I need to create the VIP for the LAN interface, an IP address shared across the cluster. The master node will claim that IP which is the gateway given to the clients. The VIP will use the CARP, Common Address Redundancy Protocol for failover. To create it, navigate to `Interfaces` > `Virtual IPs` > `Settings`:
![Create CARP virtual IP in OPNsense](img/opnsense-vm-create-vip-carp.png)

To replicate the config to the backup node, go to `System` > `High Availability` > `Status` and click the `Synchronize and reconfigure all` button. To verify, on both node navigate to `Interfaces` > `Virtual IPs` > `Status`. The master node should have the VIP active with the status `MASTER`, and the backup node with the status `BACKUP`.

#### Reconfigure DHCP

I need to reconfigure the DHCP for HA. Dnsmasq does not support DHCP lease synchronization, I have to configure the two instances independently, they would serve both DHCP lease at the same time.

On the master node, in `Services` > `Dnsmasq DNS & DHCP` > `General`, I tick the `Disable HA sync` box. Then in `DHCP ranges`, I edit the current one and also tick the `Disable HA sync` box. In `DHCP options`, I add the option `router [3]` with the value 10.102.0.1, to advertise the VIP address:
![Edit DHCP options for Dnsmasq in OPNsense](img/opnsense-vm-dnsmasq-add-option.png)

I clone that rule for the option `dns-server [6]` with the same address.

On the backup node, in `Services` > `Dnsmasq DNS & DHCP` > `General`, I also tick the `Disable HA sync` box, but I also set the value `5` to `DHCP reply delay`. This would give enough time to the master node to provide a DHCP lease before the backup node. In `DHCP ranges`, I edit the current one and give a smaller pool, different than the master's. Here I also tick the `Disable HA sync` box.

Now I can safely sync my services like described above, this will only propagate the DHCP options, which are mean to be the same.

#### WAN Interface

The last thing I need to configure is the WAN interface, my ISP box is only giving me one IP address over DHCP, I don't want my 2 VMs compete to claim it. To handle that, I give my 2 VMs the same MAC for the WAN interface, then I need to find a solution to enable the WAN interface only on the master node.

In the Proxmox WebGUI, I copy the MAC address of the net0 interface (*POC WAN*) from `poc-opnsense-1` and paste it to the one in `poc-opnsense-2`.

To handle the activation of the WAN interface on the master node while deactivating the backup, I can use a script. On CARP event, scripts located in `/usr/local/etc/rc.syshood.d/carp` are played. I found this [Gist](https://gist.github.com/spali/2da4f23e488219504b2ada12ac59a7dc#file-10-wancarp) which is exactly what I wanted.

I copy this script in `/usr/local/etc/rc.syshood.d/carp/10-wan` on both nodes:
```php
#!/usr/local/bin/php
<?php

require_once("config.inc");
require_once("interfaces.inc");
require_once("util.inc");
require_once("system.inc");

$subsystem = !empty($argv[1]) ? $argv[1] : '';
$type = !empty($argv[2]) ? $argv[2] : '';

if ($type != 'MASTER' && $type != 'BACKUP') {
    log_error("Carp '$type' event unknown from source '{$subsystem}'");
    exit(1);
}

if (!strstr($subsystem, '@')) {
    log_error("Carp '$type' event triggered from wrong source '{$subsystem}'");
    exit(1);
}

$ifkey = 'wan';

if ($type === "MASTER") {
    log_error("enable interface '$ifkey' due CARP event '$type'");
    $config['interfaces'][$ifkey]['enable'] = '1';
    write_config("enable interface '$ifkey' due CARP event '$type'", false);
    interface_configure(false, $ifkey, false, false);
} else {
    log_error("disable interface '$ifkey' due CARP event '$type'");
    unset($config['interfaces'][$ifkey]['enable']);
    write_config("disable interface '$ifkey' due CARP event '$type'", false);
    interface_configure(false, $ifkey, false, false);
}
```

### Test Failover

Time for testing! OPNsense provides a way to enter CARP maintenance mode. Before pushing the button, my master has its WAN interface enabled and the backup doesn't:
![OPNsense CARP maintenance mode](img/opnsense-vm-carp-status.png)

Once I enter the CARP maintenance mode, the master node become backup and vice versa, the WAN interface get disabled while it's enabling on the other node. I was pinging outside of the network while switching and experienced not a single drop!

Finally, I simulate a crash by powering off the master node and the magic happens! Here I have only one packet lost and, thanks to the firewall state sync, I can even keep my SSH connection alive.

## Conclusion


