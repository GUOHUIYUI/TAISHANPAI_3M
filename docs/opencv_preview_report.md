# OpenCV Preview Validation Report

Generated: 2025-06-26 23:10:37 +0800

## Result

| Item | Value |
| --- | --- |
| Exit status | `0` |
| Camera device | `/dev/video42` |
| Requested format | `NV12` |
| Requested resolution | `1280x720` |
| Actual resolution | `1280x720` |
| Display | `:0` |
| Xauthority | `/var/run/lightdm/root/:0` |
| Physical screen | `480x800` portrait |
| Rotation | `clockwise` |
| Preview FPS (avg/min/max) | `29.98 / 22.28 / 31.94` |
| Process CPU average | `205.24%` |
| RSS average / maximum | `82828 KB / 86528 KB` |
| Measured runtime | `600.04 s` |
| Process samples | `not recorded (collector version issue)` |

## Launch Command

```bash
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 QT_QPA_FONTDIR=/usr/share/fonts /opt/opencv-env/bin/python3 /opt/face-terminal/scripts/opencv_prev/opencv_preview.py --device /dev/video42 --width 1280 --height 720 --rotate clockwise --screen-width 480 --screen-height 800
```

## Automatic Checks

- [x] OpenCV opened the camera and completed the timed preview run.
- [x] Manually confirmed that the image direction is correct.
- [x] Manually confirmed that the preview has no corruption or accumulating delay.

## Manual Follow-up

The 600-second automated run used `contain` in a normal window and established
the stability and performance baseline. The updated `cover + fullscreen` mode
was then checked manually on the 480x800 MIPI panel. It filled the display while
preserving the image aspect ratio, and no corruption was observed.

The generated timestamp is incorrect because the board clock was not
synchronized. This does not affect the monotonic runtime or FPS measurements.

## Program Output

```text
[ WARN:0@0.105] global cap_v4l.cpp:1844 getProperty VIDEOIO(V4L2:/dev/video42): Unable to get camera FPS
QFontDatabase: Cannot find font directory /opt/opencv-env/lib/python3.11/site-packages/cv2/qt/fonts.
Note that Qt no longer ships fonts. Deploy some (from https://dejavu-fonts.github.io/ for example) or switch to fontconfig.
QFontDatabase: Cannot find font directory /opt/opencv-env/lib/python3.11/site-packages/cv2/qt/fonts.
Note that Qt no longer ships fonts. Deploy some (from https://dejavu-fonts.github.io/ for example) or switch to fontconfig.
QFontDatabase: Cannot find font directory /opt/opencv-env/lib/python3.11/site-packages/cv2/qt/fonts.
Note that Qt no longer ships fonts. Deploy some (from https://dejavu-fonts.github.io/ for example) or switch to fontconfig.
QFontDatabase: Cannot find font directory /opt/opencv-env/lib/python3.11/site-packages/cv2/qt/fonts.
Note that Qt no longer ships fonts. Deploy some (from https://dejavu-fonts.github.io/ for example) or switch to fontconfig.
QFontDatabase: Cannot find font directory /opt/opencv-env/lib/python3.11/site-packages/cv2/qt/fonts.
Note that Qt no longer ships fonts. Deploy some (from https://dejavu-fonts.github.io/ for example) or switch to fontconfig.
device=/dev/video42 format=NV12 size=1280x720 reported_fps=-1.00 display=:0
PREVIEW_SUMMARY frames=17992 duration_s=600.04 fps_avg=29.98 fps_min=22.28 fps_max=31.94 size=1280x720 rotate=clockwise screen=480x800 fit=contain fullscreen=0
```
