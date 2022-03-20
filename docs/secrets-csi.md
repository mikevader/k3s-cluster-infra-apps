# Secrets with CSI

## Vault Secret Injection with CSI

One way to use credentials from the vault inside pods is with CSI.

* Vault post-start command to enable kubernetes auth-method
* Use Vault with CSI
* Install CSI Driver CRD with Chart
* Define a generic SecretProviderClass template as it is needed for each secret (quite a lot of boilerplate)


In case you need the vault command you can easily log into the shell with:

```bash
$ kubectl exec -it vault-0 -- /bin/sh
```

Create the secrets with:

```bash
$ vault kv put kv-v2/k8s/framsburg/dex client-id="someID" client-secret="someSecret"
```

Enable and activate kubernetes auth method
```bash
$ vault auth enable kubernetes
$ vault write auth/kubernetes/config \
    issuer="https://kubernetes.default.svc.cluster.local" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

Create a policy:
```bash
$ vault policy write dex-app - <<EOF
policy dex-app:
path "kv-v2/data/k8s/framsburg/dex" {
  capabilities = ["read"]
}
EOF
```

Write a role to map a service account with a policy

```bash
$ vault write auth/kubernetes/role/dex-app \
    bound_service_account_names=dex \
    bound_service_account_namespaces=dex \
    policies=dex-app \
    ttl=20m
Success! Data written to: auth/kubernetes/role/dex-app
```


### Secret Class

```yaml
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-dex
spec:
  provider: vault
  parameters:
    vaultAddress: "http://vault.vault:8200"
    roleName: "dex-app"
    objects: |
      - objectName: "oidc-id"
        secretPath: "kv-v2/data/k8s/framsburg/dex"
        secretKey: "client-id"
      - objectName: "oidc-secret"
        secretPath: "kv-v2/data/k8s/framsburg/dex"
        secretKey: "client-secret"
  secretObjects:
    - data:
        - key: id
          objectName: oidc-id
        - key: secret
          objectName: oidc-secret
      secretName: oidc
      type: Opaque
```

### Volumes in a Chart

```yaml
...
  env:
    - name: GITHUB_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: oidc
          key: id
    - name: GITHUB_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: oidc
          key: secret
  envFrom:
    - secretRef:
        name: oidc
...
  volumeMounts:
    - name: 'secrets-store-inline'
      mountPath: '/mnt/secrets-store'
      readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: vault-dex

```
