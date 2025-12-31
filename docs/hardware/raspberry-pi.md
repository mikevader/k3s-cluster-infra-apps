# Raspberry Pi Setup

This guide covers the hardware setup and initial configuration of Raspberry Pi nodes for the k3s cluster.

## Hardware Components

### Control Plane Nodes (3x)
- **Model**: Raspberry Pi 4 Model B
- **RAM**: 8GB
- **Boot Storage**: Corsair GTX USB Stick
- **Power**: PoE HAT (some nodes)
- **Purpose**: k3s control plane (etcd + API server)

### Worker Nodes (4x)
- **Model**: Raspberry Pi 4 Model B
- **RAM**: 8GB
- **Boot Storage**: Corsair GTX USB Stick
- **Data Storage**: External USB NVMe drive (separately powered)
- **Power**: PoE HAT (some nodes) or standard USB-C
- **Purpose**: Application workloads + Longhorn storage

## Initial Setup

### Prerequisites

- MAC address configured in DHCP server
- Raspberry Pi Imager downloaded
- External NVMe drive (for worker nodes)
- USB-C power supply or PoE switch

### Imaging the SD Card/USB Stick

1. **Download Raspberry Pi Imager**
   - https://www.raspberrypi.com/software/

2. **Image Ubuntu Server**
   - OS → Other general purpose OS → Ubuntu → Ubuntu Server 24.04 LTS (64-bit)
   
3. **Customization Settings**:
   - Hostname: `<nodename>` (e.g., k3s-server01, k3s-worker01)
   - Username/Password: `ubuntu`/`ubuntu`
   - Enable SSH with password authentication
   - Configure Wi-Fi (if needed, but wired recommended)

4. **Write to USB stick**

5. **Boot the Raspberry Pi**
   - Insert USB stick
   - Power on
   - Wait for first boot (can take 2-3 minutes)

### First Login

```bash
# Remove old host keys if re-imaging
ssh-keygen -R <hostname>
ssh-keygen -R <ip-address>

# Login (default password: ubuntu)
ssh ubuntu@<hostname>

# Change password on first login (prompted)
```

### Initial System Update

```bash
# Update package list and upgrade
sudo apt update && sudo apt full-upgrade -y

# Reboot to apply updates
sudo reboot

# After reboot, update firmware
sudo rpi-eeprom-update -a
sudo reboot
```

## Hardware Configuration

### PoE HAT Fan Control

The PoE HAT fan can oscillate between min and max speed, which is annoying.

**Fix** (based on [Jeff Geerling's article](https://www.jeffgeerling.com/blog/2021/taking-control-pi-poe-hats-overly-aggressive-fan)):

```bash
# Edit the config
sudo nano /boot/firmware/config.txt

# Add these lines
dtparam=poe_fan_temp0=50000
dtparam=poe_fan_temp1=60000
dtparam=poe_fan_temp2=70000
dtparam=poe_fan_temp3=80000

# Reboot
sudo reboot
```

This sets temperature thresholds for fan speed:
- Below 50°C: Fan off
- 50-60°C: Low speed
- 60-70°C: Medium speed
- 70-80°C: High speed
- Above 80°C: Max speed

### External NVMe Drive Setup

For worker nodes with external storage (for Longhorn):

#### 1. Identify the Drive

```bash
lsblk -f
```

Example output:
```
NAME   FSTYPE LABEL UUID                                 MOUNTPOINT
sda                                                      
└─sda1 ext4         9999-9999-9999-9999                  
```

#### 2. Wipe Existing Data (if reusing drive)

```bash
sudo wipefs -a /dev/sda
```

#### 3. Create Partition Table

```bash
sudo fdisk /dev/sda
```

Commands in fdisk:
```
g     # Create new GPT partition table
n     # New partition
1     # Partition number (default)
      # First sector (default)
      # Last sector (default)
w     # Write changes
```

#### 4. Create Filesystem

```bash
sudo mkfs.ext4 /dev/sda1
```

#### 5. Mount Drive

```bash
# Create mount point
sudo mkdir -p /var/lib/longhorn

# Get UUID
sudo lsblk -o name,uuid

# Add to fstab
echo "UUID=<your-uuid> /var/lib/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Mount
sudo mount /var/lib/longhorn

# Verify
df -h | grep longhorn
```

### Power Supply Configuration

For nodes using UPS:

Reference: https://github.com/dzomaya/NUTandRpi

## Ansible Provisioning

Once the hardware is set up, use Ansible to configure the software:

### 1. Add Node to Ansible Inventory

Edit `hosts.yaml`:

```yaml
all:
  children:
    k3s_servers:
      hosts:
        k3s-server01:
          ansible_host: 192.168.1.10
        k3s-server02:
          ansible_host: 192.168.1.11
        k3s-server03:
          ansible_host: 192.168.1.12
    
    k3s_workers:
      hosts:
        k3s-worker01:
          ansible_host: 192.168.1.20
        k3s-worker02:
          ansible_host: 192.168.1.21
```

### 2. Run User and SSH Key Setup

```bash
ansible-playbook add-user-ssh.yaml --limit k3s-worker01
```

This will:
- Create your user account
- Add SSH keys
- Configure sudo access

### 3. Join Node to Cluster

```bash
# For control plane nodes
ansible-playbook playbooks/06_k3s_secure.yaml --limit k3s-server03 --tags server

# For worker nodes
ansible-playbook playbooks/06_k3s_secure.yaml --limit k3s-worker01
```

### 4. Verify Node Joined

```bash
kubectl get nodes
```

## Troubleshooting

### Node Won't Boot

1. **Check power supply**: Raspberry Pi 4 needs 3A USB-C power
2. **Check boot order**: May need to configure in EEPROM
3. **Re-flash USB stick**: Might be corrupted

### Can't SSH to Node

1. **Check DHCP**: Is node getting IP?
2. **Check network cable**: Is it connected?
3. **Check SSH service**: `sudo systemctl status ssh` (via console)

### External Drive Not Mounting

```bash
# Check if drive is detected
lsblk

# Check fstab
cat /etc/fstab

# Check mount errors
sudo journalctl -u local-fs.target

# Manual mount for testing
sudo mount -t ext4 /dev/sda1 /var/lib/longhorn
```

### Longhorn Can't Use Drive

```bash
# Check permissions
ls -la /var/lib/longhorn

# Fix if needed
sudo chown -R root:root /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn

# Verify Longhorn can access
kubectl get node -o jsonpath='{.items[*].metadata.annotations.longhorn\.io/default-disks-config}' | jq
```

### High Temperature

```bash
# Check current temp
vcgencmd measure_temp

# If over 80°C consistently:
# - Check PoE HAT fan is running
# - Add heatsinks
# - Improve case ventilation
# - Check ambient room temperature
```

## Firmware Updates

### Update EEPROM

```bash
# Check current version
sudo rpi-eeprom-update

# Update to latest
sudo rpi-eeprom-update -a

# Reboot to apply
sudo reboot
```

### Boot from USB

To boot from USB instead of SD card:

```bash
# Update bootloader config
sudo raspi-config

# Advanced Options → Boot Order → USB Boot
# Reboot
```

## Performance Tuning

### Overclock (Optional)

Edit `/boot/firmware/config.txt`:

```ini
# Overclock to 2.0 GHz (safe for Pi 4)
over_voltage=6
arm_freq=2000

# GPU memory (we don't need much)
gpu_mem=16
```

**Warning**: Overclocking can reduce lifespan and increase heat. Monitor temperatures.

### Network Tuning

For better network performance:

```bash
# Edit sysctl.conf
sudo nano /etc/sysctl.conf

# Add these lines
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

# Apply
sudo sysctl -p
```

## Hardware Accessories

### BlinkStick Nano

For visual status indicators: https://www.blinkstick.com/products/blinkstick-nano

Can be used to show node status (green = healthy, red = problems).

### Recommended Accessories

- **PoE HAT**: Official Raspberry Pi PoE+ HAT
- **Heatsinks**: Aluminum heatsinks for CPU, RAM, and USB controller
- **Case**: Cluster cases like GeeekPi or Uctronics
- **Network**: Gigabit switch with PoE (if using PoE HATs)
- **Storage**: High-quality USB 3.0 NVMe enclosures (not cheap ones!)

## Maintenance

### Monthly Tasks

```bash
# Update OS
sudo apt update && sudo apt full-upgrade -y

# Check disk health
sudo smartctl -a /dev/sda

# Check system logs for errors
sudo journalctl -p err -b

# Clean old logs
sudo journalctl --vacuum-time=30d
```

### Monitoring

- CPU temperature: Should stay below 80°C under load
- Disk space: Keep at least 20% free
- Memory usage: Should have swap available
- Network: Check for packet loss

## Reference Links

- [Raspberry Pi Documentation](https://www.raspberrypi.com/documentation/)
- [Ubuntu on Raspberry Pi](https://ubuntu.com/raspberry-pi)
- [Jeff Geerling's Pi Cluster](https://www.jeffgeerling.com/blog/2021/raspberry-pi-cluster-episode-1-introduction-clusters)
- [k3s on Raspberry Pi](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/)
