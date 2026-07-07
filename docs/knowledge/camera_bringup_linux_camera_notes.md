# Camera Bring-up 阶段 Linux 与摄像头基础知识

本文档总结 `camera-bringup` 阶段涉及的 Linux 操作系统知识、摄像头链路基础，以及 `scripts/collect_camera_info.sh` 脚本的编写思路。目标是把本阶段不只是“命令跑通”，而是能讲清楚 Linux 是如何识别摄像头、暴露设备节点、组织 media pipeline，并让应用层读取图像数据的。

## 1. 本阶段验证了什么

本阶段不是做人脸识别算法，也不是写业务应用，而是确认操作系统已经把 IMX415 MIPI 摄像头识别成可供应用层访问的视频设备。

最终确认结果：

- IMX415 sensor 被内核识别：`m00_b_imx415 4-0037`。
- MIPI 链路建立：`IMX415 -> rockchip-csi2-dphy0 -> rockchip-mipi-csi2 -> rkcif/rkisp`。
- 应用层推荐采集节点：`/dev/video-camera0 -> /dev/video33`。
- `/dev/video33` 是 ISP mainpath，输出 `NV12 3840x2160`。
- 已通过 `v4l2-ctl --stream-mmap` 连续抓取 30 帧 NV12 raw 数据。

这些结果说明：内核驱动、设备树、V4L2 设备节点、media pipeline 和应用层抓帧路径已经形成闭环。

## 2. Linux 里摄像头是如何变成 `/dev/video*` 的

在 Linux 中，摄像头不是应用直接访问硬件寄存器，而是通过内核驱动和统一设备接口暴露给用户态。

大致过程：

```text
硬件 sensor
  -> 设备树描述硬件连接
  -> 内核加载 sensor / CSI / ISP / CIF 驱动
  -> 驱动注册 V4L2 subdev 和 video node
  -> udev/devtmpfs 创建设备节点 /dev/video*
  -> 用户态程序通过 open/ioctl/mmap/read 访问
```

这里有几个关键概念：

| 概念 | 作用 |
| --- | --- |
| 设备树 | 描述板级硬件连接，例如 sensor 在哪个 I2C 总线、MIPI 接到哪个 DPHY、lane 数是多少。 |
| 驱动 | 内核中控制硬件的代码，例如 `imx415`、`rockchip-csi2-dphy`、`rkcif`、`rkisp`。 |
| V4L2 | Linux 视频采集标准接口，应用层通过它访问摄像头。 |
| media controller | 描述复杂视频链路中 sensor、CSI、ISP、video node 的连接关系。 |
| `/dev/video*` | 应用层可打开的视频设备节点。 |
| `/dev/media*` | media controller 设备节点，用于查看或配置 pipeline。 |

所以 `/dev/video33` 并不是“凭空出现”的文件，而是内核中某个 V4L2 video device 注册后由系统创建设备节点。

## 3. 设备树、驱动和 probe

在嵌入式 Linux 中，摄像头这类板级外设通常通过设备树描述。设备树会告诉内核：

- sensor 挂在哪条 I2C 总线上。
- I2C 地址是多少。
- sensor 使用几条 MIPI lane。
- MIPI CSI 接到哪个 DPHY。
- 电源、复位、时钟、pinctrl 如何配置。

内核启动时，驱动会按照设备树匹配硬件，这个过程通常叫 probe。

本阶段日志中最重要的一行是：

```text
imx415 4-0037: Detected imx415 id 0000e0
```

含义：

- `4-0037` 表示 I2C bus 4 上地址 `0x37` 的设备。
- `imx415` 驱动成功读到了 sensor ID。
- 这说明该位置确实有 IMX415 响应。

同时日志中还有一些失败：

```text
imx415 4-001a: Unexpected sensor id(000000), ret(-5)
imx415 5-001a: Unexpected sensor id(000000), ret(-5)
imx415 5-0037: Unexpected sensor id(000000), ret(-5)
```

这些不是当前链路失败，而是驱动/设备树尝试了多个可能位置。真正有效的是 `4-0037`。

## 4. MIPI CSI、CIF、ISP 的作用

IMX415 输出的不是 JPEG 或 RGB 图片，而是 MIPI CSI-2 raw Bayer 数据。中间需要经过硬件链路处理。

本项目中链路大致是：

```text
IMX415 sensor
  -> MIPI CSI-2 DPHY
  -> Rockchip MIPI CSI2
  -> RKCIF
  -> RKISP
  -> /dev/video-camera0
```

各部分作用：

| 模块 | 作用 |
| --- | --- |
| IMX415 sensor | 采集光信号，输出 raw Bayer 数据。 |
| MIPI CSI-2 | 摄像头常用高速串行传输协议。 |
| DPHY | MIPI 的物理层，负责电气和 lane 接收。 |
| RKCIF | Rockchip Camera Interface，可接收并输出 raw 数据流。 |
| RKISP | 图像信号处理器，可把 raw Bayer 处理成 NV12、YUV 等更适合应用使用的格式。 |
| video node | 应用层访问的 V4L2 节点。 |

这也是为什么我们同时看到 `/dev/video0` 和 `/dev/video33`：

- `/dev/video0` 是 rkcif 的 raw Bayer 输出，格式是 `GB10`。
- `/dev/video33` 是 rkisp mainpath 输出，格式是 `NV12`。

第一版应用更适合使用 `/dev/video33`，因为 OpenCV/显示/人脸识别处理 YUV/NV12 通常比处理 raw Bayer 更直接。

## 5. V4L2 基础

V4L2，全称 Video4Linux2，是 Linux 用户态访问视频设备的标准接口。

应用层通常会做这些事情：

```text
open('/dev/video33')
  -> ioctl 查询能力
  -> ioctl 设置格式和分辨率
  -> 请求缓冲区
  -> mmap 映射缓冲区
  -> 启动 stream
  -> 循环取帧
  -> 停止 stream
  -> close
```

`v4l2-ctl` 是命令行调试工具，能帮我们不用写代码就完成查询和抓帧。

常用命令含义：

```bash
v4l2-ctl --list-devices
```

列出所有 V4L2 设备以及它们对应的 `/dev/video*` 节点。

```bash
v4l2-ctl --all -d /dev/video-camera0
```

查看某个设备的驱动、能力、当前格式、分辨率、裁剪区域等。

```bash
v4l2-ctl --list-formats-ext -d /dev/video-camera0
```

查看设备支持哪些像素格式和分辨率范围。

```bash
v4l2-ctl -d /dev/video-camera0 --stream-mmap --stream-count=30 --stream-to=/tmp/camera0_nv12.raw
```

用 mmap 方式连续抓 30 帧，并写入 raw 文件。

## 6. raw Bayer、NV12 和文件大小判断

摄像头底层常见 raw Bayer 格式，例如 `GB10`，表示每个像素是 10-bit Bayer 数据。它还不是常规 RGB 图片，需要经过 ISP 或软件 demosaic 才能变成可直接显示的图像。

`NV12` 是一种 YUV 4:2:0 格式，常见于摄像头、视频编解码和嵌入式图像处理。

NV12 单帧大小计算：

```text
width x height x 1.5
```

本次抓帧为：

```text
3840 x 2160 x 1.5 x 30 = 373248000 字节
```

实际拉回文件大小也是：

```text
373248000 字节
```

所以这能证明：

- 节点确实输出了 30 帧数据。
- 输出分辨率和格式符合 `3840x2160 NV12`。
- 采集链路已经具备后续实时预览输入条件。

注意：raw 文件不是图片文件，不能直接双击查看。后续如果要可视化，需要按格式转换为 PNG/JPG。

## 7. media controller 和 pipeline

现代 SoC 摄像头链路往往不是一个简单设备，而是一串子设备组合。media controller 用来描述这些实体之间的连接关系。

查看命令：

```bash
media-ctl -p
```

本阶段关键结果：

```text
m00_b_imx415 4-0037
  -> rockchip-csi2-dphy0
  -> rockchip-mipi-csi2
  -> rkcif / rkisp
```

`media-ctl -p` 能回答的问题是：

- sensor 是哪个。
- sensor 接到哪个 DPHY。
- 哪些 link 是 enabled。
- 当前数据格式是什么。
- crop 范围是多少。
- 最终 video node 和上游 subdev 如何连接。

这比只看 `/dev/video*` 更可靠，因为 `/dev/video*` 只告诉你有节点，不告诉你节点背后的硬件链路。

## 8. `dmesg` 在本阶段的作用

`dmesg` 用来查看内核日志。摄像头调试中，它能告诉我们：

- 驱动是否加载。
- sensor ID 是否读取成功。
- MIPI DPHY 是否 probe 成功。
- CIF/ISP 是否注册。
- 是否有 I2C、GPIO、时钟、pinctrl、media graph 错误。

本阶段不能只看一句 `set exposure` 就下结论。更合理的判断方式是多证据交叉：

```text
dmesg sensor 检测成功
+ dmesg DPHY endpoint 匹配成功
+ media-ctl pipeline 存在并启用
+ v4l2-ctl 能看到设备和格式
+ stream-mmap 能抓到符合大小的数据
= camera bring-up 成功
```

这也是嵌入式调试里很重要的思路：不要只凭单条日志判断，要把内核日志、设备节点、工具输出和实际数据结果串起来。

## 9. 为什么采集脚本这样写

本阶段脚本是：

```bash
scripts/collect_camera_info.sh
```

它的目的不是修改系统，而是一次性采集排查摄像头链路所需的信息。

### 9.1 使用 `#!/usr/bin/env bash`

```bash
#!/usr/bin/env bash
```

这样脚本会从环境中查找 `bash`，比写死 `/bin/bash` 更灵活。

### 9.2 使用 `set -u`

```bash
set -u
```

含义是使用未定义变量时立即报错。它能减少脚本变量拼写错误导致的隐藏问题。

这里没有使用 `set -e`，是刻意的。因为采集脚本中某些命令可能不存在或某些节点可能不可用，如果一条命令失败就退出，会导致后续日志无法采集。

### 9.3 输出目录可配置

```bash
OUT_DIR="${1:-docs/camera_logs/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"
```

含义：

- 如果调用脚本时传入参数，就用参数作为输出目录。
- 如果没有参数，就自动用时间戳创建目录。
- `mkdir -p` 保证目录不存在时自动创建，存在时也不报错。

### 9.4 每个命令单独保存

脚本中用函数包装命令：

```bash
run_cmd() {
    local name="$1"
    shift
    echo "[camera-bringup] collecting $name"
    "$@" > "$OUT_DIR/${name}.txt" 2>&1 || true
}
```

这样做的原因：

- 每个命令输出保存成独立文件，便于后续定位。
- 标准输出和错误输出都保存：`2>&1`。
- 即使命令失败，也继续采集后续内容：`|| true`。

例如某个 `/dev/video*` 不支持 `--list-formats-ext`，脚本不会中断，而是把错误保存下来。

### 9.5 为什么采集 `uname` 和 `/etc/os-release`

```bash
run_cmd uname uname -a
run_cmd os_release cat /etc/os-release
```

摄像头问题经常和内核版本、系统镜像版本有关。记录系统版本后，后续复现和面试讲解都有依据。

### 9.6 为什么采集 `/dev/video*` 和 `/dev/media*`

```bash
run_shell video_nodes 'ls -l /dev/video* /dev/media* 2>/dev/null'
```

这能确认系统实际创建了哪些设备节点，也能看到类似：

```text
/dev/video-camera0 -> video33
```

这种别名关系对应用层选择节点很有帮助。

### 9.7 为什么 grep dmesg

```bash
run_shell dmesg_camera "dmesg | grep -Ei 'imx415|mipi|csi|isp|v4l2|video|camera|rkisp|rkcif'"
```

完整 `dmesg` 很长，所以脚本只筛选摄像头相关关键词。关键词覆盖了：

- sensor：`imx415`
- MIPI/CSI：`mipi`, `csi`
- 图像处理：`isp`, `rkisp`
- Rockchip CIF：`rkcif`
- V4L2 和 video node：`v4l2`, `video`, `camera`

### 9.8 为什么遍历所有 `/dev/video*`

```bash
for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    safe_name="$(basename "$dev")"
    run_cmd "${safe_name}_all" v4l2-ctl -d "$dev" --all
    run_cmd "${safe_name}_formats" v4l2-ctl -d "$dev" --list-formats-ext
done
```

因为一开始我们并不知道哪个节点是真正可用的摄像头输出。Rockchip 平台可能暴露很多节点：

- CIF raw 节点
- ISP mainpath/selfpath 节点
- statistics 节点
- params 节点
- VPSS scale 节点
- 编解码节点

遍历所有节点可以一次性把候选信息拿全，再从日志里判断：

- 哪个是 raw Bayer。
- 哪个是 ISP 输出。
- 哪个支持 NV12。
- 哪个适合 OpenCV 预览。

这就是我们后面能判断 `/dev/video-camera0 -> /dev/video33` 更适合应用层的原因。

### 9.9 为什么不在脚本里直接抓图

当前脚本没有自动执行 `--stream-mmap` 抓图，原因是：

- 抓图文件可能非常大。
- 不同节点格式不同，盲目抓图可能生成无意义文件。
- 某些节点不是采集节点，stream 可能卡住或失败。
- 先采集设备信息，再人工选择节点更稳。

后面确认 `/dev/video-camera0` 后，才手动执行抓帧命令，这是更安全的流程。

## 10. 本阶段可以怎么在面试中讲

可以这样组织表达：

1. 我先没有直接写 OpenCV 代码，而是从 Linux 设备链路入手确认摄像头是否被系统识别。
2. 通过 `dmesg` 确认 IMX415 在 `i2c-4@0x37` 被 probe 成功，并且和 Rockchip MIPI DPHY 匹配。
3. 通过 `media-ctl -p` 确认链路是 `IMX415 -> CSI DPHY -> MIPI CSI2 -> CIF/ISP`。
4. 通过 `v4l2-ctl --list-devices` 和 `--list-formats-ext` 区分 raw Bayer 节点和 ISP 输出节点。
5. 最终选择 `/dev/video-camera0`，也就是 `/dev/video33`，作为后续应用层输入，因为它是 `rkisp_mainpath`，能输出 `NV12`。
6. 通过 30 帧 raw 抓帧验证，文件大小与 `3840x2160 NV12` 理论大小一致，证明采集链路可用。

## 11. 后续学习重点

下一步进入 `display-bringup`，建议继续沿用同样方法：

- 先确认 `/dev/fb*`、`/dev/dri/*`、Wayland/X11/DRM/KMS 等显示链路。
- 先用系统工具显示测试图，而不是马上接入复杂应用。
- 把内核日志、设备节点、工具输出和实际显示结果放在一起判断。

摄像头后续还可以补强：

- V4L2 mmap 采集代码流程。
- NV12 到 BGR/RGB 的格式转换。
- raw Bayer 与 ISP 的关系。
- Rockchip RKAIQ / 3A 服务作用。
- 设备树中 endpoint、remote-endpoint、data-lanes 的含义。
