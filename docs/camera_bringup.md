# Camera Bring-up 调试记录

本文档记录 `codex/camera-bringup` 阶段的 IMX415 MIPI 摄像头调试过程。目标是在泰山派 3M 的 Debian 12 系统中确认摄像头链路可用，并获得后续实时预览和人脸识别需要的基础参数。

原始日志保存在 `docs/camera_logs/`，摘要见 `docs/camera_logs/summary.md`。大体积 raw 抓帧文件不纳入 Git。

## 阶段目标

- 确认 IMX415 相关驱动是否加载。
- 确认系统是否生成 `/dev/video*` 设备节点。
- 记录 V4L2 支持的像素格式、分辨率和帧率。
- 记录 media pipeline 拓扑。
- 完成连续抓帧验证。
- 整理本阶段命令输出、问题记录和验收结论。

## 硬件与系统

| 项目 | 记录 |
| --- | --- |
| 开发板 | 泰山派 3M |
| 摄像头 | IMX415 MIPI 摄像头 |
| 系统 | Debian GNU/Linux 12 (bookworm) |
| 内核版本 | `Linux TaishanPi-3M 6.1.99 #1 SMP Mon Apr 20 08:41:30 CST 2026 aarch64 GNU/Linux` |
| 摄像头接口 | MIPI CSI，4 lane |
| 有效 sensor | `m00_b_imx415 4-0037` |
| 推荐应用层节点 | `/dev/video-camera0 -> /dev/video33` |
| raw Bayer 验证节点 | `/dev/video0` |
| 推荐应用层格式 | `NV12 3840x2160` |
| raw Bayer 格式 | `GB10 3840x2160` |

## 前置检查

板端执行：

```bash
uname -a
cat /etc/os-release
ls -l /dev/video* /dev/media*
```

验证结果：

- 系统为 Debian 12，内核为 `6.1.99`。
- 系统生成 `/dev/media0` 到 `/dev/media8`。
- 系统生成 `/dev/video0` 到 `/dev/video72`。
- 系统生成摄像头别名 `/dev/video-camera0 -> video33`。

## 驱动日志检查

板端执行：

```bash
dmesg | grep -Ei 'imx415|mipi|csi|isp|v4l2|video|camera|rkisp|rkcif'
```

关键有效日志：

```text
imx415 4-0037: Detected imx415 id 0000e0
rockchip-csi2-dphy csi2-dcphy0: dphy0 matches m00_b_imx415 4-0037:bus type 5
rockchip-csi2-dphy csi2-dcphy0: csi2 dphy0 probe successfully!
rkisp-vir0: Async subdev notifier completed
rkaiq_3A.service - Enable Rockchip camera engine rkaiq
imx415 4-0037: set exposure(shr0) 2047 = cur_vts(2250) - val(203)
rkisp rkisp-vir0: first params buf queue
```

判断依据：

- `Detected imx415 id 0000e0` 是 sensor 探测成功的核心证据。
- `dphy0 matches m00_b_imx415 4-0037` 是 MIPI DPHY 与 sensor 端点匹配成功的证据。
- `rkisp-vir0: Async subdev notifier completed` 说明 ISP 侧异步子设备绑定完成。
- `set exposure` 和 `first params buf queue` 只作为 3A/ISP 参数流程已经运行的辅助证据，不能单独用于判断摄像头链路完整可用。

同时日志中存在多个未接入候选地址的失败：

```text
imx415 4-001a: Unexpected sensor id(000000), ret(-5)
imx415 5-001a: Unexpected sensor id(000000), ret(-5)
imx415 5-0037: Unexpected sensor id(000000), ret(-5)
imx415 6-001a: Unexpected sensor id(000000), ret(-5)
imx415 6-0037: Unexpected sensor id(000000), ret(-5)
```

这些失败表示设备树/驱动尝试了多个可能的 sensor 位置，但当前实际有效设备是 `i2c-4` 上的 `0x37`，即 `imx415 4-0037`。

## V4L2 设备检查

板端执行：

```bash
v4l2-ctl --list-devices
v4l2-ctl --all -d /dev/video-camera0
v4l2-ctl --list-formats-ext -d /dev/video-camera0
v4l2-ctl --all -d /dev/video0
v4l2-ctl --list-formats-ext -d /dev/video0
```

应用层推荐节点结果：

| 项目 | 实际结果 |
| --- | --- |
| 视频设备节点 | `/dev/video-camera0 -> /dev/video33` |
| Driver name | `rkisp_v10` |
| Card type | `rkisp_mainpath` |
| Bus info | `platform:rkisp-vir0` |
| 默认格式 | `NV12 3840x2160` |
| 支持格式 | `UYVY`, `NV16`, `NV61`, `NV21`, `NV12`, `NM21`, `NM12` |
| 支持分辨率 | `32x32 - 3840x2160`，step `8/8` |
| 推荐测试分辨率 | `3840x2160`，后续预览可降到 `1280x720` 或 `1920x1080` |
| 推荐测试帧率 | sensor 端 pipeline 显示 30fps；应用层实际 FPS 后续在 OpenCV 预览阶段统计 |

raw Bayer 节点结果：

| 项目 | 实际结果 |
| --- | --- |
| 视频设备节点 | `/dev/video0` |
| Driver name | `rkcif` |
| Card type | `rkcif` |
| Bus info | `platform:rkcif-mipi-lvds` |
| 默认格式 | `GB10 3840x2160` |
| 支持格式 | `RG10`, `BA10`, `GB10`, `BG10`, `Y10` |
| 支持分辨率 | `64x64 - 3864x2192`，step `8/8` |
| 使用建议 | 适合底层链路和 raw 数据验证，不作为第一版 OpenCV 预览输入 |

## Media Pipeline 检查

板端执行：

```bash
media-ctl -p
```

关键链路：

```text
m00_b_imx415 4-0037
  -> rockchip-csi2-dphy0
  -> rockchip-mipi-csi2
  -> rkcif / rkisp
```

sensor entity：

```text
entity 63: m00_b_imx415 4-0037
             type V4L2 subdev subtype Sensor
             device node name /dev/v4l-subdev5
```

sensor 输出格式：

```text
SGBRG10_1X10/3864x2192@10000/300000
crop.bounds:(12,16)/3840x2160
```

`10000/300000` 对应约 30fps。后续应用层预览优先走 ISP mainpath 输出的 NV12，而不是直接处理 raw Bayer。

## 抓帧验证

板端执行：

```bash
v4l2-ctl -d /dev/video-camera0 --stream-mmap --stream-count=30 --stream-to=/tmp/camera0_nv12.raw
ls -lh /tmp/camera0_nv12.raw
```

抓帧结果：

| 项目 | 结果 |
| --- | --- |
| 节点 | `/dev/video-camera0` |
| 实际节点 | `/dev/video33` |
| 格式 | `NV12` |
| 分辨率 | `3840x2160` |
| 帧数 | 30 |
| raw 文件 | `docs/camera0_nv12.raw`，未纳入 Git |
| 文件大小 | `373248000` 字节 |
| 理论大小 | `3840 x 2160 x 1.5 x 30 = 373248000` 字节 |
| 验证结论 | 文件大小与 30 帧 NV12 理论大小完全一致，说明 `/dev/video-camera0` 可以连续输出图像数据 |

由于 raw 文件体积约 373 MB，不纳入 Git 提交。仓库只保留抓帧命令、文件大小和结论。后续如需可视化验证，可从 raw 中截取单帧并转换为 PNG/JPG，再提交小体积图片。

## 自动采集脚本

本分支提供 `scripts/collect_camera_info.sh`，可在板端仓库根目录执行：

```bash
bash scripts/collect_camera_info.sh
```

本次采集结果已保存到：

```text
docs/camera_logs/
```

关键文件：

| 文件 | 内容 |
| --- | --- |
| `docs/camera_logs/dmesg_camera.txt` | 摄像头、MIPI、CSI、ISP、V4L2 相关内核日志 |
| `docs/camera_logs/v4l2_devices.txt` | V4L2 设备分组和节点列表 |
| `docs/camera_logs/media_pipeline.txt` | media controller pipeline 拓扑 |
| `docs/camera_logs/video-camera0_all.txt` | `/dev/video-camera0` 详细信息 |
| `docs/camera_logs/video-camera0_formats.txt` | `/dev/video-camera0` 支持格式 |
| `docs/camera_logs/video0_all.txt` | `/dev/video0` raw Bayer 节点详细信息 |
| `docs/camera_logs/video0_formats.txt` | `/dev/video0` 支持格式 |
| `docs/camera_logs/summary.md` | 本次日志摘要 |

## 验收标准

- [x] `dmesg` 能看到 IMX415、CSI、ISP、V4L2 相关有效日志。
- [x] `v4l2-ctl --list-devices` 能列出视频设备。
- [x] `v4l2-ctl --list-formats-ext` 能列出可采集格式。
- [x] `media-ctl -p` 能看到 sensor 到 CSI/ISP/video node 的 pipeline。
- [x] 能通过 `v4l2-ctl --stream-mmap` 连续抓取 30 帧数据。
- [x] 已保存关键命令输出到 `docs/camera_logs/`。
- [x] 已在本文档中补充实际设备节点、格式、问题和结论。

## 问题记录

| 问题 | 现象 | 原因分析 | 处理方式 |
| --- | --- | --- | --- |
| 多个 IMX415 候选地址 probe 失败 | `4-001a`、`5-001a`、`5-0037`、`6-001a`、`6-0037` 返回 `Unexpected sensor id(000000)` | 设备树/驱动枚举了多个可能接入位置，当前实际硬件只在 `4-0037` 有 sensor 响应 | 不作为阻塞项，记录有效节点 `m00_b_imx415 4-0037` |
| 部分未接入 MIPI 通道报 `get remote terminal sensor failed -19` | `rkcif-mipi-lvds1`、`rkcif-mipi-lvds3` 有失败日志 | 对应通道没有实际 sensor 终端，当前有效通道是 `rkcif-mipi-lvds` / `rkisp-vir0` | 不作为阻塞项，后续只使用 `/dev/video-camera0` 或 `/dev/video33` |
| IMX415 日志提示 GPIO/pinstate 缺失 | `Failed to get power-gpios`、`could not get default pinstate` | 当前设备树可能未配置对应可选 GPIO/pinctrl，或驱动兼容板级简化配置 | sensor 已识别且能抓帧，暂不处理；后续底层补强阶段再分析设备树 |
| raw 抓帧文件体积过大 | 30 帧 4K NV12 raw 文件约 373 MB | raw 是未压缩图像数据，体积符合预期 | `.gitignore` 忽略 `*.raw`，仓库只记录命令、大小和结论 |

## 本阶段结论

`camera-bringup` 阶段完成。

IMX415 MIPI 摄像头已在泰山派 3M 的 Debian 12 系统中被识别，有效 sensor 为 `m00_b_imx415 4-0037`。media pipeline 显示链路为 `IMX415 -> rockchip-csi2-dphy0 -> rockchip-mipi-csi2 -> rkcif/rkisp`。应用层推荐使用 `/dev/video-camera0`，该别名指向 `/dev/video33`，属于 `rkisp_mainpath`，支持 `NV12 3840x2160` 输出。通过 `v4l2-ctl --stream-mmap` 已完成 30 帧 NV12 raw 抓帧，文件大小与理论值一致，说明摄像头链路已满足后续实时预览开发的输入条件。

下一阶段按项目流程进入 `display-bringup`，确认 MIPI 屏幕或当前显示链路是否可稳定显示测试画面。完成显示链路验证后，再进入 `opencv-preview`，把 `/dev/video-camera0` 的采集画面显示到屏幕上。
