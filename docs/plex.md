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
