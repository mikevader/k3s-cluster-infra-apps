# Network Debugging

Troubleshooting guide for network-related issues including connectivity, DNS, ingress, and load balancing.

## Quick Diagnostics

```bash
# Check network pods
kubectl get pods -n kube-system | grep -E "(coredns|flannel)"
kubectl get pods -n traefik
kubectl get pods -n metallb-system

# Check services and endpoints
kubectl get svc,endpoints -A | grep <service>

# Check ingress routes
kubectl get ingressroute -A

# Test DNS
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- nslookup kubernetes.default
```

## DNS Resolution Issues

### Internal DNS Not Working

**Symptoms**:
- Pods can't resolve service names
- `nslookup <service>.<namespace>.svc.cluster.local` fails

**Diagnosis**:

```bash
# Check CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100

# Test DNS from pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- nslookup kubernetes.default.svc.cluster.local
```

**Common Fixes**:

1. **CoreDNS pods down**: Restart them
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

2. **Wrong DNS server in pod**:
   ```bash
   kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- cat /etc/resolv.conf
   # Should show: nameserver 10.43.0.10 (or similar cluster IP)
   ```

### External DNS Not Resolving

**Symptoms**: Can't reach external websites from pods

**Fix**: Check CoreDNS forward configuration:
```bash
kubectl edit configmap coredns -n kube-system
# Ensure: forward . /etc/resolv.conf
```

## Pod-to-Pod Communication Issues

### Pods Can't Communicate Across Nodes

**Diagnosis**:

```bash
# Test from pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- ping <other-pod-ip>

# Check CNI (Flannel)
kubectl get pods -n kube-system -l app=flannel
kubectl logs -n kube-system -l app=flannel --tail=100
```

**Fix**:

```bash
# Restart Flannel
kubectl rollout restart daemonset kube-flannel -n kube-system
```

## Service Access Issues

See [Common Issues - Service Not Accessible](common-issues.md#service-not-accessible)

## MetalLB Issues

### MetalLB Not Assigning IPs

See [Common Issues - MetalLB Not Assigning IPs](common-issues.md#metallb-not-assigning-ips)

### MetalLB Layer 2 ARP Issues

**Symptoms**: External IP assigned but not reachable

**Diagnosis**:

```bash
# Check MetalLB speaker logs
kubectl logs -n metallb-system -l component=speaker --tail=100

# Check ARP table (on a client machine)
arp -a | grep <external-ip>
```

**Fix**: Ensure network allows ARP, verify speaker pods run on all nodes

## Traefik Ingress Issues

### IngressRoute Not Creating Route

**Diagnosis**:

```bash
# Check IngressRoute
kubectl get ingressroute <name> -n <namespace>
kubectl describe ingressroute <name> -n <namespace>

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100 | grep <your-domain>

# Check Traefik dashboard
kubectl port-forward -n traefik svc/traefik 9000:9000
# Open http://localhost:9000/dashboard/
```

**Common Issues**:

1. **Wrong service name or port**:
   ```yaml
   services:
     - name: my-service  # Must match Service name
       port: 80           # Must match Service port
   ```

2. **Missing entryPoint**:
   ```yaml
   entryPoints:
     - websecure  # For HTTPS
   ```

### Can't Access Traefik Dashboard

**Fix**:

```bash
# Port-forward to access
kubectl port-forward -n traefik svc/traefik 9000:9000
# Open http://localhost:9000/dashboard/
```

## Connectivity Testing

### Debug Container

Run a debug container with network tools:

```bash
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- /bin/bash

# Inside container:
# ping <ip>
# nslookup <domain>
# curl <url>
# traceroute <ip>
```

### Test Service Connectivity

From within cluster:

```bash
# Test service by name
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://<service>.<namespace>.svc.cluster.local

# Test service by IP
kubectl get svc <service> -n <namespace>
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://<cluster-ip>:<port>
```

From external:

```bash
# Test LoadBalancer service
curl http://<external-ip>:<port>

# Test Ingress
curl -k https://<domain>
```

## Firewall and Security

### Port Requirements

**k3s requires**:
- 6443: Kubernetes API
- 10250: kubelet
- 2379-2380: etcd (control plane nodes)
- 8472: Flannel VXLAN
- 51820-51821: Flannel Wireguard

**Check firewall** (on nodes):
```bash
ssh <node>
sudo iptables -L -n -v | grep -E "(6443|10250|8472)"
```

## DNS Record Management

For external access:

1. **Verify DNS points to MetalLB IP**:
   ```bash
   nslookup <your-domain>
   # Should resolve to your MetalLB external IP
   ```

2. **Update DNS** (example with CloudFlare):
   - Add A record: `*.example.com` → `<metallb-ip>`
   - Or specific: `app.example.com` → `<metallb-ip>`

3. **Wait for propagation**:
   ```bash
   # Check from multiple locations
   dig <your-domain> @8.8.8.8
   ```

## Performance Issues

### High Network Latency

**Diagnosis**:

```bash
# Test latency between nodes
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- ping <node-ip>

# Check network interface stats
ssh <node>
ifconfig
netstat -i
```

**Causes**:
- Network congestion
- Faulty network hardware
- Wi-Fi (use wired for k8s nodes!)

## Quick Reference

```bash
# Check all network components
kubectl get pods -A | grep -E "(coredns|flannel|traefik|metallb)"

# Test DNS
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- nslookup kubernetes.default

# Test connectivity to service
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://<service>.<namespace>.svc.cluster.local

# Check service endpoints
kubectl get endpoints <service> -n <namespace>

# Traefik dashboard
kubectl port-forward -n traefik svc/traefik 9000:9000

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=200

# MetalLB status
kubectl get svc -A | grep LoadBalancer
kubectl logs -n metallb-system -l component=speaker --tail=100
```

--8<-- "includes/abbreviations.md"
