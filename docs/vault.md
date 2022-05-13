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

