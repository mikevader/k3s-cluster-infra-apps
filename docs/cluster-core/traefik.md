# Traefik

Use two traefik controllers for internal and external network.

Issue with only one service `api@internal` with will mess up the WebUI: The web ui will display for both controllers all
services and routes.


## Second ingress controller for external access

As alternative to a second traefik controller, the NGINX ingress controller could be used:

There are two option: ingress nginx controller (community) and nginx ingress controller (from nginx).
I go for the latter as it seems more active at the moment.


## References

- https://github.com/traefik/traefik-helm-chart/blob/master/EXAMPLES.md
- https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/#kind-tlsoption
- https://doc.traefik.io/traefik/routing/routers/
- https://doc.traefik.io/traefik/https/acme/#using-letsencrypt-with-kubernetes
