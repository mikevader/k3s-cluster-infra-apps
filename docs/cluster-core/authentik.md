# Authentik




## RBAC Integration

For RBAC to work, you need to integrate it with an Identity Provider (IDP) or a system that does authentication and
provides user roles. We are obviously going to use Authentik.

For a serious production deployment, you should use an IDP which is not running inside the cluster. This is because if
authentik fails to start up, you will not be able to log in to the cluster. Here we solve this by still keeping the
bootstrap root certificate to be able to log into our cluster.

After saving the admin certificate we are going to create a new OIDC client in Authentik. This will afterwards be used
to configure the cluster to use Authentik as an OIDC provider. And the we use Authentik in kubectl and some apps to
validate everything works.

### Keep a break-glass kubeconfig (do this first)

k3s creates an admin kubeconfig that authenticates with a client certificate (doesn’t depend on OIDC).

```bash title="Inside a k3s server node"
sudo cat /etc/rancher/k3s/k3s.yaml
```

* Save a copy to a secure vault/password manager. (The cluster hashicorp vault is **not** a good place for this)
* This is how you’ll get in if Authentik is down or you misconfigure OIDC.

### Create an OIDC client in Authentik

1. Provider: create an OpenID Connect (OIDC) provider.
    * Example settings:
        * Issuer URL (you don’t set this manually; it’s derived from your Authentik base URL,
          e.g. `https://auth.example.com/application/o/<slug>/`).
        * Enable Authorization Code and/or Device Code (device flow is convenient for headless).
        * Scopes: include at least `openid email profile`. 

          You also need groups to show up in the ID token (see next bullet).

2. Expose “groups” claim (so RBAC can use groups):
    * Add/attach a User/Claim mapping that emits a claim named `groups` with an array of group names (or slugs).
    * Resulting ID token should contain e.g.:
      ```json
      { "email": "alice@example.com", "groups": ["devs","k8s-admins"] }
      ```
    * (Exact steps depend on how you’ve modeled groups in Authentik; the key is: claim name must be `groups`.)

3. Client: create an OAuth2/OIDC Application bound to that provider.
   * Note the Client ID and Client Secret.
   * Allowed redirect URIs are not used by the API server, but are used by your kubectl OIDC plugin (see step 3). If using the kubectl device flow, you typically don’t need to pre-register redirect URIs.


### Configure k3s API server to trust Authentik (OIDC)

The k3s flags can be found in the k3s-server service files (see Ansible playbooks).

```bash title="k3s-servcer.service"
# (merge with your existing config; do NOT duplicate keys)

--kube-apiserver-arg=oidc-issuer-url=https://auth.example.com/application/o/<your-provider-slug>/
--kube-apiserver-arg=oidc-client-id=kubernetes
# If your app uses a client secret, include it:
# --kube-apiserver-arg=oidc-client-secret=<YOUR_CLIENT_SECRET>
--kube-apiserver-arg=oidc-username-claim=email
--kube-apiserver-arg=oidc-groups-claim=groups
# Optional but recommended to avoid collisions with other auth methods:
--kube-apiserver-arg=oidc-username-prefix=oidc:
--kube-apiserver-arg=oidc-groups-prefix=oidc:
# If Authentik uses a private CA or your own TLS, point k3s at the CA bundle:
# --kube-apiserver-arg=oidc-ca-file=/var/lib/rancher/k3s/server/tls/oidc-ca.crt
```

Notes:
* Store the `oidc-client-id` and `oidc-client-secret` in the ansible vault if you use Ansible to deploy k3s.
* `oidc-issuer-url` must exactly match the issuer that signs tokens (including trailing slash if that’s how the
  discovery doc advertises it).
* If Authentik uses a non-public CA, drop the CA chain at oidc-ca-file and ensure k3s can read it.

Restart k3s to apply:
```bash
sudo systemctl restart k3s-server
```
<!--
Verify the API server exposes OIDC flags:
```bash
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -i oidc -n
# (In k3s the apiserver runs as a process, but you can also check with:)
kubectl get --raw /livez
```
-->

### Configure kubectl to use Authentik OIDC

You can use the `kubectl oidc-login` plugin to authenticate with Authentik. Install it as follows:

```bash
# Install the kubectl oidc-login plugin
brew install oidc-login
```

You can test the OIDC parameters by running the following command:

```bash
kubectl oidc-login setup \
  --oidc-issuer-url=ISSUER_URL \
  --oidc-client-id=YOUR_CLIENT_ID \
  --oidc-client-secret=YOUR_CLIENT_SECRET
```

This command will not only validate your OIDC parameters but also provides the `kubectl config set-credentials` command
you need to add oidc to your kubeconfig.

It should output something like this:

```bash"
kubectl config set-credentials oidc \
--exec-api-version=client.authentication.k8s.io/v1 \
--exec-interactive-mode=Never \
--exec-command=kubectl \
--exec-arg=oidc-login \
--exec-arg=get-token \
--exec-arg="--oidc-issuer-url=ISSUER_URL" \
--exec-arg="--oidc-client-id=YOUR_CLIENT_ID" \
--exec-arg="--oidc-client-secret=YOUR_CLIENT_SECRET" \
--exec-arg="--oidc-extra-scope=email,profile,groups"
```

You can now run the following command to check if your kubeconfig is set up correctly:

```bash
kubectl --user=oidc auth whoami
```

You should see your email address or username from Authentik including groups.

If everything works, you can permanently add the oidc user to your kubeconfig:

```bash
kubectl config set-context --current --user=oidc
```

### Test OIDC authentication with kubectl

Bind RBAC to your OIDC groups (or users)
Create a simple test binding. For example, grant view in a dev namespace to group oidc:devs (note the oidc: prefix we configured).

```yaml title="view-to-devs.yaml"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: view-to-devs
  namespace: dev
subjects:
- kind: Group
  name: oidc:devs      # groups-prefix + your groups claim value
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```
Apply it:
```bash
  kubectl apply -f view-to-devs.yaml
```
