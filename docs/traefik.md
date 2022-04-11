# Traefik

Use two traefik controllers for internal and external network.

Issue with only one service `api@internal` with will mess up the WebUI: The web ui will display for both controllers all
services and routes.
