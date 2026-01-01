# Common Issues

This page covers the most common issues you'll encounter in day-to-day operations and their quick fixes.

!!! tip "Quick Diagnostic Commands"
    ```bash
    # Check cluster health
    kubectl get nodes
    kubectl get pods -A | grep -v Running
    
    # Check ArgoCD sync status
    kubectl get applications -n argocd-system
    
    # Check certificates
    kubectl get certificate -A
    
    # Check storage
    kubectl get pv,pvc -A
    ```

## Pod Issues

### Pod Stuck in Pending

**Symptoms**: Pod shows `Pending` status for extended period

**Common Causes**:

1. **Insufficient Resources**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Look for: "Insufficient cpu" or "Insufficient memory"
   ```
   
   **Fix**: 
   - Reduce resource requests in deployment
   - Add more nodes
   - Remove resource limits if too restrictive

2. **No Available PV for PVC**
   ```bash
   kubectl describe pvc <pvc-name> -n <namespace>
   # Look for: "waiting for first consumer"
   ```
   
   **Fix**: 
   - Check if Longhorn is healthy: `kubectl get pods -n longhorn-system`
   - Ensure nodes have available storage
   - Check StorageClass exists: `kubectl get sc`

3. **Node Selector Not Matching**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Look for: "didn't match node selector"
   ```
   
   **Fix**: Update deployment to remove or fix node selector

### Pod CrashLoopBackOff

**Symptoms**: Pod continuously restarting

**Diagnosis**:
```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # logs from crashed container

# Check events
kubectl describe pod <pod-name> -n <namespace>
```

**Common Causes**:

1. **Application Error**: Check logs for error messages
2. **Missing ConfigMap/Secret**: 
   ```bash
   kubectl get configmap,secret -n <namespace>
   ```
3. **Liveness Probe Failing**: Adjust probe timing or fix health endpoint
4. **Init Container Failing**: Check init container logs

**Fix**: Depends on root cause, but often:
- Fix application configuration
- Ensure required secrets exist
- Adjust probe configuration

### Pod Stuck in Terminating

**Symptoms**: Pod won't delete, stuck in `Terminating` state

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for finalizers or stuck processes
```

**Quick Fix** (use cautiously):
```bash
# Force delete (last resort)
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force
```

## Storage Issues

### PVC Stuck in Pending

**Symptoms**: PersistentVolumeClaim won't bind

**Diagnosis**:
```bash
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get storageclass
```

**Common Causes**:

1. **No Available Storage**
   - Check Longhorn dashboard for capacity
   - Check node disk space on nodes

2. **StorageClass Not Found**
   ```bash
   kubectl get sc
   ```
   **Fix**: Ensure StorageClass exists and matches PVC

### Longhorn Volume Degraded

**Symptoms**: Longhorn dashboard shows degraded volumes

**Diagnosis**:
```bash
kubectl get volumes.longhorn.io -A
kubectl describe volume <volume-name> -n longhorn-system
```

**Common Causes**:

1. **Node Down**: Volume replica on failed node
2. **Disk Full**: Node disk at capacity
3. **Network Issues**: Replicas can't sync

## Network Issues

### Service Not Accessible

**Symptoms**: Can't reach service via ClusterIP or external IP

**Diagnosis**:
```bash
# Check service exists
kubectl get svc <service-name> -n <namespace>

# Check endpoints (pods backing the service)
kubectl get endpoints <service-name> -n <namespace>
```

**Common Causes**:

1. **No Pods Ready**: Service has no endpoints
2. **Label Mismatch**: Pod labels don't match service selector
3. **Wrong Port**: Service port doesn't match container port

### Ingress Not Working

**Symptoms**: Can't access service via domain name

**Diagnosis**:
```bash
# Check Traefik is running
kubectl get pods -n traefik

# Check IngressRoute
kubectl get ingressroute -n <namespace>
kubectl describe ingressroute <name> -n <namespace>
```

**Common Causes**:

1. **DNS Not Resolving**: Domain doesn't point to MetalLB IP
2. **IngressRoute Misconfigured**: Wrong service name or port
3. **Traefik Not Healthy**: Controller pods crashed

## Certificate Issues

### Certificate Not Issued

**Symptoms**: Certificate stuck in `False` or `Pending` status

**Diagnosis**:
```bash
kubectl get certificate -n <namespace>
kubectl describe certificate <cert-name> -n <namespace>
```

**Common Causes**:

1. **DNS Validation Failing**: ACME DNS-01 challenge can't complete
2. **Rate Limit**: Let's Encrypt rate limits hit
3. **Wrong Issuer**: Certificate references non-existent issuer

## ArgoCD Issues

### Application Out of Sync

**Symptoms**: ArgoCD shows application as "OutOfSync"

**Common Causes**:

1. **Manual Change**: Someone ran `kubectl apply` manually
2. **Ignored Differences**: Resource has expected drift
3. **Git Repo Not Accessible**: ArgoCD can't fetch from Git

## Quick Reference

```bash
# Pod status
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace>

# Storage
kubectl get pv,pvc -A
kubectl get volumes.longhorn.io -A

# Network
kubectl get svc,endpoints -A
kubectl get ingressroute -A

# Certificates
kubectl get certificate -A

# ArgoCD
kubectl get applications -n argocd-system
```
