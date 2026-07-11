# Display Bring-up 阶段 Linux 与显示基础知识

本文档总结 `display-bringup` 阶段涉及的 Linux 显示子系统知识、MIPI DSI 屏幕链路基础，以及 `scripts/collect_display_info.sh` 脚本的编写思路。目标是把本阶段不只是“屏幕能亮”，而是能讲清楚 Linux 是如何识别显示硬件、暴露 DRM 设备、组织 connector/mode，并让应用层选择合适的显示路径。

## 1. 本阶段验证了什么

本阶段不是实现实时预览程序，而是确认泰山派 3M 上的 4.3 寸 MIPI 屏幕已经被系统识别，并明确后续 OpenCV 预览应该优先走哪条显示链路。

最终确认结果：

- 系统为 Debian 12，内核版本为 `Linux 6.1.99 aarch64`。
- 未发现 `/dev/fb*`，因此 framebuffer 暂不作为第一优先显示方案。
- DRM/KMS 显示链路存在，主显示设备为 `/dev/dri/card0`。
- `/dev/dri/card0` 对应 `platform-display-subsystem-card`。
- MIPI 屏幕对应 DRM connector `DSI-1`。
- `DSI-1` 状态为 `connected` / `enabled`。
- 当前屏幕模式为 `480x800 @ 60.00 Hz`。
- 系统运行 Xorg/LightDM，环境中可见 `DISPLAY=:0`。

这些结果说明：显示屏硬件、DRM/KMS 驱动、connector 状态和显示模式已经形成闭环。下一阶段可以基于此做 OpenCV 实时预览验证。

## 2. Linux 显示链路的几个层次

Linux 显示并不是只有一种方式。嵌入式板子上常见的显示路径包括：

| 层次 | 典型接口 | 作用 |
| --- | --- | --- |
| Framebuffer | `/dev/fb0` | 早期或简单显示接口，应用可直接写显存。 |
| DRM/KMS | `/dev/dri/card*` | 现代 Linux 图形显示核心，负责显示控制、connector、CRTC、plane、mode setting。 |
| X11/Wayland | `DISPLAY=:0` / `WAYLAND_DISPLAY` | 用户态图形会话，OpenCV `imshow`、Qt、GTK 等通常依赖它。 |
| 应用层库 | OpenCV、Qt、SDL、GStreamer | 使用底层显示系统输出窗口或画面。 |

本项目板端实际情况是：

```text
MIPI DSI 屏
  -> Rockchip display subsystem
  -> DRM/KMS: /dev/dri/card0
  -> connector: DSI-1
  -> Xorg/LightDM: DISPLAY=:0
  -> 后续 OpenCV / Qt / DRM 程序
```

所以 display-bringup 的重点不是只看屏幕亮没亮，而是要确认 Linux 里哪个设备节点、哪个 connector、哪个 mode 才是后续应用应使用的显示出口。

## 3. Framebuffer 为什么不是本阶段优先路线

Framebuffer 通常表现为：

```text
/dev/fb0
/sys/class/graphics/fb0
```

如果存在 `/dev/fb0`，应用可以尝试直接写像素数据到 framebuffer。但本次采集结果中：

```text
framebuffer_sysfs.txt:
## /sys/class/graphics/fb*
```

并且 `display_nodes.txt` 没有列出 `/dev/fb*`。同时：

```text
fbset: command not found
```

这说明当前系统没有暴露传统 framebuffer 节点，或者没有安装 framebuffer 调试工具。因此本阶段不把 framebuffer 作为主路线。

这不是问题。现代 Rockchip Linux 镜像更常见的路线是 DRM/KMS，再由 Xorg/Wayland 或图形库在其上显示。

## 4. DRM/KMS 基础

DRM 是 Direct Rendering Manager，KMS 是 Kernel Mode Setting。它们是现代 Linux 显示栈中内核侧的核心部分。

本阶段看到的关键节点：

```text
/dev/dri/card0
/dev/dri/renderD128
/dev/dri/card1
/dev/dri/renderD129
```

其中：

- `/dev/dri/card0`：显示主设备，路径指向 `platform-display-subsystem-card`。
- `/dev/dri/card1`：NPU 相关 card，不是显示主卡。
- `/dev/dri/renderD*`：render node，更多用于 GPU/NPU/render 访问，不直接等价于屏幕输出。

`/dev/dri/by-path` 里能看到：

```text
platform-display-subsystem-card -> ../card0
platform-27700000.npu-card -> ../card1
```

这说明要调屏幕，优先关注 `card0`，不要误把 NPU 的 `card1` 当成显示设备。

## 5. connector、encoder、CRTC、plane 是什么

DRM/KMS 中常见几个对象：

| 对象 | 作用 |
| --- | --- |
| connector | 物理或逻辑显示接口，例如 HDMI、DP、DSI。 |
| encoder | 把 CRTC 输出编码成某种接口信号。 |
| CRTC | 扫描输出控制器，决定时序和模式。 |
| plane | 显示图层，可承载 framebuffer、overlay、cursor 等。 |
| mode | 分辨率、刷新率、同步时序等显示模式。 |

本阶段 `modetest -c` 中关键结果：

```text
204 203 connected DSI-1
  #0 480x800 60.00 ... type: preferred, driver
```

含义：

- connector id 是 `204`。
- encoder id 是 `203`。
- connector 名称是 `DSI-1`。
- 状态是 `connected`。
- 支持一个模式：`480x800 @ 60.00 Hz`。
- 该模式是 preferred/driver 模式。

这就是我们判断 MIPI 屏幕已被正确识别的核心证据。

## 6. MIPI DSI 和 DSI-1

MIPI DSI 是嵌入式屏幕常见接口。和摄像头的 MIPI CSI 不同：

| 接口 | 方向 | 典型用途 |
| --- | --- | --- |
| MIPI CSI | sensor -> SoC | 摄像头输入 |
| MIPI DSI | SoC -> panel | 屏幕输出 |

本阶段的屏幕在 Linux DRM 中表现为：

```text
/sys/class/drm/card0-DSI-1
```

状态文件显示：

```text
status=connected
enabled=enabled
modes=480x800
```

这说明内核已经识别到 MIPI DSI panel，且该 connector 已启用。

## 7. Xorg/LightDM 在本阶段的意义

除了 DRM/KMS，本阶段还确认系统运行了 Xorg/LightDM：

```text
/usr/sbin/lightdm
/usr/lib/xorg/Xorg :0
lightdm-gtk-greeter
```

环境中也有：

```text
DISPLAY=:0
```

这意味着系统上有 X11 显示会话。对下一阶段很有价值，因为 OpenCV 的：

```python
cv2.imshow(...)
```

通常需要 X11 或其他窗口系统。如果 Xorg 可用，下一阶段可以先用 OpenCV `imshow` 快速验证摄像头预览，而不必一开始就写 DRM/KMS 原生显示代码。

但这次 `xrandr` 输出：

```text
Authorization required, but no authorization protocol specified
Can't open display :0
```

这不是屏幕不可用，而是 adb shell 当前用户没有访问 X server 的授权。后续如果要从 adb shell 运行 OpenCV 窗口程序，需要处理：

- `DISPLAY=:0`
- `XAUTHORITY` 或 `xhost`
- 运行用户是否和 Xorg 会话用户一致

## 8. 为什么不能只看屏幕亮了

嵌入式显示调试不能只凭肉眼判断。更可靠的判断方式是多证据交叉：

```text
/dev/dri/card0 存在
+ /sys/class/drm/card0-DSI-1 connected/enabled
+ modetest 能列出 DSI-1 和 480x800@60 mode
+ Xorg/LightDM 正在运行
+ 实际屏幕验证完成
= display bring-up 成功
```

如果只说“屏幕亮了”，面试时很难回答底层链路。现在可以讲清楚应用层显示背后依赖的是 DRM/KMS 的 `card0` 和 `DSI-1`。

## 9. `collect_display_info.sh` 脚本为什么这样写

本阶段脚本是：

```bash
scripts/collect_display_info.sh
```

它的目的不是修改系统，而是一次性采集显示链路排查所需的信息。

### 9.1 输出目录可配置

```bash
OUT_DIR="${1:-docs/display_logs/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"
```

和 camera 阶段脚本一样：

- 传入参数时，使用指定目录。
- 不传参数时，使用时间戳目录。
- 输出都集中保存，便于提交到 `docs/display_logs/`。

### 9.2 为什么使用 `run_cmd` 和 `run_shell`

脚本里把命令包装成函数：

```bash
run_cmd name command args...
run_shell name 'shell script'
```

好处：

- 每个检查项单独保存为一个 `.txt`。
- 标准输出和错误输出都保存。
- 单个命令失败不会中断后续采集。

这对板端调试很重要，因为 `fbset`、`xrandr`、`modetest` 不一定都安装或可用。

### 9.3 为什么采集 `/dev/fb*` 和 `/dev/dri/*`

```bash
ls -l /dev/fb* /dev/dri/* 2>/dev/null
```

这一步用于判断系统暴露了哪些显示设备入口：

- 有 `/dev/fb0`：可以考虑 framebuffer。
- 有 `/dev/dri/card0`：可以考虑 DRM/KMS。
- 有 render node：说明存在 render 设备，但不等于屏幕输出。

本阶段正是通过这一步确认了没有 `/dev/fb*`，但存在 `/dev/dri/card0`。

### 9.4 为什么读取 `/sys/class/drm`

```bash
for p in /sys/class/drm/*; do
    ...
done
```

`/sys/class/drm` 里能直接看到 connector 状态，例如：

```text
card0-DSI-1/status
card0-DSI-1/modes
card0-DSI-1/enabled
```

这比只看 `/dev/dri/card0` 更具体。`card0` 只说明有显示设备，`card0-DSI-1` 才说明 MIPI DSI 屏是否连接、启用、支持什么分辨率。

### 9.5 为什么采集 `modetest`

```bash
modetest -c
modetest -p
```

`modetest` 来自 libdrm 工具集，能列出 DRM connector、plane、CRTC、mode 等信息。

本阶段 `modetest -c` 给出关键结论：

```text
DSI-1 connected
480x800 60.00
```

`modetest -p` 输出很长，主要用于后续如果需要走 DRM/KMS 原生显示时，分析哪些 plane 可用、支持什么格式。

### 9.6 为什么采集 Xorg/LightDM 进程

```bash
ps -ef | grep -Ei 'weston|wayland|xorg|Xorg|lightdm|gdm|sddm|kms|drm'
```

这一步用于判断系统有没有桌面或显示服务。因为后续应用显示路径取决于它：

- 有 Xorg：可以优先尝试 OpenCV `imshow`。
- 有 Wayland/Weston：需要考虑 Wayland 环境变量或对应后端。
- 没有窗口系统：更可能走 DRM/KMS 或 framebuffer。

本阶段确认了 Xorg/LightDM 存在，因此下一阶段先走 OpenCV `imshow` 是合理的。

## 10. 下一阶段预览程序的路线选择

当前摄像头阶段已经确认：

```text
/dev/video42
NV12 3840x2160
```

当前显示阶段已经确认：

```text
DSI-1
480x800 @ 60Hz
Xorg DISPLAY=:0
```

所以下一阶段 `opencv-preview` 可以按这个顺序推进：

1. 先用 OpenCV 打开 `/dev/video42`。
2. 设置较低预览分辨率或读取后缩放到 `480x800`。
3. 将 NV12 转成 BGR/RGB。
4. 先尝试 `DISPLAY=:0` + `cv2.imshow`。
5. 如果 Xauthority 卡住，再补充 Xorg 授权方式。
6. 如果窗口路线不稳定，再考虑 DRM/KMS 原生显示。

不要一开始就写复杂的 DRM/KMS 显示程序。先完成“摄像头输入到屏幕输出”的最小闭环更重要。

## 11. 本阶段可以怎么在面试中讲

可以这样组织表达：

1. 我没有直接写界面程序，而是先确认 Linux 显示链路。
2. 通过 `/dev/fb*` 和 `/sys/class/graphics` 判断当前系统没有暴露传统 framebuffer。
3. 通过 `/dev/dri/by-path` 确认 `/dev/dri/card0` 是 Rockchip display subsystem，`card1` 是 NPU 相关设备。
4. 通过 `/sys/class/drm/card0-DSI-1` 和 `modetest -c` 确认 MIPI DSI 屏幕处于 connected/enabled 状态。
5. 记录屏幕模式为 `480x800 @ 60Hz`，这是后续预览显示的目标分辨率。
6. 通过进程和环境变量确认系统运行 Xorg/LightDM，所以下一阶段优先尝试 OpenCV `imshow`。
7. 对 `xrandr` 权限失败做了区分：这是 Xauthority 问题，不是屏幕链路失败。

## 12. 后续学习重点

进入 `opencv-preview` 后建议继续补强：

- X11 下 adb shell 程序访问 `DISPLAY=:0` 的权限问题。
- OpenCV `VideoCapture` 读取 V4L2 节点的参数设置。
- NV12 到 BGR 的转换方式和性能影响。
- 3840x2160 输入缩放到 480x800 显示时的 CPU 占用。
- DRM/KMS plane、format、buffer 的基本概念。
- 如果不用 X11，如何直接通过 DRM/KMS 显示一帧图像。
