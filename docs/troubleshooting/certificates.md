# Certificate Issues

Common certificate-related problems and their solutions.

## Quick Diagnostics

```bash
# Check all certificates
kubectl get certificate -A

# Check specific certificate
kubectl describe certificate <cert-name> -n <namespace>

# Check certificate requests
kubectl get certificaterequest -A

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

## Certificate Not Being Issued

### Symptoms
- Certificate shows `Ready: False`
- HTTPS access fails with invalid certificate
- IngressRoute shows certificate pending

### Common Causes & Fixes

#### 1. DNS Validation Failing (ACME DNS-01 Challenge)

**Problem**: Let's Encrypt can't validate domain ownership via DNS

**Diagnosis**:
```bash
kubectl describe challenge -A
# Look for error messages about DNS
```

**Fix**:
- Verify DNS provider credentials are correct (in Secret)
- Check CloudFlare API token has correct permissions
- Verify domain is configured in DNS provider
- Wait for DNS propagation (can take minutes)

```bash
# Verify DNS record exists
dig _acme-challenge.<your-domain> TXT

# Delete and retry
kubectl delete certificate <cert-name> -n <namespace>
# ArgoCD will recreate it
```

#### 2. Let's Encrypt Rate Limiting

**Problem**: Too many certificate requests in short time

**Error Message**: `"rate limit exceeded"`

**Fix**:
- Use Let's Encrypt staging issuer for testing
- Wait 1 hour before retrying
- Consolidate certificates (use wildcard certs)

```yaml
# Use staging issuer for testing
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
spec:
  issuerRef:
    name: letsencrypt-staging  # Change to letsencrypt-prod later
    kind: ClusterIssuer
```

#### 3. Wrong Issuer Configuration

**Problem**: Certificate references non-existent ClusterIssuer

**Fix**:
```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

## Certificate Renewal Issues

### Automatic Renewal Not Working

cert-manager should auto-renew certificates 30 days before expiration.

**Check**:
```bash
# View certificate expiration
kubectl get certificate -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.notAfter)"'

# Check renewal status
kubectl describe certificate <cert-name> -n <namespace>
```

**Fix**:
```bash
# Force renewal by deleting secret
kubectl delete secret <cert-secret> -n <namespace>

# Or delete certificate (ArgoCD will recreate)
kubectl delete certificate <cert-name> -n <namespace>
```

## Certificate Expired

### Symptoms
- Browser shows "Certificate Expired" error
- Services reject HTTPS connections

### Fix
```bash
# Delete certificate and secret
kubectl delete certificate <cert-name> -n <namespace>
kubectl delete secret <cert-secret> -n <namespace>

# cert-manager will reissue
# Watch progress
kubectl get certificate -n <namespace> --watch
```

## Wrong Certificate Being Used

### Symptoms
- HTTPS works but shows wrong domain
- Certificate doesn't match expected domain

### Causes
- Traefik using wrong certificate
- Multiple IngressRoutes for same host
- Missing TLS configuration

### Fix

Check IngressRoute TLS config:
```bash
kubectl get ingressroute <name> -n <namespace> -o yaml
```

Should have:
```yaml
spec:
  tls:
    secretName: <correct-cert-secret>
```

Example correct IngressRoute:
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.example.com`)
      kind: Rule
      services:
        - name: myapp
          port: 80
  tls:
    secretName: myapp-tls  # Must match Certificate secret name
```

## Self-Signed Certificate Appearing

### Symptoms
- Browser shows self-signed certificate warning
- Certificate issuer is "Traefik Default Cert"

### Causes
- cert-manager hasn't issued certificate yet
- Certificate not referenced in IngressRoute
- Traefik using default certificate

### Fix

1. **Verify certificate exists and is ready**:
   ```bash
   kubectl get certificate -n <namespace>
   # Should show Ready: True
   ```

2. **Verify IngressRoute references certificate**:
   ```yaml
   tls:
     secretName: <cert-name>-tls
   ```

3. **Wait for cert issuance** (can take 1-5 minutes)

## Wildcard Certificates

For multiple subdomains:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - example.com  # Also include root domain
```

**Note**: Wildcard certs REQUIRE DNS-01 challenge (can't use HTTP-01)

## Debugging cert-manager

### Check cert-manager Health

```bash
# Check pods
kubectl get pods -n cert-manager

# Check logs
kubectl logs -n cert-manager -l app=cert-manager --tail=200

# Check webhook
kubectl get validatingwebhookconfigurations cert-manager-webhook
```

### Common cert-manager Issues

**Webhook Not Working**:
```bash
# Check webhook pod
kubectl get pods -n cert-manager -l app=webhook

# Restart webhook
kubectl rollout restart deployment cert-manager-webhook -n cert-manager
```

## Quick Reference

```bash
# List all certificates
kubectl get certificate -A

# Check certificate details
kubectl describe certificate <name> -n <namespace>

# Check certificate requests
kubectl get certificaterequest -A

# Check challenges (for ACME)
kubectl get challenge -A

# Force certificate renewal
kubectl delete secret <cert-secret> -n <namespace>

# View certificate expiration
kubectl get certificate -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.notAfter)"'

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --follow
```

--8<-- "includes/abbreviations.md"
