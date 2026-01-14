# MetalLB

`kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)" --dry-run -o yaml | kubectl apply -f -`

use ansible vault for secretkey.
