# Pi Farm @ the river


## First Time

Create credentials file in devops home, named `.vault-credentials` with permission 0600.
This file contains the passphrase for the ansible vault.

### Download roles from the ansible galixy

`ansible-galaxy install -r roles/requirements.yml`

## New servers

To provision new (or existing systems) with the correct users and keys do the following:

* Add system to the hosts file
* Ensure the default user exists in `group_vars/<distribution-name>.yaml`
  Otherwise add a file with the variable `ansible_user_first_run`
* Run ansible with `ansible-playbook add-user-ssh.yaml --limit k3sworker05`

## Deploy the site

`ansible-playbook site.yml`

## Upgrade all servers to latest versions

`ansible-playbook upgrade.yml`


## References

- https://github.com/prometheus/demo-site



# Raspberry Firmware Update

```
$ sudo rpi-eeprom-update
$ sudo apt-get install rpi-eeprom
$ sudo rpi-eeprom-update -a

$ sudo raspi-config
```


TODO:

# setup requirements
- update hostname: `sudo hostnamectl set-hostname k3s...`

- cgroupt in /boot/firmware/cmdline.txt: (on ubuntu /boot/fir)
append `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 swapaccount=1`
# install k3s server


```
$ export K3S_DATASTORE_ENDPOINT='postgres://k3s:12345678@192.168.42.221:5432/k3s?sslmode=disable'

$ curl -sfL https://get.k3s.io | sh -s - server --node-taint CriticalAddonsOnly=true:NoExecute --tls-san 192.168.42.60

--datastore-endpoint postgres://k3s:12345678@192.168.42.221:5432/k3s?sslmode=disable
--tls-san k3s.framsburg.ch
```

```
$ sudo journalctl -u k3s.service
```


get token `sudo cat /var/lib/rancher/k3s/server/node-token`

# add second server

export database
export Token
```
$ export K3S_DATASTORE_ENDPOINT='postgres://k3s:12345678@192.168.42.221:5432/k3s?sslmode=disable'
$ export K3S_TOKEN=K10c72f4e5f9fd862f0a1e91f9d1f91b16b2580621273705ee76528a66ed45f9819::server:5401d36937aa612639acb4d1083c2800

curl -sfL https://get.k3s.io | sh -s - server \
--datastore-endpoint postgres://k3s:12345678@192.168.42.221:5432/k3s?sslmode=disable \
--tls-san k3s.framsburg.ch
```


# install agent

log into agent node
```
export K3S_URL=https://k3s.framsburg.ch:6443
export K3S_TOKEN=K10c72f4e5f9fd862f0a1e91f9d1f91b16b2580621273705ee76528a66ed45f9819::server:5401d36937aa612639acb4d1083c2800
curl -sfL https://get.k3s.io | sh -


```

# MetalLB

`kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)" --dry-run -o yaml | kubectl apply -f -`

use ansible vault for secretkey.


# Dual Stack Ingress

[Ideas from Digitalis](https://digitalis.io/blog/k3s-lightweight-kubernetes-made-ready-for-production-part-1/)

# Install Longhorn

https://www.ekervhen.xyz/posts/2021-02/troubleshooting-longhorn-and-dns-networking/


## New disk
find out device `lsblk -f`
on new devices `wipefs -a /dev/{{ var_disk }}`

```
$ sudo fdisk -l
$ sudo fdisk /dev/sdb

Command: n
Partition number: 1 (default)
First sector: (default)
Last sector: (default)
Command: w

$ sudo fdisk -l
```


```
$ sudo mkfs -t ext4 /dev/sdb1
```


# install cert-manager
log into localhost or commander
```
$ export KUBECONFIG='~/.kube/config-k3s'


# If you have installed the CRDs manually instead of with the `--set installCRDs=true` option added to your Helm install command, you should upgrade your CRD resources before upgrading the Helm chart:

$ kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.1/cert-manager.crds.yaml

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
$ helm repo update

# Install the cert-manager Helm chart
$ helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.5.4 \
  --set installCRDs=true \
  --debug


```


# install rancher

log into localhost or commander
```
$ export KUBECONFIG='~/.kube/config-k3s'
$ helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

$ kubectl create namespace cattle-system

# Update your local Helm chart repository cache
$ helm repo update

$ helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.framsburg.ch \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=rancher  --wait --debug --timeout 10m0s


$ kubectl -n cattle-system rollout status deploy/rancher
```



uninstall cert-manager:
- helm uninstall cert-manager -n cert-manager
- kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/v1.5.4/cert-manager.crds.yaml
- kubectl delete  job.batch/cert-manager-startupapicheck -n cert-manager
- kubectl delete rolebinding.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert -n cert-manager
- kubectl delete role.rbac.authorization.k8s.io/cert-manager-startupapicheck:create-cert -n cert-manager


# argo cd

## prerequisites

Install Go
* [https://golang.org/doc/install]

Install Docker
* [https://docs.docker.com/engine/install/ubuntu/]

Clone and build argo-cd according to [^argocdarm]
* `git clone https://github.com/argoproj/argo-cd.git`
* `cd argo-cd`
* `make armimage`



# Plex
Plex image after [k8s-at-home/plex](https://github.com/k8s-at-home/charts/tree/master/charts/stable/plex)
has an initial issue with recognising itself as plex media server.
The reason is the claim token (https://raw.githubusercontent.com/uglymagoo/plex-claim-server/master/plex-claim-server.sh)

if [ ! -z "${PLEX_CLAIM}" ] && [ -z "${token}" ]; then
  echo "Attempting to obtain server token from claim token"
  loginInfo="$(curl -X POST \
        -H 'X-Plex-Client-Identifier: '${clientId} \
        -H 'X-Plex-Product: Plex Media Server'\
        -H 'X-Plex-Version: 1.1' \
        -H 'X-Plex-Provides: server' \
        -H 'X-Plex-Platform: Linux' \
        -H 'X-Plex-Platform-Version: 1.0' \
        -H 'X-Plex-Device-Name: PlexMediaServer' \
        -H 'X-Plex-Device: Linux' \
        "https://plex.tv/api/claim/exchange?token=${PLEX_CLAIM}")"
  token="$(echo "$loginInfo" | sed -n 's/.*<authentication-token>\(.*\)<\/authentication-token>.*/\1/p')"
  
  if [ "$token" ]; then
    setPref "PlexOnlineToken" "${token}"
    echo "Plex Media Server successfully claimed"
  fi
fi





# Tips & Tricks

## Get rid of node:
kubectl drain <node>
kubectl delete <node>


## list all helm installations:
helm list -a  -A


## uninstall helm installation:
helm uninstall <name> -n <namespace>

## Remove dangling namespaces:
(
NAMESPACE=your-rogue-namespace
kubectl proxy &
kubectl get namespace $NAMESPACE -o json |jq '.spec = {"finalizers":[]}' >temp.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json 127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
)

## Remove old logs:
sudo journalctl --rotate --vacuum-time=5s
sudo journalctl --rotate --vacuum-size=500M

## Remove SSH keys

`sudo ssh-keygen -f "/root/.ssh/known_hosts" -R "k3sworker02"`
`ssh-keygen -f "/home/devops/.ssh/known_hosts" -R "k3sworker02"`


## Replace master node

* Drain master node
* Move master node to end of ansible master group list (if it is at the top, it will be initialized as new cluster)
* 

## Install etcdctl
```
$ VERSION="v3.5.4"
$ curl -L https://github.com/etcd-io/etcd/releases/download/${VERSION}/etcd-${VERSION}-linux-arm64.tar.gz --output etcdctl-linux-arm64.tar.gz
$ sudo tar -zxvf etcdctl-linux-arm64.tar.gz --strip-components=1 -C /usr/local/bin etcd-${VERSION}-linux-arm64/etcdctl
```
```
$ sudo etcdctl --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt --key=/var/lib/rancher/k3s/server/tls/etcd/client.key version
```

## Unix Utils

Find listening ports:
```
$ sudo lsof -i -P -n | grep LISTEN
```

# Next Steps:

* https://greg.jeanmart.me/2020/04/13/deploy-prometheus-and-grafana-to-monitor-a-k/
* https://www.civo.com/learn/monitoring-k3s-with-the-prometheus-operator-and-custom-email-alerts
* https://github.com/atoy3731/k8s-tools-app

# References:

* https://rpi4cluster.com/k3s/k3s-hardware/
* [^argocdarm]: https://github.com/argoproj/argo-cd/pull/3554
* argocd selfdeploy: [https://www.arthurkoziel.com/setting-up-argocd-with-helm/]
