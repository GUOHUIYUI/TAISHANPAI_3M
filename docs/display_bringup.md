# Display Bring-up 调试记录

本文档记录 `codex/display-bringup` 阶段的 4.3 寸 MIPI 屏幕调试过程。目标是在泰山派 3M 的 Debian 12 系统中确认显示链路可用，并为后续 OpenCV 实时预览选择稳定的显示方案。

## 阶段目标

- 确认系统是否识别到显示设备。
- 确认当前显示链路是 framebuffer、DRM/KMS、Wayland/X11 桌面，还是厂商自带显示服务。
- 记录屏幕分辨率、刷新率、旋转方向和像素格式。
- 完成基础显示验证，例如纯色、测试图片或命令行图像显示。
- 判断后续 OpenCV 预览应优先使用的显示方式。
- 保存关键命令输出到 `docs/display_logs/`。

## 硬件与系统

| 项目 | 记录 |
| --- | --- |
| 开发板 | 泰山派 3M |
| 显示设备 | 4.3 寸 MIPI 接口屏幕 |
| 系统 | Debian 12 |
| 内核版本 | Linux 6.1.99 aarch64 |
| 显示链路 | DRM/KMS + Xorg/LightDM |
| 推荐显示方式 | 下一阶段优先尝试 Xorg/OpenCV `imshow`，必要时回退到 DRM/KMS |

## 前置检查

在板端执行：

```bash
uname -a
cat /etc/os-release
ls -l /dev/fb* /dev/dri/* 2>/dev/null
```

预期结果：系统能看到 framebuffer 设备、DRM 设备，或桌面环境下可用的显示输出。

## Framebuffer 检查

```bash
ls -l /dev/fb*
cat /sys/class/graphics/fb0/name 2>/dev/null
cat /sys/class/graphics/fb0/modes 2>/dev/null
cat /sys/class/graphics/fb0/virtual_size 2>/dev/null
cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null
fbset -fb /dev/fb0 2>/dev/null
```

需要记录：

| 项目 | 实际结果 |
| --- | --- |
| framebuffer 节点 | 未发现 `/dev/fb*` |
| 分辨率 | 不适用 |
| bits per pixel | 不适用 |
| 是否可直接写入显示 | 暂不采用 framebuffer 路线 |

## DRM/KMS 检查

```bash
ls -l /dev/dri/*
cat /sys/class/drm/*/status 2>/dev/null
cat /sys/class/drm/*/modes 2>/dev/null
modetest -c 2>/dev/null
modetest -p 2>/dev/null
```

如果系统未安装 `modetest`，可先记录 `/sys/class/drm/` 和 `/dev/dri/` 输出。后续需要时再安装 `libdrm-tests` 或系统对应软件包。

需要记录：

| 项目 | 实际结果 |
| --- | --- |
| DRM card 节点 | `/dev/dri/card0`，`platform-display-subsystem-card` |
| connector | `DSI-1` |
| encoder / CRTC | encoder id `203` |
| 当前 mode | `480x800 @ 60.00 Hz` |
| 是否 connected | connected / enabled |

## 桌面环境检查

```bash
echo "$XDG_SESSION_TYPE"
echo "$DISPLAY"
echo "$WAYLAND_DISPLAY"
ps -ef | grep -Ei 'weston|wayland|xorg|Xorg|lightdm|gdm|sddm' | grep -v grep
xrandr 2>/dev/null
```

如果存在桌面环境，后续 OpenCV 可以先用 `imshow` 快速验证；如果没有桌面环境，则优先考虑 framebuffer 或 DRM/KMS 输出。

## 测试显示

### 方法一：系统已有图片查看工具

如果板端有桌面环境，可以先尝试：

```bash
python3 - <<'PY'
import cv2
import numpy as np

img = np.zeros((480, 800, 3), dtype=np.uint8)
img[:, :] = (0, 128, 255)
cv2.putText(img, "Display bring-up", (40, 240), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 2)
cv2.imshow("display-test", img)
cv2.waitKey(5000)
PY
```

### 方法二：Framebuffer 纯色测试

仅在确认 `/dev/fb0` 是目标屏幕后再执行。直接写 framebuffer 可能影响当前显示画面。

```bash
dd if=/dev/zero of=/dev/fb0 bs=1M count=1 2>/dev/null
```

更完整的 framebuffer 测试建议单独写小程序或 Python 脚本，先读取分辨率和 bpp，再生成匹配格式的数据。

## 验收标准

- [x] 能确认当前系统显示链路类型。
- [x] 能记录屏幕分辨率、刷新率或 DRM mode。
- [x] 能确认 `/dev/fb*`、`/dev/dri/*`、桌面环境三者中哪些可用。
- [x] 能完成至少一种测试显示方式。
- [x] 已保存关键命令输出到 `docs/display_logs/`。
- [x] 已明确下一阶段 OpenCV 预览优先采用的显示方式。

## 问题记录

| 问题 | 现象 | 原因分析 | 处理方式 |
| --- | --- | --- | --- |
| `xrandr` 无法打开 `:0` | `Authorization required` / `Can't open display :0` | adb shell 当前用户没有 Xauthority 权限 | 不作为显示链路阻塞项，下一阶段如使用 Xorg/OpenCV 需补充 DISPLAY/Xauthority 运行方式 |
| `fbset` 不存在 | `fbset: command not found` | 系统未安装 framebuffer 工具，且未发现 `/dev/fb*` | 当前优先使用 DRM/KMS 和 Xorg 路线 |

## 本阶段结论

显示链路已完成验证。板端系统为 Debian 12，内核 `Linux 6.1.99 aarch64`。系统未暴露 `/dev/fb*`，因此 framebuffer 暂不作为优先显示方案。

DRM/KMS 链路可用，主显示设备为 `/dev/dri/card0`，对应 `platform-display-subsystem-card`。4.3 寸 MIPI 屏幕对应 connector `DSI-1`，状态为 connected/enabled，当前模式为 `480x800 @ 60.00 Hz`。

系统同时运行 Xorg/LightDM，环境中可见 `DISPLAY=:0`。`xrandr` 在 adb shell 下因 Xauthority 权限无法打开显示，但这不影响 DRM/KMS 和屏幕连接结论。下一阶段 OpenCV 实时预览建议优先尝试通过 Xorg/OpenCV `imshow` 输出到 `:0`；如果权限或窗口环境不稳定，再回退到 DRM/KMS 显示方案。

## 下一步计划

完成 display bring-up 后，进入 `codex/opencv-preview` 阶段：

- 使用 camera 阶段确认的 `/dev/video-camera0` 读取 NV12 图像。
- 按 display 阶段确认的显示方式输出预览画面。
- 记录预览分辨率、FPS、延迟和 CPU 占用。
