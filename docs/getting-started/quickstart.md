# Quick Start

This guide will help you get started quickly with understanding or building your own k3s homelab cluster.

## Prerequisites

Before you begin, ensure you have:

- **Hardware**: Multiple nodes (Raspberry Pis or x86 servers)
- **Network**: Static IPs configured for all nodes
- **Storage**: External storage for Longhorn (NVMe/SSD recommended)
- **Domain**: A domain name with DNS control (e.g., CloudFlare)
- **Tools**: 
  - `kubectl` installed on your workstation
  - `helm` CLI
  - `ansible` for provisioning
  - SSH access to all nodes

## High-Level Steps

### 1. Hardware Setup (30-60 minutes)

1. Assemble your hardware (Raspberry Pis or servers)
2. Configure network (static IPs, VLANs if needed)
3. Attach external storage for Longhorn
4. Document your hardware inventory

📖 **Detailed Guide**: [Raspberry Pi Setup](../hardware/raspberry-pi.md)

### 2. OS Provisioning (15 minutes per node)

1. Flash Ubuntu Server to SD cards/USBs
2. Configure initial user and SSH
3. Run initial system updates
4. Configure firmware (for Raspberry Pis)

📖 **Detailed Guide**: [Bare Metal Setup](../setup/bare-metal.md)

### 3. Ansible Provisioning (20-30 minutes)

1. Configure Ansible inventory
2. Run user and SSH key provisioning playbook
3. Run k3s installation playbook
4. Verify cluster is up

📖 **Detailed Guide**: [Ansible Automation](../setup/ansible.md)

```bash
# Quick commands
ansible-playbook add-user-ssh.yaml
ansible-playbook playbooks/06_k3s_secure.yaml
kubectl get nodes
```

### 4. Bootstrap Core Services (1-2 hours)

Install critical infrastructure in order:

1. **MetalLB** - Load balancer for bare metal
2. **Traefik** - Ingress controller
3. **cert-manager** - Certificate management
4. **Longhorn** - Distributed storage
5. **ArgoCD** - GitOps continuous delivery

📖 **Detailed Guides**: 
- [MetalLB](../cluster-core/metallb.md)
- [Traefik](../cluster-core/traefik.md)
- [cert-manager](../cluster-core/cert-manager.md)
- [Longhorn](../cluster-core/longhorn.md)
- [ArgoCD](../cluster-core/argocd.md)

### 5. Setup Security & Secrets (1-2 hours)

1. **HashiCorp Vault** - Secrets storage
2. **Authentik** - SSO/OIDC provider
3. **External Secrets Operator** - Sync secrets from Vault
4. **Secrets Store CSI** - Mount secrets as files

📖 **Detailed Guides**: 
- [Vault](../cluster-core/vault.md)
- [Authentik](../cluster-core/authentik.md)

### 6. Deploy Platform Services (30-60 minutes)

1. **Monitoring Stack** - Prometheus + Grafana + Loki
2. **PostgreSQL** - CloudNativePG operator
3. **Backup configuration** - Longhorn backups to MinIO/TrueNAS

📖 **Detailed Guides**: 
- [Monitoring](../cluster-core/monitoring.md)
- [PostgreSQL](../platform/postgres-cnpg.md)

### 7. Deploy Applications

Now you can deploy your applications using ArgoCD!

## Verification Checklist

After setup, verify everything is working:

- [ ] All nodes are in `Ready` state: `kubectl get nodes`
- [ ] MetalLB has assigned external IPs: `kubectl get svc -A | grep LoadBalancer`
- [ ] Traefik dashboard is accessible
- [ ] cert-manager has issued certificates: `kubectl get certificate -A`
- [ ] Longhorn dashboard shows all volumes healthy
- [ ] ArgoCD is syncing applications
- [ ] Vault is initialized and unsealed
- [ ] Authentik is accessible and configured
- [ ] Prometheus/Grafana showing metrics
- [ ] Test application is deployed and accessible via HTTPS

## Common First-Time Issues

### Pods Stuck in Pending

**Cause**: Usually storage or resource constraints

**Fix**: 
```bash
kubectl describe pod <pod-name> -n <namespace>
# Check events for specific error
```

📖 See: [Storage Problems](../troubleshooting/storage.md)

### Certificate Not Issued

**Cause**: DNS propagation or Let's Encrypt rate limits

**Fix**:
```bash
kubectl describe certificate <cert-name> -n <namespace>
kubectl describe certificaterequest -n <namespace>
```

📖 See: [Certificate Issues](../troubleshooting/certificates.md)

### Can't Access Services

**Cause**: MetalLB not configured, Traefik not routing, or firewall

**Fix**:
```bash
kubectl get svc -n traefik
kubectl get ingressroute -A
```

📖 See: [Network Debugging](../troubleshooting/network.md)

## Time Estimates

- **Minimal working cluster**: 4-6 hours
- **Production-ready with monitoring**: 8-12 hours
- **Full setup with all applications**: 2-3 days

These are estimates for first-time setup. With experience and automation, you can rebuild in a few hours.

## GitOps Repository Structure

The repository is organized as follows:

```
k3s-cluster-infra-apps/
├── cluster-init-apps/       # Bootstrap apps (MetalLB, cert-manager)
├── cluster-critical-apps/   # Core infrastructure (Traefik, Longhorn)
├── cluster-platform-apps/   # Platform services (databases, monitoring)
├── cluster-apps-apps/       # User applications
├── apps-root-config/        # ArgoCD ApplicationSets
└── docs/                    # This documentation
```

Each app follows this structure:
```
app-name/
├── Chart.yaml              # Helm chart definition
├── values.yaml             # Configuration values
└── templates/              # Kubernetes manifests
```

## Next Steps

1. **Understand the Architecture**: [Architecture Overview](architecture.md)
2. **Start Building**: [Hardware Setup](../hardware/raspberry-pi.md)
3. **Learn GitOps Workflow**: [ArgoCD](../cluster-core/argocd.md)

## Getting Help

If you run into issues:

1. Check [Troubleshooting & Operations](../troubleshooting/common-issues.md)
2. Search this documentation
3. Check the GitHub repository issues

--8<-- "includes/abbreviations.md"
