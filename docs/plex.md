# PLEX

## Token

Goto [www.plex.tv/claim/](https://www.plex.tv/claim/)

Set the env variable `PLEX_CLAIM` to the generated claim token.


## Remote Access

Add additional entrypoint for plex port (I chose 2000 but can be anything)
Set it in plex

```
traefik:
...
  ports:
    plex:
      port: 2000
      expose: true
      exposedPort: 2000
...
```
