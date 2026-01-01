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

``` bash
apt-get update

apt full-upgrade

reboot
```

### Storage

BE CAREFUL. This is meant for the storage/longhorn disks as it will wipe it

``` bash title="select the correct disk device"
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

Add the following lines to the main network interface so all vlans are served
over one interface and supports vlan ids from 2 to 4096.

``` bash title="/etc/network/interfaces" hl_lines="5 6"
iface vmbr0 inet static
    address 192.168.xx.xx/24
    gateway 192.168.xx.xx
    ...
    bridge-vlan-aware yes
    bridge-vids 2-4094
```


### ISOs

Define images:

* https://releases.ubuntu.com/22.10/ubuntu-22.10-live-server-amd64.iso
* https://releases.ubuntu.com/noble/ubuntu-24.04.1-live-server-amd64.iso


## Setup worker node

First select `Create VM` 

Depending on the usage the parameters may vary. But following is a node which is
part of the longhorn storage and has an interface to the internet. The list
defines mostly non default values. If nothing else specified take the defaults.

* General:
    * Node: pve1-x
    * Name: k3sworker
    * Start at boot: true
* OS:
    * Storage: local
    * ISO Image: ubuntu server installer
* System:
    * Qemu Agent: true
* Disks:
    * disk 1:
        * Storage: local
        * Size: 128 GB
        * Backup: yes
        * Skip replication: no
        * Discard: yes
        * SSD emulation: yes
    * disk 2: (for longhorn but passthrough is preferred)
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
    * min 16 GB (16384 MiB)  
    * opt 32 GB (32768 MiB)
    * max 64 GB (65536 MiB) (You can't use all memory, keep 2GB)
* Network:
    * net0
        * Bridge: vmbr0
    * net1
        * Bridge: vmbr0
        * vlan tag: 99

Don't forget to define the generated mac address in DHCP

You might have to adjust the boot order for CD to be first.

### Disk passthrough

The disks for longhorn, especially the slower ones like HDD, should be attached to the VM directly.
Unfortunately there is no way to do this in the Web UI at the moment but proxmox provides quite a 
[good guide][proxmox-passthrough] for it.

Go through the following steps

1. Find right disk

```bash
find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12
```

or

``` bash
lsblk |awk 'NR==1{print $0" DEVICE-ID(S)"}NR>1{dev=$1;printf $0" ";system("find /dev/disk/by-id -lname \"*"dev"\" -printf \" %p\"");print "";}'|grep -v -E 'part|lvm'
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


### GPU Passthrough

**As prerequisite** you should make sure the onboard graphics is still enabled and is the primary display.

I follow the suggestions from [proxmox passthrough guide][proxmox-pci-passthrough]:

First you want to blacklist GPU drivers to prevent the host from loading the GPU (we want to use in the VM :D )

``` bash
echo "blacklist amdgpu" >> /etc/modprobe.d/blacklist.conf
echo "blacklist radeon" >> /etc/modprobe.d/blacklist.conf

echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf 
echo "blacklist nvidia*" >> /etc/modprobe.d/blacklist.conf

echo "blacklist i915" >> /etc/modprobe.d/blacklist.conf
```

After setting this you have to update the `ramfs` and reboot the system.

``` bash
update-initramfs -u -k all
```

Find Vendor and Devide ID to use for the VM Device (vfio)

``` shell
echo "options vfio-pci ids=10de:1ff0 disable_vga=1" > /etc/modprobe.d/vfio.conf
```

Reboot and add raw device (select map all functions)


``` shell
hostpci0: 0000:01:00,pcie=1
```

### Nvidia drivers on k3s node

https://ubuntu.com/server/docs/nvidia-drivers-installation

https://www.declarativesystems.com/2023/11/04/kubernetes-nvidia.html

https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html


https://radicalgeek.co.uk/pi-cluster/adding-a-gpu-node-to-a-k3s-cluster/


## Tips & Trick

### Resize disk

```bash
sudo lvresize -l +100%FREE --resizefs /dev/mapper/ubuntu--vg-ubuntu--lv
```

### Install Qemu Agent

```bash
ssh devops@k3sworker<xy>
sudo apt-get install qemu-guest-agent
```


## References

[tt-proxmox]: https://docs.technotim.live/posts/first-11-things-proxmox/
[proxmox-passthrough]: https://pve.proxmox.com/wiki/Passthrough_Physical_Disk_to_Virtual_Machine_(VM)
[proxmox-pci-passthrough]: https://pve.proxmox.com/wiki/PCI_Passthrough
[gpu-passthrough-guide]: https://pve.proxmox.com/pve-docs/pve-admin-guide.html#_gpu_passthrough_notes
