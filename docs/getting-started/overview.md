# Overview

Welcome to the K3s Homelab GitOps Stack documentation. This documentation serves as both a reference guide and troubleshooting manual for a production-ready, GitOps-managed Kubernetes homelab cluster.

## Purpose of This Documentation

This documentation has three primary goals, in order of priority:

1. **Troubleshooting & Operations** - Quickly find solutions to common problems and execute maintenance tasks
2. **Architecture & Setup** - Understand how the cluster is configured and why certain decisions were made
3. **Replication Guide** - Follow step-by-step instructions to build a similar setup

## Who Is This For?

Primarily for myself (Michael) as a reference when things break or when I need to remember how I set something up months ago. However, it's published on GitHub for anyone interested in building a similar homelab setup.

## Design Philosophy

This homelab follows production-ready practices:

- ✅ **Everything is automated** - No manual kubectl commands
- ✅ **Clear separation** between public and private networks
- ✅ **Secure connections** - All HTTPS with valid Let's Encrypt certificates
- ✅ **Disaster recovery** - Easy backup and restore procedures
- ✅ **High Availability** - Critical components (control plane, networking) run in HA mode

## Quick Navigation

### 🔧 I Need to Fix Something Now

Go to [Troubleshooting & Operations](../troubleshooting/common-issues.md) for immediate help with:

- Certificate issues
- Storage problems
- Network debugging
- Application failures
- Disaster recovery

### 📖 I Want to Understand the Setup

Start with [Architecture](architecture.md) to understand the overall design, then explore:

- [GitOps Workflow](../cluster-core/argocd.md)
- [Networking](../cluster-core/traefik.md)
- [Storage](../cluster-core/longhorn.md)
- [Security](../cluster-core/authentik.md)

### 🛠️ I Want to Build This

Follow the [Quick Start](quickstart.md) guide, then proceed through:

1. [Hardware Setup](../hardware/raspberry-pi.md)
2. [OS Provisioning](../setup/bare-metal.md)
3. [Cluster Bootstrap](../setup/ansible.md)
4. [Core Services Installation](../cluster-core/argocd.md)

## Technology Stack

### Hardware

- **Control Plane**: 3x Raspberry Pi 4 (8GB RAM)
- **Worker Nodes**: 4x Raspberry Pi 4 (8GB RAM) with external NVMe storage
- **Compute Servers**: Lenovo Thinkcentre M720q, M75q, Minisforum MS-01 (all 64GB RAM)
- **Storage**: HL15 with TrueNAS and 6x HDDs

### Core Technologies

- **Container Orchestration**: k3s (lightweight Kubernetes)
- **GitOps**: ArgoCD
- **Ingress**: Traefik
- **Load Balancer**: MetalLB
- **Storage**: Longhorn (distributed block storage)
- **Secrets Management**: HashiCorp Vault + External Secrets Operator
- **Authentication**: Authentik (SSO/OIDC)
- **Certificates**: cert-manager + Let's Encrypt
- **Monitoring**: Prometheus + Grafana
- **Logging**: Loki
- **Databases**: CloudNativePG (PostgreSQL operator)

## Cluster Architecture at a Glance

```mermaid
graph TB
    subgraph "External"
        Internet[Internet]
        DNS[CloudFlare DNS]
    end
    
    subgraph "Edge"
        Router[OPNsense Router]
        MetalLB[MetalLB LoadBalancer]
    end
    
    subgraph "Ingress Layer"
        Traefik[Traefik Ingress]
        CertManager[cert-manager]
    end
    
    subgraph "Security Layer"
        Authentik[Authentik SSO]
        Vault[HashiCorp Vault]
    end
    
    subgraph "Platform Services"
        ArgoCD[ArgoCD]
        Monitoring[Prometheus/Grafana]
        CNPG[PostgreSQL CNPG]
    end
    
    subgraph "Storage"
        Longhorn[Longhorn]
        TrueNAS[TrueNAS]
    end
    
    subgraph "Applications"
        Apps[Media/Network/Monitoring Apps]
    end
    
    Internet --> DNS
    DNS --> Router
    Router --> MetalLB
    MetalLB --> Traefik
    Traefik --> Authentik
    Traefik --> Apps
    Authentik --> Apps
    Vault --> Apps
    CertManager --> Traefik
    ArgoCD --> Platform Services
    ArgoCD --> Apps
    Apps --> Longhorn
    Apps --> CNPG
    Longhorn --> TrueNAS
```

## Getting Help

- Check [Common Issues](../troubleshooting/common-issues.md) first
- Look for your specific component in the [Cluster Core](../cluster-core/argocd.md) section
- Search the documentation using the search bar
- Review [Useful Commands](../reference/commands.md) for quick CLI reference

## Next Steps

New to this setup? Start with the [Quick Start Guide](quickstart.md).

Already familiar? Jump to what you need:

- [Troubleshooting](../troubleshooting/common-issues.md)
- [Deploy New App](../howto/deploy-app.md)
- [Configure Ingress](../howto/configure-ingress.md)
- [Setup Backup](../howto/setup-backup.md)
