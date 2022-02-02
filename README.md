# k3s-cluster-infra-apps


Order on initialization:

1. cluster itself
2. argocd
3. applicationset
3. applicationset init
    1. reference to self
4. application set platform
    1. metallb
        * Add secret for memberlist
    2. cert-manager
        * Add token for digital ocean
    3. traefik
