# Application Debugging

Guide for debugging application-specific issues in your k3s cluster.

## Quick Diagnostics

```bash
# Check pod status
kubectl get pods -n <namespace>

# View pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous crash

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Execute shell in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Check resource usage
kubectl top pod <pod-name> -n <namespace>
```

## Pod Startup Issues

### Image Pull Errors

**Symptoms**: `ImagePullBackOff` or `ErrImagePull`

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for: Failed to pull image
```

**Common Causes**:

1. **Wrong image name or tag**: Verify image exists
2. **Private registry auth missing**:
   ```bash
   kubectl create secret docker-registry regcred \
     --docker-server=<registry> \
     --docker-username=<username> \
     --docker-password=<password> \
     -n <namespace>
   ```
3. **Rate limit** (Docker Hub): Authenticate to increase rate limit

### Application Crashes on Startup

See [Common Issues - CrashLoopBackOff](common-issues.md#pod-crashloopbackoff)

**Check exit code**:
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for: Exit Code

# Common exit codes:
# 0   - Success (shouldn't crash)
# 1   - General error
# 137 - SIGKILL (OOMKilled)
# 143 - SIGTERM (terminated)
```

### Configuration Issues

**Check ConfigMaps and Secrets**:

```bash
# Verify ConfigMap exists and has correct data
kubectl get configmap <name> -n <namespace> -o yaml

# Verify Secret exists
kubectl get secret <name> -n <namespace> -o yaml

# Decode secret
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d

# Check environment variables in pod
kubectl exec <pod-name> -n <namespace> -- env
```

## Runtime Issues

### Out of Memory (OOMKilled)

**Symptoms**: Pod restarts frequently, exit code 137

**Diagnosis**:

```bash
# Check events
kubectl describe pod <pod-name> -n <namespace>
# Look for: OOMKilled

# Monitor memory usage
kubectl top pod <pod-name> -n <namespace>
```

**Fix**:

```yaml
# Increase memory limit
resources:
  limits:
    memory: "512Mi"  # Increase this
  requests:
    memory: "256Mi"
```

### CPU Throttling

**Symptoms**: Application slow, high CPU usage

**Diagnosis**:

```bash
# Check CPU usage
kubectl top pod <pod-name> -n <namespace>
```

**Fix**:

```yaml
resources:
  limits:
    cpu: "1000m"  # Increase (1 core = 1000m)
  requests:
    cpu: "500m"
```

### Database Connection Issues

**Symptoms**: Application can't connect to database

**Check**:

1. **Database pod is running**:
   ```bash
   kubectl get pods -n <namespace> -l app=postgres
   ```

2. **Service exists**:
   ```bash
   kubectl get svc <db-service> -n <namespace>
   ```

3. **Test connectivity from app pod**:
   ```bash
   kubectl exec -it <app-pod> -n <namespace> -- nc -zv <db-service> 5432
   ```

4. **Check credentials**: Verify secret exists and app uses it

### Liveness/Readiness Probe Failures

**Symptoms**: Pod keeps restarting, shows not ready

**Diagnosis**:

```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for: Liveness probe failed / Readiness probe failed
```

**Fix**: Adjust probe timing:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60  # Give app time to start
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

## Debugging Techniques

### Interactive Debugging

**Enter shell in running pod**:

```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
# or /bin/bash if available
```

**Run debug container in same pod**:

```bash
kubectl debug <pod-name> -n <namespace> -it --image=nicolaka/netshoot
```

### Log Analysis

**Follow logs**:

```bash
kubectl logs -f <pod-name> -n <namespace>
```

**Multiple containers in pod**:

```bash
# List containers
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'

# View specific container
kubectl logs <pod-name> -c <container-name> -n <namespace>
```

**Logs from all pods in deployment**:

```bash
kubectl logs -n <namespace> -l app=<app-label> --tail=100
```

### Events

**Check recent events**:

```bash
# Namespace-specific
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Watch events
kubectl get events -n <namespace> --watch
```

### Port Forwarding for Testing

**Forward pod port to localhost**:

```bash
kubectl port-forward <pod-name> -n <namespace> 8080:80
# Access at http://localhost:8080
```

## Application-Specific Debugging

### Web Applications

**Test endpoints**:

```bash
# HTTP test
kubectl exec -it <pod-name> -n <namespace> -- curl localhost:8080/health

# With port-forward
kubectl port-forward <pod-name> -n <namespace> 8080:8080
curl http://localhost:8080
```

### Database Applications

**PostgreSQL**:

```bash
# Enter psql
kubectl exec -it <postgres-pod> -n <namespace> -- psql -U <username> -d <database>

# Check connections
kubectl exec -it <postgres-pod> -n <namespace> -- psql -U postgres -c "SELECT * FROM pg_stat_activity;"
```

### Background Jobs/Workers

**Check job status**:

```bash
kubectl get jobs -n <namespace>
kubectl describe job <job-name> -n <namespace>

# Check job pod logs
kubectl logs job/<job-name> -n <namespace>
```

**CronJob debugging**:

```bash
kubectl get cronjobs -n <namespace>
kubectl get jobs -n <namespace> --sort-by=.status.startTime

# Manually trigger CronJob
kubectl create job --from=cronjob/<cronjob-name> test-run -n <namespace>
```

## Performance Debugging

### Slow Application Response

**Check resource usage**:

```bash
kubectl top pod <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

**Check node resources**:

```bash
kubectl top nodes
kubectl describe node <node-name>
```

### Common Patterns

### Init Container Failures

**Symptoms**: Pod stuck in `Init:0/1`

**Check init container logs**:

```bash
kubectl logs <pod-name> -c <init-container> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

## Quick Reference

```bash
# Pod status
kubectl get pods -n <namespace>

# Pod logs
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
kubectl logs -f <pod> -n <namespace>

# Pod description
kubectl describe pod <pod> -n <namespace>

# Execute commands
kubectl exec <pod> -n <namespace> -- <command>
kubectl exec -it <pod> -n <namespace> -- /bin/sh

# Port forwarding
kubectl port-forward <pod> -n <namespace> 8080:80

# Resource usage
kubectl top pod <pod> -n <namespace>

# Events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Debug container
kubectl debug <pod> -n <namespace> -it --image=nicolaka/netshoot
```

--8<-- "includes/abbreviations.md"
