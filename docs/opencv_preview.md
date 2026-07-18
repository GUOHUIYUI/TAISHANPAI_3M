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
| 实际采集分辨率 | `1280x720` |
| 实际预览 FPS | 平均 `29.98`，最低 `22.28`，最高 `31.94` |
| CPU 占用 | 平均 `205.24%`，约占用两个 CPU 核 |
| 常驻内存 | 平均 `82828 KB`，最大 `86528 KB` |
| 连续运行时间 | `600.04` 秒 |
| Xorg 运行用户/Xauthority | root，`/var/run/lightdm/root/:0` |
| 屏幕方向和画面比例 | 顺时针旋转；`cover + fullscreen` 保持比例铺满 `480x800` 竖屏 |

## 验收标准

- [x] OpenCV 能稳定打开 `/dev/video42`。
- [x] 能连续读取并显示摄像头画面。
- [x] 画面方向正确且在 `480x800` 屏幕上不拉伸。
- [x] FPS 可见并完成记录。
- [x] 连续运行至少 10 分钟，无崩溃、花屏或持续累积延迟。
- [x] adb shell 或板端终端的可靠启动方式已记录。

## 问题记录

| 问题 | 现象 | 原因分析 | 处理方式 |
| --- | --- | --- | --- |
| V4L2 不上报 FPS | OpenCV 输出 `reported_fps=-1.00` | 驱动未通过 `CAP_PROP_FPS` 返回标称值 | 在程序中按实际帧数和单调时钟计算 FPS |
| adb shell 无法访问 Xorg | `Authorization required` | shell 缺少 Xauthority | 设置 `DISPLAY=:0` 和 `XAUTHORITY=/var/run/lightdm/root/:0` |
| 普通窗口未铺满竖屏 | 登录界面、标题栏或少量黑边可见 | 摄像头和屏幕比例不同，且窗口未全屏 | 增加 `cover` 和 `fullscreen` 模式，保持比例并轻微裁剪 |
| Qt 字体目录警告 | 重复输出 `Cannot find font directory` | pip OpenCV 自带 Qt 不包含字体 | 设置系统字体目录；警告不影响预览 |
| 板端报告时间不准确 | 报告日期仍为 2025 年 | 板端系统时钟未同步 | 不影响本阶段性能数据，后续部署阶段配置 RTC/NTP |

## 自动验收报告

`scripts/collect_opencv_preview.sh` 可以启动预览、按秒采样进程 CPU 和常驻内存，并在定时运行结束后生成 Markdown 报告。默认运行 600 秒，报告写入 `/tmp/opencv_preview_report.md`：

```bash
chmod +x scripts/collect_opencv_preview.sh
scripts/collect_opencv_preview.sh
```

首次验证可先运行 60 秒：

```bash
scripts/collect_opencv_preview.sh 60 /tmp/opencv_preview_report.md
```

如果程序部署在其他位置，可通过环境变量覆盖默认路径：

```bash
PREVIEW_SCRIPT=/path/to/opencv_preview.py \
scripts/collect_opencv_preview.sh 600 /tmp/opencv_preview_report.md
```

在 PC 端拉取报告：

```bash
adb pull /tmp/opencv_preview_report.md docs/opencv_preview_report.md
```

脚本能够自动记录实际分辨率、平均/最低/最高 FPS、CPU、RSS、运行时长和启动参数。画面方向、拉伸和主观延迟仍需人工观察，并在报告对应检查项中确认。

验收脚本默认使用 `FIT=cover` 和全屏模式：保持宽高比并轻微裁剪边缘，以铺满 `480x800` 屏幕。如果需要保留摄像头完整视野并接受少量黑边，可执行：

```bash
FIT=contain FULLSCREEN=1 scripts/collect_opencv_preview.sh 60 /tmp/opencv_preview_report.md
```

## 阶段结论

`opencv-preview` 阶段完成。OpenCV 通过 V4L2 成功打开 ISP 主通道 `/dev/video42`，以 `1280x720 NV12` 连续采集图像；画面顺时针旋转后，通过 Xorg `:0` 显示到 `480x800` MIPI 竖屏。最终采用 `cover + fullscreen` 保持比例铺满屏幕。

程序连续运行 `600.04` 秒，平均帧率 `29.98 FPS`，未出现崩溃、卡死或花屏。当前 Python 版本平均占用约两个 CPU 核，可作为后续 C++/Qt 实现和性能优化的基线。
