# Traefik

Use two traefik controllers for internal and external network.

Issue with only one service `api@internal` with will mess up the WebUI: The web ui will display for both controllers all
services and routes.


https://github.com/traefik/traefik-helm-chart/blob/master/EXAMPLES.md


https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/#kind-tlsoption

https://doc.traefik.io/traefik/routing/routers/

https://doc.traefik.io/traefik/https/acme/#using-letsencrypt-with-kubernetes

