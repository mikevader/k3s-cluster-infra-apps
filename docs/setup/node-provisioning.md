# Node Provisioning

Automated node provisioning using Ansible. For hardware setup, see [Raspberry Pi Guide](../hardware/raspberry-pi.md).

## Prerequisites

```bash
# Create vault credentials file
touch ~/.vault-credentials
chmod 0600 ~/.vault-credentials
# Add your vault passphrase to this file

# Download Ansible Galaxy roles
ansible-galaxy install -r roles/requirements.yml
```

## Add New Node

### 1. Prepare Hardware

- Flash OS (Ubuntu Server 24.04 LTS)
- Boot and verify network connectivity
- First login: `ssh ubuntu@<hostname>` (password: ubuntu)
- Update: `sudo apt update && sudo apt full-upgrade -y && sudo reboot`
- Update firmware (Pi): `sudo rpi-eeprom-update -a && sudo reboot`

### 2. Add to Ansible Inventory

Edit `hosts.yaml`:

```yaml
all:
  children:
    k3s_servers:
      hosts:
        k3s-server01:
          ansible_host: 192.168.1.10
    k3s_workers:
      hosts:
        k3s-worker05:
          ansible_host: 192.168.1.25
```

### 3. Configure User & SSH

```bash
ansible-playbook add-user-ssh.yaml --limit k3s-worker05
```

### 4. Join to Cluster

```bash
# Workers
ansible-playbook playbooks/06_k3s_secure.yaml --limit k3s-worker05

# Control plane nodes
ansible-playbook playbooks/06_k3s_secure.yaml --limit k3s-server03 --tags server
```

### 5. Verify

```bash
kubectl get nodes
```

## Playbooks Reference

| Playbook | Purpose |
|----------|---------|
| `add-user-ssh.yaml` | User provisioning & SSH keys |
| `site.yml` | Full cluster deployment |
| `upgrade.yml` | OS package upgrades |
| `06_k3s_secure.yaml` | Join node to cluster |
| `07_k3s_update.yml` | Update K3S version |

## Storage Setup

After [partitioning the disk](../hardware/raspberry-pi.md#external-nvme-drive-setup):

```bash
# Mount Longhorn disk
sudo mkdir -p /var/lib/longhorn
UUID=$(sudo lsblk -no UUID /dev/sda1)
echo "UUID=$UUID /var/lib/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mount /var/lib/longhorn

# Verify
df -h | grep longhorn
kubectl get node -o jsonpath='{.items[*].metadata.annotations.longhorn\.io/default-disks-config}' | jq
```

## Rolling Updates

Update K3S version **one control plane node at a time**. Wait 5-10 minutes between nodes for Longhorn to stabilize.

```bash
# Update version in hosts.yaml first

# Update control plane sequentially
ansible-playbook playbooks/07_k3s_update.yml --limit k3s-server01
# Wait and verify cluster health...
ansible-playbook playbooks/07_k3s_update.yml --limit k3s-server02
# Wait and verify...
ansible-playbook playbooks/07_k3s_update.yml --limit k3s-server03

# Update workers
ansible-playbook playbooks/07_k3s_update.yml --limit k3s_workers
```

### Replace Node

```bash
# 1. Drain and delete
kubectl drain <nodename> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <nodename>

# 2. Verify etcd member removed (control plane only)
kubectl exec -n kube-system etcd-k3s-server01 -- etcdctl member list

# 3. Provision new node (see "Add New Node" above)
```

## MinIO Backup Target

### Install & Configure TLS

Install MinIO: https://min.io/docs/minio/linux/operations/install-deploy-manage/deploy-minio-single-node-single-drive.html

**TLS via Certbot:**
```bash
certbot certonly --manual --preferred-challenges dns -d minio.example.com
```

**TLS via OPNsense ACME:**
Configure SFTP upload automation in OPNsense to copy certs to MinIO server at `/home/minio-user/.minio/certs` (use fullchain.pem as public.crt).

**Prometheus monitoring:**
```bash
export MINIO_PROMETHEUS_URL=https://prometheus.example.com
export MINIO_PROMETHEUS_JOB_ID=minio-job
export MINIO_PROMETHEUS_AUTH_TYPE=public
```

### Create Backup Bucket

```bash
mc alias set myminio https://minio.example.com ACCESS_KEY SECRET_KEY

# Create bucket
mc mb myminio/k3s/etcd-snapshot

# Create user
mc admin user add myminio k3s <password>

# Create and apply policy
cat > /tmp/etcd-backups-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketPolicy"],
      "Resource": ["arn:aws:s3:::k3s"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::k3s/*"]
    }
  ]
}
EOF

mc admin policy create myminio etcd-backups-policy /tmp/etcd-backups-policy.json
mc admin policy attach myminio etcd-backups-policy --user k3s
```

### Configure K3S Backups

**Ansible vault** (`ansible-vault edit group_vars/all.yaml`):
```yaml
backup_s3_access_key: k3s
backup_s3_secret_key: <secure-password>
```

**Hosts/group vars:**
```yaml
backup_s3_enabled: true
backup_schedule_cron: '0 */6 * * *'
backup_s3_bucket: k3s
backup_s3_folder: etcd-snapshot
backup_s3_endpoint: minio.example.com
```

## Hardware-Specific Fixes

### Lenovo E1000 NIC Issues

```bash
# Disable offloading
sudo ethtool -K <adapter> gso off gro off tso off

# Make persistent
sudo tee /etc/network/if-up.d/disable-offload <<EOF
#!/bin/sh
ethtool -K \$IFACE gso off gro off tso off 2>/dev/null || true
EOF
sudo chmod +x /etc/network/if-up.d/disable-offload
```

### Proxmox Network Card Replacement

```bash
# Check kernel module loaded
dmesg | grep -i ethernet

# List interfaces
ip link show

# Edit /etc/network/interfaces
# Change bridge-ports from old to new interface (e.g., eno1 → enp3s0)

# Restart networking
systemctl restart networking.service
```

## Common Operations

```bash
# Remove node
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node>

# List Helm releases
helm list -a -A

# Uninstall Helm release
helm uninstall <name> -n <namespace>

# Remove stuck namespace
NAMESPACE=stuck-namespace
kubectl proxy &
kubectl get namespace $NAMESPACE -o json | jq '.spec.finalizers=[]' > temp.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json \
  127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
kill %1 && rm temp.json

# Clean logs
sudo journalctl --vacuum-time=30d

# Remove SSH keys
ssh-keygen -f ~/.ssh/known_hosts -R <hostname>

# Install etcdctl
VERSION="v3.5.4"
curl -L https://github.com/etcd-io/etcd/releases/download/${VERSION}/etcd-${VERSION}-linux-arm64.tar.gz \
  -o etcdctl.tar.gz
sudo tar -zxvf etcdctl.tar.gz --strip-components=1 -C /usr/local/bin \
  etcd-${VERSION}-linux-arm64/etcdctl

# Use etcdctl with k3s
alias k3s-etcdctl='sudo etcdctl \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/client.key'

k3s-etcdctl member list
```

## References

- [K3S Hardware Guide](https://rpi4cluster.com/k3s/k3s-hardware/)
- [K3S Production Setup](https://digitalis.io/blog/k3s-lightweight-kubernetes-made-ready-for-production-part-1/)
- [Longhorn Troubleshooting](https://www.ekervhen.xyz/posts/2021-02/troubleshooting-longhorn-and-dns-networking/)

--8<-- "includes/abbreviations.md"
