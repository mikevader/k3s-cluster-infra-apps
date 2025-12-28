# Storage Problems

Troubleshooting guide for storage-related issues in Longhorn and other storage systems.

## Quick Diagnostics

```bash
# Check Longhorn health
kubectl get pods -n longhorn-system
kubectl get volumes.longhorn.io -A

# Check PV/PVC status
kubectl get pv,pvc -A

# Check storage classes
kubectl get storageclass

# Check node disk space
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.ephemeral-storage}{"\n"}{end}'
```

## PVC Stuck in Pending

See [Common Issues - PVC Stuck in Pending](common-issues.md#pvc-stuck-in-pending)

## Longhorn Volume Degraded

### Symptoms
- Longhorn dashboard shows volume in "Degraded" state
- Volume has fewer replicas than configured
- Performance degradation

### Diagnosis

```bash
# Get volume status
kubectl get volumes.longhorn.io -A

# Describe specific volume
kubectl describe volume <volume-name> -n longhorn-system

# Check Longhorn UI
# Navigate to: Volume → <volume-name> → Check replica status
```

### Common Causes

#### 1. Node Down or Disconnected

**Fix**:
- Bring node back online
- Or force detach and rebuild replica

```bash
# Check node status
kubectl get nodes

# If node permanently dead, remove it
kubectl delete node <node-name>

# Longhorn will rebuild replica on healthy node
```

#### 2. Disk Full

**Check disk space on nodes**:
```bash
# SSH to each node
ssh <node>
df -h

# Check Longhorn disk usage
ls -lah /var/lib/longhorn/
du -sh /var/lib/longhorn/*
```

**Fix**:
- Clean up old data
- Expand disk
- Add more nodes with storage

#### 3. Network Issues Between Replicas

**Check**:
- Network connectivity between nodes
- Firewall rules
- CNI (Flannel) health

```bash
# Test connectivity between nodes
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- ping <other-node-ip>
```

### Recovery Steps

1. **Identify problematic replica** in Longhorn UI
2. **Remove failed replica** (if node is dead)
3. **Add new replica** - Longhorn automatically creates new replica
4. **Wait for rebuild** - Can take hours for large volumes

## Longhorn Volume Won't Attach

### Symptoms
- Pod stuck in `ContainerCreating`
- Error: "Volume is not attached"

### Diagnosis

```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for volume attachment errors

kubectl describe volume <volume-name> -n longhorn-system
```

### Fixes

#### 1. Volume Stuck on Old Node

```bash
# Check where volume is attached
kubectl get volume <volume-name> -n longhorn-system -o jsonpath='{.status.currentNodeID}'

# If node is down, force detach via Longhorn UI
# Volume → <volume> → Detach → Force detach
```

#### 2. Multiple Pods Trying to Use Same Volume

**Problem**: Two pods on different nodes trying to use `ReadWriteOnce` volume

**Fix**:
```bash
# Find pods using the volume
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="<pvc-name>") | "\(.metadata.namespace)/\(.metadata.name)"'

# Delete one of the pods
kubectl delete pod <pod-name> -n <namespace>
```

## Volume Performance Issues

### Slow I/O

**Causes**:
- Node disk is slow (SD card vs NVMe)
- Network bottleneck between replicas
- Longhorn engine overloaded

**Diagnosis**:

```bash
# Check I/O performance on node
ssh <node>
sudo iostat -x 5

# Check Longhorn engine pods
kubectl get pods -n longhorn-system | grep engine
kubectl top pods -n longhorn-system | grep engine
```

**Fixes**:

1. **Use faster storage**: Migrate to NVMe-backed nodes
2. **Reduce replica count** (trade-off: less redundancy):
   ```yaml
   parameters:
     numberOfReplicas: "2"  # Instead of 3
   ```
3. **Use local-path storage** for non-critical data

## Disk Space Issues

### Node Running Out of Space

**Symptoms**:
- Pods evicted
- "No space left on device" errors
- Longhorn won't create new replicas

**Diagnosis**:

```bash
# Check node disk usage
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.status.allocatable.ephemeralStorage)"'

# SSH to node and check
ssh <node>
df -h
du -sh /var/lib/longhorn/* | sort -h
```

**Fixes**:

1. **Clean up old data**:
   ```bash
   # Remove old container images
   sudo crictl rmi --prune
   
   # Remove old logs
   sudo journalctl --vacuum-time=7d
   ```

2. **Delete old Longhorn backups** via Longhorn UI

3. **Remove unused PVs**:
   ```bash
   kubectl get pv | grep Released
   kubectl delete pv <pv-name>
   ```

### Longhorn Exceeding Disk Reservation

**Error**: "Disk usage exceeded the threshold"

**Fix**:
```bash
# Via Longhorn UI: Node → <node> → Edit → Adjust Storage Reserved

# Or via kubectl
kubectl edit node.longhorn.io <node-name> -n longhorn-system
# Adjust: spec.disks.default.storageReserved
```

## Backup Issues

### Backup Failing

**Symptoms**: Longhorn backup shows failed status

**Diagnosis**:

```bash
# Check Longhorn backup target settings
kubectl get settings.longhorn.io backup-target -n longhorn-system -o yaml

# Check MinIO/S3 connectivity
kubectl run -it --rm aws-cli --image=amazon/aws-cli --restart=Never -- s3 ls s3://<bucket-name>/
```

**Common Causes**:

1. **Invalid backup target URL**: Verify S3/NFS URL
2. **Network connectivity**: Can't reach backup target
3. **Insufficient permissions**: S3 credentials lack permissions

**Fix**:

```bash
# Update backup target
kubectl edit settings.longhorn.io backup-target -n longhorn-system

# Update backup credentials
kubectl edit secret longhorn-backup-target-credential -n longhorn-system
```

### Restore Failing

**Symptoms**: Restore from backup fails

**Diagnosis**:

```bash
kubectl get volumes.longhorn.io -A
# Check volume status

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=200
```

**Fix**: Delete failed restore and retry via Longhorn UI

## Migrating Data Between Volumes

Use a Job to copy data:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: volume-migration
  namespace: <namespace>
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migration
          image: ubuntu:latest
          command: ["/bin/sh", "-c", "cp -r /old/* /new/"]
          volumeMounts:
            - name: old-vol
              mountPath: /old
            - name: new-vol
              mountPath: /new
      volumes:
        - name: old-vol
          persistentVolumeClaim:
            claimName: old-pvc
        - name: new-vol
          persistentVolumeClaim:
            claimName: new-pvc
```

## Quick Reference

```bash
# Longhorn status
kubectl get volumes.longhorn.io -A
kubectl describe volume <volume> -n longhorn-system

# Access Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Check all PVs
kubectl get pv,pvc -A

# Clean up Released PVs
kubectl get pv | grep Released | awk '{print $1}' | xargs kubectl delete pv
```

--8<-- "includes/abbreviations.md"
