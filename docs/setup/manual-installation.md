# Manual K3S Installation

Manual installation without Ansible. For production, use [Ansible provisioning](node-provisioning.md) instead.

## Prerequisites

```bash
# Enable cgroups (required for Kubernetes)
sudo nano /boot/firmware/cmdline.txt
# Append: cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 swapaccount=1
sudo reboot
```

## Control Plane Installation

### Method 1: Embedded etcd (Recommended)

**First control plane node:**
```bash
export K3S_TOKEN="SecureRandomTokenHere"

curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san k3s.example.com \
  --node-taint CriticalAddonsOnly=true:NoExecute

# Get token for other nodes
sudo cat /var/lib/rancher/k3s/server/node-token
```

**Additional control plane nodes:**
```bash
export K3S_TOKEN="<token-from-first-node>"
export K3S_URL="https://k3s-server01:6443"

curl -sfL https://get.k3s.io | sh -s - server \
  --server ${K3S_URL} \
  --tls-san k3s.example.com \
  --node-taint CriticalAddonsOnly=true:NoExecute
```

### Method 2: External PostgreSQL

```sql
CREATE DATABASE k3s;
CREATE USER k3s WITH PASSWORD 'securepassword';
GRANT ALL PRIVILEGES ON DATABASE k3s TO k3s;
```

```bash
export K3S_DATASTORE_ENDPOINT='postgres://k3s:securepassword@192.168.1.221:5432/k3s?sslmode=disable'

curl -sfL https://get.k3s.io | sh -s - server \
  --datastore-endpoint "${K3S_DATASTORE_ENDPOINT}" \
  --tls-san k3s.example.com \
  --node-taint CriticalAddonsOnly=true:NoExecute
```

## Worker Installation

```bash
export K3S_URL="https://k3s.example.com:6443"
export K3S_TOKEN="<token-from-control-plane>"

curl -sfL https://get.k3s.io | sh -
```

## kubeconfig Setup

**On control plane:**
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

**On remote machine:**
```bash
scp user@k3s-server01:/etc/rancher/k3s/k3s.yaml ~/.kube/config-k3s
sed -i 's/127.0.0.1/k3s.example.com/g' ~/.kube/config-k3s
export KUBECONFIG=~/.kube/config-k3s
```

## Install Core Components

### MetalLB

```bash
# Create secret
kubectl create secret generic -n metallb-system memberlist \
  --from-literal=secretkey="$(openssl rand -base64 128)" \
  --dry-run=client -o yaml | kubectl apply -f -

# Install
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --create-namespace

# Configure IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: public-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - public-pool
EOF
```

### cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --version v1.14.0 --set installCRDs=true

# Create Let's Encrypt issuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
```

**Uninstall:**
```bash
helm uninstall cert-manager -n cert-manager
kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml
kubectl delete namespace cert-manager
```

### Rancher (Optional)

```bash
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

helm install rancher rancher-latest/rancher \
  -n cattle-system --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=your-email@example.com \
  --wait --timeout 10m0s
```

## Troubleshooting

```bash
# Check service status
sudo systemctl status k3s         # Control plane
sudo systemctl status k3s-agent   # Worker
sudo journalctl -u k3s.service -f

# Check etcd health
sudo k3s etcd-snapshot ls

# Reset cluster
sudo /usr/local/bin/k3s-uninstall.sh        # Control plane
sudo /usr/local/bin/k3s-agent-uninstall.sh  # Worker
sudo rm -rf /var/lib/rancher/k3s /etc/rancher/k3s
```

## References

- [K3S Documentation](https://docs.k3s.io/)
- [K3S HA Setup](https://docs.k3s.io/datastore/ha-embedded)
- [MetalLB Docs](https://metallb.universe.tf/)

--8<-- "includes/abbreviations.md"
