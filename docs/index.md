# K3s Homelab GitOps Stack

Welcome to the documentation for my production-ready k3s homelab cluster. This documentation serves three primary purposes (in priority order):

1. **🔧 Troubleshoot and fix issues** - Quick access to solutions when things break
2. **📖 Understand the architecture** - Explain how everything is configured and why
3. **🛠️ Replicate the setup** - Step-by-step guide to build a similar cluster

## Quick Navigation

### 🚨 I Need to Fix Something NOW

Go directly to **[Troubleshooting & Operations](troubleshooting/common-issues.md)** for:

- [Common Issues & Quick Fixes](troubleshooting/common-issues.md)
- [Disaster Recovery Procedures](troubleshooting/disaster-recovery.md)
- [Certificate Problems](troubleshooting/certificates.md)
- [Storage Issues](troubleshooting/storage.md)
- [Network Debugging](troubleshooting/network.md)
- [Application Debugging](troubleshooting/applications.md)

### 📚 I Want to Understand the Setup

Start with **[Getting Started](getting-started/overview.md)**:

- [Overview](getting-started/overview.md) - Purpose, philosophy, technology stack
- [Architecture](getting-started/architecture.md) - Detailed design with diagrams
- [Quick Start](getting-started/quickstart.md) - Step-by-step setup guide

### 🏗️ I Want to Build This

Follow the **[Quick Start Guide](getting-started/quickstart.md)** then:

1. [Hardware Setup](getting-started/architecture.md#hardware)
2. [OS Provisioning](getting-started/quickstart.md#2-os-provisioning-15-minutes-per-node)
3. [Ansible Automation](getting-started/quickstart.md#3-ansible-provisioning-20-30-minutes)
4. [Core Services](getting-started/quickstart.md#4-bootstrap-core-services-1-2-hours)

## About This Setup

This is my personal homelab k3s cluster, running production-ready practices:

- ✅ **Everything as code** - GitOps with ArgoCD, no manual kubectl commands
- ✅ **High availability** - 3-node control plane, distributed storage
- ✅ **Security first** - Valid HTTPS certificates, SSO authentication, secrets management
- ✅ **Network segmentation** - Public/private VLANs with proper firewall rules
- ✅ **Disaster recovery** - Automated backups, documented recovery procedures
- ✅ **Observable** - Comprehensive monitoring, logging, and alerting

Although this is a personal educational project, I maintain production standards because the biggest learnings come from handling real-world complexity and failure scenarios.

## Technology Stack at a Glance

### Hardware
- **Control Plane**: 3x Raspberry Pi 4 (8GB RAM)
- **Workers**: 4x Raspberry Pi 4 (8GB RAM) + 3x x86 servers (64GB RAM)
- **Storage**: HL15 with TrueNAS (40TB capacity)

### Core Infrastructure
- **Orchestration**: k3s (lightweight Kubernetes)
- **GitOps**: ArgoCD
- **Ingress**: Traefik
- **Load Balancer**: MetalLB
- **Storage**: Longhorn (distributed block storage)
- **Certificates**: cert-manager + Let's Encrypt
- **Secrets**: HashiCorp Vault + External Secrets Operator
- **Authentication**: Authentik (SSO/OIDC)
- **Monitoring**: Prometheus + Grafana + Loki
- **Database**: CloudNativePG (PostgreSQL operator)

### Hardware Setup

![Hardware Setup](homelab.drawio)

**Current Configuration:**

- **3x Raspberry Pi 4 (8GB)** - Control plane nodes with Corsair USB sticks
- **4x Raspberry Pi 4 (8GB)** - Worker nodes with USB boot + external NVMe (for Longhorn)
- **Lenovo Thinkcentre M720q** - 64GB RAM, Proxmox, large SSD
- **Lenovo Thinkcentre M75q** - 64GB RAM, Proxmox, large SSD  
- **Minisforum MS-01** - 64GB RAM, Proxmox, 3x large SSDs
- **HL15 with TrueNAS** - Backup target, 6x HDDs (~40TB)

The control plane runs on the first three Raspberry Pis for HA. Workers run on the remaining Raspberry Pis and Proxmox VMs. Some nodes have PoE hats for power. External NVMe drives provide fast storage for Longhorn.

## Documentation Structure

This documentation is organized to prioritize troubleshooting and operations:

```
📖 Documentation
├── 🏠 Getting Started - Orientation and setup
│   ├── Overview - Purpose and technology stack
│   ├── Quick Start - Step-by-step setup guide
│   └── Architecture - Detailed design with diagrams
│
├── 🔧 Troubleshooting & Operations ⭐ PRIORITY
│   ├── Common Issues - Daily problems & fixes
│   ├── Disaster Recovery - Complete recovery procedures
│   ├── Certificates - cert-manager troubleshooting
│   ├── Storage - Longhorn & PVC problems
│   ├── Network - DNS, ingress, connectivity
│   ├── Applications - Pod & app debugging
│   └── Maintenance - Regular maintenance tasks
│
├── 🏗️ Infrastructure Setup - Hardware and OS
├── ⚙️ Cluster Core - Critical services
├── 🗄️ Platform Services - Databases, secrets
├── 📱 Applications - User applications
├── 📝 How-To Guides - Task-focused procedures
└── 📚 Reference - Commands, templates, resources
```

## Key Features of This Documentation

### 🎯 Troubleshooting First
Every page in the troubleshooting section includes:
- Quick diagnostic commands at the top
- Clear symptoms → diagnosis → fix workflow
- Common causes with step-by-step solutions
- Copy-paste ready code examples
- Quick reference commands at the bottom

### 📊 Visual Diagrams
Architecture and workflow diagrams using Mermaid for clear understanding of system design and data flow.

### 💡 Production Practices
Real-world lessons learned from running this cluster, including:
- Design decisions and trade-offs
- Why certain technologies were chosen
- Common pitfalls and how to avoid them
- Disaster recovery procedures tested in practice

### 🔍 Searchable
Full-text search enabled across all documentation. Use the search bar above to quickly find what you need.

## Who Is This For?

Primarily for **myself (Michael)** as a reference when:
- Something breaks and I need to fix it quickly
- I need to remember how I configured something months ago
- I want to replicate or expand the setup

But also for **anyone interested in building** a similar homelab cluster with production-ready practices.

## Inspiration & Credits

This setup is inspired by the excellent work of:

- [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
- [bjw-s/home-ops](https://github.com/bjw-s/home-ops)
- [dirtycajunrice/gitops](https://github.com/dirtycajunrice/gitops)
- [TinyMiniMicro Project](https://www.servethehome.com/introducing-project-tinyminimicro-home-lab-revolution/)

## Get Started

**New to this documentation?** Start here:

1. Read the [Overview](getting-started/overview.md) to understand the purpose and design
2. Check out the [Architecture](getting-started/architecture.md) to see how everything fits together
3. Follow the [Quick Start](getting-started/quickstart.md) if you want to build something similar

**Need to troubleshoot?** Go directly to:

- [Common Issues](troubleshooting/common-issues.md) for daily problems
- [Disaster Recovery](troubleshooting/disaster-recovery.md) for serious failures
- Component-specific guides for [Certificates](troubleshooting/certificates.md), [Storage](troubleshooting/storage.md), [Network](troubleshooting/network.md), or [Applications](troubleshooting/applications.md)

**Looking for specific information?** Use the search bar above or browse the navigation menu.

---

*Last updated: December 2025*
