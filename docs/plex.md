# PLEX

## Token

Goto [www.plex.tv/claim/](https://www.plex.tv/claim/)

Set the env variable `PLEX_CLAIM` to the generated claim token.


## Remote Access

Either add an additional entrypoint or use the custom port 443 for the remote port.

It is important to adapt the custom hostname to the correct URL including protocol (`https://`)
and Path Prefix like `/web`.


## ReadWriteMany for storage

To upload a lot of files it might be helpful to use `ReadWriteMany` volumes. This way the can be exposed
for upload over samba, nfs or other setups.


## Upload

```
kubectl cp <some-namespace>/<some-pod>:/tmp/foo /tmp/bar
```

## Change video containers with ffmpeg

```
ffmpeg -i example.mkv -c copy -tag:v hvc1 example.mp4
```


```
for f in *.mkv; do ffmpeg -i "$f" -c copy -tag:v hvc1 "${f%.mkv}.mp4"; rm "$f"; done
```

## Proxy rewrite

To remove the annoying `/web` I follow some existing guides like [^1].
The main challenge is to do this correctly with traefik and inside K8S.

What I did was basically translate the Apache redirect to a traefik middleware
which is doing basically the same thing.

```xaml title='apache config'
<VirtualHost *:80>

  RewriteEngine on
  RewriteCond %{REQUEST_URI} !^/web
  RewriteCond %{HTTP:X-Plex-Device} ^$
  RewriteRule ^/$ /web/$1 [R,L]
</VirtualHost>
```

Because Traefik has no conditions we solve it with two different routes. But this
is only possible with the propriatary IngressRoute.

```yaml title='traefik ingressroute'
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: plex3
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`plex3.framsburg.ch`) && (PathPrefix(`/web`) || HeadersRegexp('X-Plex-Device', '.*'))
      kind: Rule
      priority: 100
      services:
        - name: plex
          port: http
      middlewares:
        - name: svc-plex-headers
          namespace: plex
    - match: Host(`plex3.framsburg.ch`)
      kind: Rule
      priority: 50
      services:
        - name: plex
          port: http
      middlewares:
        - name: svc-plex-headers
          namespace: plex
        - name: web-redirect
          namespace: plex
  tls:
    certResolver: letsencrypt
    domains:
      - main: plex3.framsburg.ch
```


With the following Middleware to redirect the path:

```yaml title='traefik middleware'
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: web-redirect
  namespace: plex
spec:
  redirectRegex:
    regex: "^/$"
    replacement: "/web/"
```


## Usenet instead of Torrent

https://trash-guides.info/Downloaders/SABnzbd/Basic-Setup/
https://blog.harveydelaney.com/switching-from-torrents-to-usenet-the-why-and-how/

[^1]: https://matt.coneybeare.me/how-to-map-plex-media-server-to-your-home-domain/
