Camera bring-up logs collected at Thu Jun 26 11:11:49 PM CST 2025

Suggested next steps:
1. Inspect dmesg_camera.txt for IMX415, CSI, ISP, or V4L2 errors.
2. Inspect v4l2_devices.txt to choose the correct /dev/video* node.
3. Inspect video*_formats.txt before selecting capture resolution and pixel format.
4. Try one-frame capture with v4l2-ctl after confirming the target node and format.
