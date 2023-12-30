# Setup Proxmox

Proxmox is an OpenSource virtualization software. The largere nodes are setup
with it and the nodes on it virtualized.


## Install Proxmox

First create a boot USB stick with Proxmox VE Installer ISO.

Select ZFS as filesystem as it will set the bootloader to systemd-boot instead of GRUB.


## First steps on a new Proxmox server

After setting up a new Proxmox server, there are a few things to do before they
can be used. Idealy those steps would be automated but ...

Those steps are heavily inspired by [techno tim setup article][tt-proxmox]


### Updates

Edit `/etc/apt/sources.list`

```shell
deb http://ftp.debian.org/debian bullseye main contrib

deb http://ftp.debian.org/debian bullseye-updates main contrib

# security updates
deb http://security.debian.org/debian-security bullseye-security main contrib

# PVE pve-no-subscription repository provided by proxmox.com,
# NOT recommended for production use
deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription
```

Edit `/etc/apt/sources.list.d/pve-enterprise.list`

```shell
# deb https://enterprise.proxmox.com/debian/pve buster pve-enterprise
```

Run

```bash
apt-get update

apt full-upgrade

reboot
```

### Storage

BE CAREFUL. This is meant for the storage/longhorn disks as it will wipe it

```shell caption="select the correct disk device"
fdisk /dev/sda
```

Then P for partition, then D for delete and W for write.

### IOMMU  (PCI Passthrough)

See [Proxmox PCI Passthrough](https://pve.proxmox.com/wiki/Pci_passthrough)

First make sure IOMMU is enabled in the BIOS.

`nano /etc/kernel/cmdline`

Add `intel_iommu=on iommu=pt` to the end of this line without line breaks. (for
AMD processors add `amd_iommu=on ...`)

```shell
root=ZFS=rpool/ROOT/pve-1 boot=zfs intel_iommu=on iommu=pt
```

Edit `/etc/modules` and add

```shell
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

run

```shell
update-initramfs -u -k all
# or proxmox-boot-tool refresh

reboot
```

### VLAN Aware

Setup the network interface to handle VLANs.

```bash
nano /etc/network/interfaces
```

Add the following lines to the main network interface

```shell
bridge-vlan-aware yes
bridge-vids 2-4094
```


### ISOs

Define images:

* https://releases.ubuntu.com/22.10/ubuntu-22.10-live-server-amd64.iso


## Setup worker node

Depending on the usage the parameters may vary. But following is a node which is
part of the longhorn storage and has an interface to the internet.

* General:
  * Node: pve1-x
  * Name: k3sworker
  * Start at boot: true
* OS:
  * ISO Image: ubuntu server installer
* System:
  * Qemu Agent: true
* Disks:
  * disk 1:
    * Storage: virtual
    * Size: 64 GB
    * Backup: yes
    * Skip replication: no
    * Discard: yes
    * SSD emulation: yes
  * disk 2:
    * Storage: virtual
    * Size: >512 GB
    * Backup: no
    * Skip replication: yes
    * Discard: yes
    * SSD emulation: yes
* CPU:
  * Sockets: 1
  * Cores: 2-12
* Memory:
  * min 32 GB
  * max 64 GB
* Network:
  * net0
    * Bridge: vmbr0
  * net1
    * Bridge: vmbr0
    * vlan tag: 99

Don't forget to define the generated mac address in DHCP


### Install Qemu Agent

```bash
ssh devops@k3sworker<xy>
sudo apt-get install qemu-guest-agent
```


### Disk passthrough

The disks for longhorn, especially the slower ones like HDD, should be attached to the VM directly.
Unfortunately there is no way to do this in the Web UI at the moment but proxmox provides quite a 
[good guide][proxmox-passthrough] for it.

Go through the following steps

1. Find right disk

```bash
find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12
```

2. Add drive as new virtual drive

```bash
qm set 592 -scsi2 /dev/disk/by-id/ata-...
```
Replace *592* with the correct VM id and -scsi*2* with the next scsi id.

3. Remove drive

```bash
qm unlink 592 --idlist scsi2
```

## Tips & Trick

### Resize disk

```bash
sudo lvresize -l +100%FREE --resizefs /dev/mapper/ubuntu--vg-ubuntu--lv
```

6510C08A-590C-477C-A72E-D3E25B972D5E

## References

[tt-proxmox]: https://docs.technotim.live/posts/first-11-things-proxmox/
[proxmox-passthrough]: https://pve.proxmox.com/wiki/Passthrough_Physical_Disk_to_Virtual_Machine_(VM)



--8<-- "includes/abbreviations.md"
