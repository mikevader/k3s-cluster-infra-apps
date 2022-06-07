# Hashicorp Vault

For operating the Vault inside K8S it is a good idea to use the [Banzaicloud Vault-Operator](https://github.com/banzaicloud/bank-vaults).
It automates some the integration and HA tasks.


## Install the operator

Define a new Chart with a dependencies to the
[Vault-Operator Chart](https://artifacthub.io/packages/helm/banzaicloud-stable/vault-operator)
in the app of apps for the vault-operator with the following values:

```yaml
vault-operator:
  crdAnnotations:
      "helm.sh/hook": crd-install
```

## Install Vault

Define a new empty Chart with the following templates inside:

```yaml:rbac.yaml
kind: ServiceAccount
apiVersion: v1
metadata:
  name: vault

---

kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: vault
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "update", "patch"]
---

kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: vault
roleRef:
  kind: Role
  name: vault
  apiGroup: rbac.authorization.k8s.io
subjects:
  - kind: ServiceAccount
    name: vault

---

# This binding allows the deployed Vault instance to authenticate clients
# through Kubernetes ServiceAccounts (if configured so).
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault
    namespace: default
```

## Use secrets

You always have to map the secrets in different ways. You can find a detailed
description on [banzais website](https://banzaicloud.com/docs/bank-vaults/mutating-webhook/)

### As envrionment variable

Pod should have the following annotations:

```yaml
annotations:
  vault.security.banzaicloud.io/vault-addr: "http://vault.vault.svc:8200"
  vault.security.banzaicloud.io/vault-path: "kubernetes"
  vault.security.banzaicloud.io/vault-role: "test"
  vault.security.banzaicloud.io/vault-skip-verify: "true"
```

You should adapt the role to the corresponding role you want to use.
You can then use secrets in environment variables like this:

```yaml
env:
  - name: GITHUB_CLIENT_ID
    value: vault:secret/data/framsburg/test#github_token
```

### As secret

The approach with secrets looks quite similar. The main difference is, that you
have to provide the path to the secret **base64** encoded.

```bash
$ echo -n vault:secret/data/framsburg/test#github_token | base64
dmF1bHQ6c2VjcmV0L2RhdGEvZnJhbXNidXJnL3Rlc3QjZ2l0aHViX3Rva2Vu
```

Then prepare the secret accodringly:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: some-secret
data:
  GITHUB_CLIENT_ID: dmF1bHQ6c2VjcmV0L2RhdGEvZnJhbXNidXJnL3Rlc3QjZ2l0aHViX3Rva2Vu
type: Opaque
```

### Inline

Instead of environment variables or secrets you can use the vault key reference
anywhere in resources and the webhook will replace it with the secret.

