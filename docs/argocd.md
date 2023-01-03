# Argo CD


## ApplicationSet

### Ignore Diffs

``` yaml title="diff in applicationset"
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-init
  namespace: argocd-system
spec:
  generators:
    ...
  template:
    spec:
      project: default
      ignoreDifferences:
        - group: ""
          kind: ConfigMap
          jsonPointers:
            - /data/oidc.config
        - group: ""
          kind: Secret
          jsonPointers:
            - /data/oidc.authentik.clientSecret
      ...
```

## Part Two: OIDC integration

This part should follow after [Vault] and [Authentik] are up and running.

### OIDC Login

First you have to create a provider and application in authentik to get a client id and secret.
Afterwards the oidc credentials can be saved in the Vault and mapped over a `SecretProviderClass`. (Do not forget to
mount the vault volumes for the secret to work [./secrets-csi.md#volumes-in-a-chart])

```yaml
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-argocd
spec:
  provider: vault
  parameters:
    vaultAddress: "http://vault.vault:8200"
    roleName: "argocd-app"
    objects: |
      - objectName: "oidc-id"
        secretPath: "kv-v2/data/framsburg/argocd/oidc"
        secretKey: "client-id"
      - objectName: "oidc-secret"
        secretPath: "kv-v2/data/framsburg/argocd/oidc"
        secretKey: "client-secret"
  secretObjects:
    - data:
        - key: oidc.authentik.clientId
          objectName: oidc-id
        - key: oidc.authentik.clientSecret
          objectName: oidc-secret
      secretName: oidc
      type: Opaque
      labels:
        app.kubernetes.io/part-of: argocd # (1)!
```

1. Without this label the secret reference in the argocd ConfigMap will not work and complain about that the secret key can not be found.




```yaml
argo-cd:
  server:
    ...
    config:
      url: https://argocd.framsburg.ch
      oidc.config: | 
          name: Authentik
          issuer: "https://authentik.framsburg.ch/application/o/argocd/"
          clientID: "c579d3195f85aeccaf1ecce35ef5501e023c2a6a"
          clientSecret: "$oidc:oidc.authentik.clientSecret"
          requestedScopes: ["openid", "profile", "email"]
          logoutURL: "https://authentik.framsburg.ch/if/session-end/argocd/"
    rbacConfig:
      policy.default: role:readonly
      policy.csv: |
          g, 'authentik Admins', role:admin
    volumeMounts:
      - name: 'secrets-store-inline'
        mountPath: '/mnt/secrets-store'
        readOnly: true
    volumes:
      - name: secrets-store-inline
        csi:
          driver: 'secrets-store.csi.k8s.io'
          readOnly: true
          volumeAttributes:
            secretProviderClass: 'vault-argocd'
```

## Rename Applicationset

kubectl delete ApplicationSet (NAME) --cascade=false

on new and old applicationset, with identical names!!!
.spec.syncPolicy.preserveResourcesOnDeletion

--> Warning should occur of applicationsets are part of two applications (it's
actually wrong, but apparently applicationsets are identified only by name)

Remove old application set -

- Add app for new applicationset
- Add preserve resources in old and new applicationset
- Remove old applicationset
- Add app to new applicationset one by one

