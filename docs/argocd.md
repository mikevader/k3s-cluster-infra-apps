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

**Important**: Remove Applicationset without cascade delete with the following
two options.

### Variant A: Delete over CLI

```bash
$ kubectl delete ApplicationSet (NAME) --cascade=false
```

### Variant B: Delete over GitOps

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-apps
  namespace: argocd-system
spec:
  goTemplate: true
  syncPolicy:
    preserveResourcesOnDeletion: true
```

--> Warning should occur of applicationsets are part of two applications (it's
actually wrong, but apparently applicationsets are identified only by name)

Remove old application set -

Go through the following steps

1. Add app for new applicationset
2. Add preserve resources in old and new applicationset
3. Remove old applicationset
4. Add app to new applicationset one by one


## Switch from Applicationset to App of Apps

To switch from applicationsets to an App of Apps setup we want to delete the
superstructure of applicationsets and applications without removing the
underlying resources like Pods or VolumeClaims. We do this in multiple steps

### Disable cascading

Configure all application sets to preserve their resources. Otherwise the remove
of the application set will trigger a deletion cascade to applications and pods,
etc.

You can do this by defining the following option on the applicationset spec (not
the template!!):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-apps
  namespace: argocd-system
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true
```

### Remove applicationset

Next step is to delete the applicationset. Make sure to remove them from the
initial bootstrap setup otherwise they will be recreated again. This means
remove the applicationset from `cluster-init/root`.

After the sync the applicationset should be removed as well as the applications.
If this is not the case you can manually remove them with the following command:

```bash
$ kubectl delete ApplicationSet <NAME> -n argocd-system --cascade=false
```

### Add new app of apps

This can be done anytime even before you start, if your new app of apps does not
share the name with an existing application.

This is quite straight forward. Add new app of apps to the bootstrap start under
`apps-root-config/bootstrap/values.yaml`.

### Add app to app of apps

First make sure the application you want to add is in the right folder. Don't
move aka remove it from the old folder as the old application still exists and 
would sync your change aka remove the app!

Add your app to the new app of apps for example under
`apps-root-config/applications/cluster-utility-apps.yaml`

**This assumes the application name has not changed!**. You can now remove the
app files from the old folder.

