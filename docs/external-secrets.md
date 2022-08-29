# External Secrets

After some hickups with the *vault-secrets-webhook* I want to give
[*external secrets*][es] a try. With the webhook I had issues with the env variables
as not all Helm Charts made it so easy to use like the
*kube-monitoring-stack*: Grafana was using some complicated mapping setup which
made it necessary to use Secrets and `secret-refs`. And thats where my issues
started because the *vault-secrets-webhook* did not reliably replace the
placeholders ....

## Install Operator

I created a new Helm Chart App for [external secrets](https://github.com/mikevader/k3s-cluster-infra-apps/tree/master/cluster-platform/external-secrets)

``` yaml title="Chart.yaml"
apiVersion: v2
name: external-secrets
version: 0.0.0
dependencies:
  - name: external-secrets
    version: 0.5.9
    repository: https://charts.external-secrets.io
```

``` yaml title="values.yaml"
external-secrets:
  serviceMonitor:
    enabled: true
```

That will create the very basic setup for External Secrets.

## Setup Store

The next and most important part is the Secret Store. This is the actual
connection to the vault and has the vault coordinates as well as access keys.
To make it an easy setup, this is part of the external secrets application.

``` yaml title="templates/secret-store.yaml"
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "kubernetes"
      version: "v2"
      auth:
        # Authenticate against Vault using a Kubernetes ServiceAccount
        # token stored in a Secret.
        # https://www.vaultproject.io/docs/auth/kubernetes
        kubernetes:
          # Path where the Kubernetes authentication backend is mounted in Vault
          mountPath: "kubernetes"
          # A required field containing the Vault Role to assume.
          role: "externalSecret" # (1)
          # Optional service account field containing the name
          # of a kubernetes ServiceAccount
          serviceAccountRef:
            name: "external-secrets"
```

1.  This role name has to be created in the Vault or configured for the operator
    to create it.

## Use/Create external secret

Last step: create a secret over the external secrets operator. Because the store
is clusterwide available, the only missing part is the `ExternalSecret`
definition.

As an example, the following is the OIDC client id and secret for grafana. I
stored all the authentik OIDC clients in the vault. The external secret
manifest resides in the templates folder of the monitoring stack.

``` yaml title="templates/grafana-oidc-secret.yaml" linenums="1"
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-oidc-secret
  namespace: monitoring-stack
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend # (1)
    kind: ClusterSecretStore
    namespace: external-secrets
  target:
    name: grafana-oidc-secret
    template:
      metadata:
        labels:
          app.kubernetes.io/part-of: monitoring-stack
      data:
        - secretKey: oidc-id
          remoteRef:
            key: secret/data/framsburg/grafana/oidc # (2)
            property: client-id # (3)
        - secretKey: oidc-secret
          remoteRef:
            key: secret/data/framsburg/grafana/oidc
            property: client-secret
```
1.  Name of the configured Secret Store (Make sure the kind is in sync with your
    Secret Store)
2.  Path of the secret in Vault. `secret` is the name of the secret engine,
    `data` is part of the path although not visible in Vault ... some Hashicorp
    Vault shenanigan
3.  Key of the secret

The generated secret will look like this:

``` yaml title=""

```

## Reference

[es]: https://external-secrets.io/ 
