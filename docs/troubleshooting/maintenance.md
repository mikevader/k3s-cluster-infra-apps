# Maintenance Tasks

Regular maintenance tasks to keep your k3s cluster healthy and running smoothly.

## Daily Tasks

### Check Cluster Health

```bash
# Quick cluster health check
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get applications -n argocd-system | grep -v Synced

# Check ArgoCD sync status
kubectl get applications -n argocd-system -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

### Monitor Resource Usage

```bash
# Node resources
kubectl top nodes

# Top memory consumers
kubectl top pods -A --sort-by=memory | head -20

# Top CPU consumers
kubectl top pods -A --sort-by=cpu | head -20
```

## Weekly Tasks

### Review Storage Usage

```bash
# Check PV usage
kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,STATUS:.status.phase

# Check Longhorn UI for disk usage
# Clean up Released PVs
kubectl get pv | grep Released
```

### Check Certificate Expiration

```bash
# List certificates and expiration
kubectl get certificate -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter
```

### Review Failed Backups

```bash
# Check Longhorn backup status via UI
# Check PostgreSQL backup status
kubectl get backup -A
```

## Monthly Tasks

### System Updates

**OS Updates** (via Ansible):

```bash
cd ansible-directory

# Check for updates
ansible all -m shell -a "apt update && apt list --upgradable"

# Apply updates (one node at a time for workers)
ansible-playbook upgrade.yml --limit <node-name>

# Reboot if needed
ansible-playbook reboot.yml --limit <node-name>

# Verify node comes back
kubectl get nodes --watch
```

**k3s Updates**:

```bash
# Check current version
kubectl version --short

# Update via Ansible
ansible-playbook playbooks/06_k3s_secure.yaml
```

### Backup Verification

**Test Longhorn Restore**:

1. Choose non-critical volume
2. Create backup
3. Delete volume
4. Restore from backup
5. Verify data integrity

### Cleanup Tasks

**Clean Up Old Docker Images**:

```bash
# On each node
ssh <node>
sudo crictl rmi --prune
```

**Clean Up Old Snapshots** via Longhorn UI

**Clean Up Completed Jobs**:

```bash
# List old jobs
kubectl get jobs -A --field-selector status.successful=1

# Delete jobs older than 7 days
kubectl delete job -n <namespace> <job-name>
```

### Security Audit

**Check for Security Updates**:

```bash
# Check for CVEs in running images
# Use tool like Trivy

# Update base images via PRs
```

**Review Secrets**:

```bash
# Check for secrets in namespaces
kubectl get secrets -A

# Ensure sensitive secrets are in Vault
```

## Quarterly Tasks

### Major Version Updates

**k3s Major Version Update**:

1. Review release notes
2. Test in dev environment
3. Backup cluster
4. Update control plane nodes one at a time
5. Update worker nodes
6. Verify all applications

### Disaster Recovery Test

**Full Cluster Rebuild Test**:

1. Document current state
2. Destroy test cluster
3. Rebuild from scratch
4. Restore from backups
5. Verify all services
6. Document any issues

### Performance Review

Analyze resource usage trends over 3 months:
- CPU/memory trends
- Storage growth
- Network performance
- Identify bottlenecks

## Maintenance Calendar

### Daily
- [ ] Check cluster health
- [ ] Review critical alerts

### Weekly
- [ ] Review storage usage
- [ ] Check certificate expiration
- [ ] Review failed backups

### Monthly
- [ ] Apply OS updates
- [ ] Backup verification
- [ ] Cleanup tasks
- [ ] Security audit

### Quarterly
- [ ] Major version updates
- [ ] Disaster recovery test
- [ ] Performance review

## Maintenance Windows

### Planning a Maintenance Window

1. **Schedule**: Choose low-traffic time
2. **Notify**: Inform users (if applicable)
3. **Backup**: Ensure recent backups exist
4. **Test**: Test changes in dev first
5. **Execute**: Perform maintenance
6. **Verify**: Check all services

### Drain Node for Maintenance

```bash
# Drain node (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Perform maintenance
# ...

# Uncordon node (allow scheduling)
kubectl uncordon <node-name>

# Verify
kubectl get nodes
```

## Useful Scripts

### Health Check Script

```bash
#!/bin/bash
# cluster-health-check.sh

echo "=== Cluster Health Check ==="
echo ""

echo "Node Status:"
kubectl get nodes
echo ""

echo "Failed Pods:"
kubectl get pods -A | grep -v Running | grep -v Completed
echo ""

echo "ArgoCD Sync Status:"
kubectl get applications -n argocd-system | grep -v Synced
echo ""

echo "Certificate Status:"
kubectl get certificate -A | grep -v "True"
echo ""

echo "Resource Usage:"
kubectl top nodes
```

### Cleanup Script

```bash
#!/bin/bash
# cleanup.sh

echo "Cleaning up old jobs..."
kubectl delete jobs --field-selector status.successful=1 -A

echo "Cleaning up old pods..."
kubectl delete pods --field-selector status.phase=Succeeded -A
kubectl delete pods --field-selector status.phase=Failed -A

echo "Done!"
```

## Quick Reference

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running

# Check resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Check ArgoCD
kubectl get applications -n argocd-system

# Check certificates
kubectl get certificate -A

# Check storage
kubectl get pv,pvc -A

# Drain node
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Uncordon node
kubectl uncordon <node>
```
