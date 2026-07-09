Camera bring-up logs collected at Thu Jun 26 11:49:02 PM CST 2025

Suggested next steps:
1. Inspect dmesg_camera.txt and camera_hints.txt for IMX415, CSI, ISP, or V4L2 errors.
2. Inspect media_pipelines_summary.txt first. If the camera moved to another MIPI connector, the active sensor may appear under /dev/media1, /dev/media2, or another media node instead of /dev/media0.
3. Inspect media*_pipeline.txt to confirm the enabled path from imx415 -> dphy -> mipi-csi2 -> rkcif/rkisp.
4. Inspect v4l2_devices.txt and video*_formats.txt before selecting the capture node, resolution, and pixel format.
5. Try one-frame capture with v4l2-ctl after confirming the target node and format.
