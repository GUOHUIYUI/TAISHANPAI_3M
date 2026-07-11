# OpenCV Preview 调试记录

本文档记录 `codex/opencv-preview` 阶段的实现和板端验证结果。本阶段只打通摄像头采集到屏幕显示的实时图像通路，不加入人脸检测或识别逻辑。

## 已知基础

- 摄像头最终有效应用节点：`/dev/video42`
- 摄像头输出：ISP mainpath，优先使用 `NV12`
- 已验证最大分辨率：`3840x2160 @ 30 fps`
- 显示链路：DRM/KMS + Xorg/LightDM
- MIPI 屏：`DSI-1`，`480x800 @ 60 Hz`
- 首选显示方式：OpenCV `imshow` 输出到 Xorg `DISPLAY=:0`

## 阶段目标

- 使用 OpenCV 从 `/dev/video42` 连续读取图像。
- 将横向摄像头画面旋转并等比例适配到 `480x800` 屏幕。
- 在预览画面上显示实时 FPS。
- 记录实际采集分辨率、FPS、CPU 占用和主观延迟。
- 明确 adb shell 访问 Xorg 时所需的 Xauthority 配置。

## 首次板端验证

先确认依赖和设备节点：

```bash
python3 --version
python3 -c 'import cv2; print(cv2.__version__)'
v4l2-ctl --all -d /dev/video42
ls -l /dev/video42
```

在有权访问 Xorg 的终端中，从仓库根目录运行：

```bash
DISPLAY=:0 python3 scripts/opencv_preview.py
```

如果默认 `1280x720` 不可用，可按设备实际能力调整：

```bash
DISPLAY=:0 python3 scripts/opencv_preview.py --width 1920 --height 1080
```

按 `q` 或 `Esc` 退出预览。

## adb shell 显示权限

如果出现 `Authorization required` 或 `Can't open display :0`，说明当前 shell 没有 Xauthority，而不是摄像头或屏幕失效。需要先确认 Xorg 所属用户及其授权文件：

```bash
ps -ef | grep '[X]org'
find /run/user /home -name '.Xauthority' -o -name 'Xauthority' 2>/dev/null
```

找到正确文件后再设置，例如：

```bash
export DISPLAY=:0
export XAUTHORITY=/path/to/Xauthority
python3 scripts/opencv_preview.py
```

实际路径和可用运行用户应在本阶段验证后补充到本文档，不在脚本中硬编码。

## 验收记录

| 项目 | 实际结果 |
| --- | --- |
| 设备节点 | `/dev/video42` |
| 请求格式 | `NV12` |
| 实际采集分辨率 | 待验证 |
| 实际预览 FPS | 待验证 |
| CPU 占用 | 待验证 |
| 连续运行时间 | 待验证 |
| Xorg 运行用户/Xauthority | 待验证 |
| 屏幕方向和画面比例 | 待验证 |

## 验收标准

- [ ] OpenCV 能稳定打开 `/dev/video42`。
- [ ] 能连续读取并显示摄像头画面。
- [ ] 画面方向正确且在 `480x800` 屏幕上不拉伸。
- [ ] FPS 可见并完成记录。
- [ ] 连续运行至少 10 分钟，无崩溃或持续累积延迟。
- [ ] adb shell 或板端终端的可靠启动方式已记录。

## 问题记录

| 问题 | 现象 | 原因分析 | 处理方式 |
| --- | --- | --- | --- |
| 待验证 | | | |
