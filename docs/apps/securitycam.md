


## Config for PI0w Cam

```config
dtparam=audio=on
dtoverlay=vc4-kms-v3d
max_framebuffers=2
camera_auto_detect=1
```

sudo modprobe bcm2835-v4l2

## Stream

motion


libcamerify motion


sudo service motion status



libcamera-vid -n --level 4.2 --denoise cdn_off -t 0 --inline --autofocus-mode continuous  --width 1920 --height 1080 --framerate 30 -o - | cvlc -vvv stream:///dev/stdin :demux=h264 --no-audio --sout '#rtp{sdp=http://:8554/x}'




```bash
$ libcamera-vid -t 0 -n --inline -o - | gst-launch-1.0 fdsrc fd=0 ! h264parse ! rtph264pay ! udpsink host=overseer port=5000
```

with cvlc

```bash
$ libcamera-vid -t 0 --inline -o - | cvlc stream:///dev/stdin --sout '#rtp{sdp=rtsp://:8554/stream1}' :demux=h264
```


