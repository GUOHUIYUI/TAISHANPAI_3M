# Camera Bring-up 调试记录

本文档记录 `codex/camera-bringup` 阶段的 IMX415 MIPI 摄像头调试过程。目标是在泰山派 3M 的 Debian 12 系统中确认摄像头链路可用，并获得后续实时预览和人脸识别需要的基础参数。

原始日志保存在 `docs/camera_logs/`，摘要见 `docs/camera_logs/summary.md`。大体积 raw/YUV 抓帧文件不纳入 Git。

## 阶段目标

- 确认 IMX415 相关驱动是否加载。
- 确认系统是否生成 `/dev/video*` 和 `/dev/media*` 设备节点。
- 记录 V4L2 支持的像素格式、分辨率和帧率。
- 记录 media pipeline 拓扑。
- 完成连续抓帧验证。
- 整理本阶段命令输出、问题记录和验收结论。

## 硬件与系统

| 项目 | 最终记录 |
| --- | --- |
| 开发板 | 泰山派 3M |
| 摄像头 | IMX415 MIPI 摄像头 |
| 系统 | Debian GNU/Linux 12 (bookworm) |
| 内核版本 | `Linux TaishanPi-3M 6.1.99 #1 SMP Mon Apr 20 08:41:30 CST 2026 aarch64 GNU/Linux` |
| 摄像头接口 | MIPI CSI，4 lane |
| 最终有效 sensor | `m00_b_imx415 5-0037` |
| 最终有效 CIF media | `/dev/media1`，`rkcif-mipi-lvds1` |
| 最终有效 ISP media | `/dev/media4`，`rkisp-vir1` |
| 推荐应用层节点 | `/dev/video42` |
| raw Bayer 验证节点 | `/dev/video11` |
| 推荐应用层格式 | `NV12 3840x2160` |
| raw Bayer 格式 | `GB10 3840x2160` |

说明：本阶段曾在旧 MIPI 接口上验证过 `m00_b_imx415 4-0037`、`/dev/video-camera0 -> /dev/video33`。后续硬件切换到新的 MIPI 接口后，最终验收以 `5-0037`、`/dev/media1`、`/dev/media4`、`/dev/video42` 为准。

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
- 换 MIPI 接口后，不能只依赖 `/dev/video-camera0` 或默认 `media-ctl -p`；必须遍历全部 `/dev/media*` 查找实际有效链路。

## 驱动日志检查

板端执行：

```bash
dmesg | grep -Ei 'imx415|mipi|csi|isp|v4l2|video|camera|rkisp|rkcif'
```

最终关键有效日志：

```text
imx415 5-0037: Detected imx415 id 0000e0
rockchip-csi2-dphy csi2-dphy0: dphy0 matches m00_b_imx415 5-0037:bus type 5
imx415 5-0037: set exposure(shr0) 2047 = cur_vts(2250) - val(203)
rkisp rkisp-vir1: first params buf queue
```

判断依据：

- `Detected imx415 id 0000e0` 是 sensor 探测成功的核心证据。
- `dphy0 matches m00_b_imx415 5-0037` 是 MIPI DPHY 与 sensor 端点匹配成功的证据。
- `set exposure` 和 `first params buf queue` 说明 3A/ISP 参数流程已经运行，但不能单独作为链路完整可用的唯一依据。
- 完整可用性需要结合 media pipeline 的 `[ENABLED]` 链路和 `v4l2-ctl --stream-mmap` 抓帧验证。

日志中仍存在多个未接入候选地址或未接入通道的失败，例如：

```text
Unexpected sensor id(000000), ret(-5)
rkcif_update_sensor_info: get remote terminal sensor failed
update sensor info failed -19
```

这些失败主要来自旧接口或未接摄像头的候选通道。最终有效通道是 `rkcif-mipi-lvds1` / `rkisp-vir1`，因此不作为本阶段阻塞项。

## V4L2 设备检查

板端执行：

```bash
v4l2-ctl --list-devices
v4l2-ctl --all -d /dev/video42
v4l2-ctl --list-formats-ext -d /dev/video42
v4l2-ctl --all -d /dev/video11
v4l2-ctl --list-formats-ext -d /dev/video11
```

应用层推荐节点结果：

| 项目 | 实际结果 |
| --- | --- |
| 视频设备节点 | `/dev/video42` |
| Driver name | `rkisp_v10` |
| Card type | `rkisp_mainpath` |
| Bus info | `platform:rkisp-vir1` |
| 默认格式 | `NV12 3840x2160` |
| 支持格式 | `UYVY`, `NV16`, `NV61`, `NV21`, `NV12`, `NM21`, `NM12` |
| 支持分辨率 | `32x32 - 3840x2160`，step `8/8` |
| 使用建议 | 第一版 OpenCV/应用层预览优先使用该节点，必要时降到 `1920x1080` 或 `1280x720` |

raw Bayer 节点结果：

| 项目 | 实际结果 |
| --- | --- |
| 视频设备节点 | `/dev/video11` |
| Driver name | `rkcif` |
| Card type | `rkcif` |
| Bus info | `platform:rkcif-mipi-lvds1` |
| 默认格式 | `GB10 3840x2160` |
| 支持格式 | `RG10`, `BA10`, `GB10`, `BG10`, `Y10` |
| 支持分辨率 | `64x64 - 3864x2192`，step `8/8` |
| 使用建议 | 适合底层链路和 raw 数据验证，不作为第一版 OpenCV 预览输入 |

## Media Pipeline 检查

板端执行：

```bash
for media in /dev/media*; do
    echo "===== $media ====="
    media-ctl -d "$media" -p
 done
```

最终有效 CIF 链路位于 `/dev/media1`：

```text
m00_b_imx415 5-0037
  -> rockchip-csi2-dphy0
  -> rockchip-mipi-csi2
  -> stream_cif_mipi_id0 /dev/video11
```

最终有效 ISP 链路位于 `/dev/media4`：

```text
rkcif-mipi-lvds1
  -> rkisp-isp-subdev
  -> rkisp_mainpath /dev/video42
```

sensor 输出格式：

```text
SGBRG10_1X10/3864x2192@10000/300000
crop.bounds:(12,16)/3840x2160
```

`10000/300000` 对应约 30fps。后续应用层预览优先走 ISP mainpath 输出的 NV12，而不是直接处理 raw Bayer。

## 抓帧验证

最终板端验证命令：

```bash
v4l2-ctl -d /dev/video42 \
  --set-fmt-video=width=3840,height=2160,pixelformat=NV12 \
  --stream-mmap --stream-count=10 --stream-to=/tmp/video42_nv12.yuv
```

抓帧结果：

| 项目 | 结果 |
| --- | --- |
| 节点 | `/dev/video42` |
| 格式 | `NV12` |
| 分辨率 | `3840x2160` |
| 帧数 | 10 |
| 验证结论 | 能连续输出 YUV 数据，说明新 MIPI 接口下的 camera 链路可用 |

大体积 raw/YUV 文件不纳入 Git。仓库只保留抓帧命令、节点能力、日志和结论。

## 自动采集脚本

本分支提供 `scripts/collect_camera_info.sh`，可在板端仓库根目录执行：

```bash
bash scripts/collect_camera_info.sh docs/camera_logs
```

脚本会采集：

| 文件 | 内容 |
| --- | --- |
| `docs/camera_logs/dmesg_camera.txt` | 摄像头、MIPI、CSI、ISP、V4L2 相关内核日志 |
| `docs/camera_logs/camera_hints.txt` | IMX415、DPHY、曝光、ISP 首帧参数等关键提示日志 |
| `docs/camera_logs/v4l2_devices.txt` | V4L2 设备分组和节点列表 |
| `docs/camera_logs/media_pipelines_summary.txt` | 所有 `/dev/media*` 的关键信息汇总 |
| `docs/camera_logs/media*_pipeline.txt` | 每个 media controller 的完整 pipeline 拓扑 |
| `docs/camera_logs/video42_all.txt` | `/dev/video42` 详细信息 |
| `docs/camera_logs/video42_formats.txt` | `/dev/video42` 支持格式 |
| `docs/camera_logs/video11_all.txt` | `/dev/video11` raw Bayer 节点详细信息 |
| `docs/camera_logs/video11_formats.txt` | `/dev/video11` 支持格式 |
| `docs/camera_logs/summary.md` | 本次日志摘要 |

## 验收标准

- [x] `dmesg` 能看到 IMX415、CSI、ISP、V4L2 相关有效日志。
- [x] `v4l2-ctl --list-devices` 能列出视频设备。
- [x] `v4l2-ctl --list-formats-ext` 能列出可采集格式。
- [x] 遍历 `/dev/media*` 能看到 sensor 到 CSI/ISP/video node 的有效 pipeline。
- [x] 能通过 `/dev/video42` 和 `v4l2-ctl --stream-mmap` 连续抓取 NV12 数据。
- [x] 已保存关键命令输出到 `docs/camera_logs/`。
- [x] 已在本文档中补充实际设备节点、格式、问题和结论。

## 问题记录

| 问题 | 现象 | 原因分析 | 处理方式 |
| --- | --- | --- | --- |
| 换 MIPI 接口后默认 `media-ctl -p` 信息不完整 | 默认只看到 `/dev/media0`，无法看到新接口有效 sensor | `media-ctl -p` 未指定 `-d` 时通常查看默认 media 设备；新接口链路在 `/dev/media1` 和 `/dev/media4` | 修改采集脚本，遍历 `/dev/media*` 并生成 `media*_pipeline.txt` 和 `media_pipelines_summary.txt` |
| 有效 sensor 从 `4-0037` 变为 `5-0037` | 新日志显示 `m00_b_imx415 5-0037` | 硬件换到新的 MIPI/I2C 组合后，设备树匹配到不同 bus/address | 最终文档以 `5-0037` 为准，旧接口信息仅作为历史记录 |
| 多个 IMX415 候选地址 probe 失败 | 部分地址返回 `Unexpected sensor id(000000)` | 设备树/驱动枚举了多个可能接入位置，未接硬件的位置读不到 sensor id | 不作为阻塞项，只记录最终有效节点 `m00_b_imx415 5-0037` |
| 部分未接入 MIPI 通道报 `get remote terminal sensor failed -19` | `rkcif-mipi-lvds`、`rkcif-mipi-lvds3` 等旧/空通道有失败日志 | 对应通道没有实际 sensor 终端 | 不作为阻塞项，后续只使用 `/dev/video42` 或按 media pipeline 重新确认 |
| IMX415 日志提示 GPIO/pinstate 缺失 | `Failed to get power-gpios`、`could not get default pinstate` | 当前设备树可能未配置对应可选 GPIO/pinctrl，或驱动兼容板级简化配置 | sensor 已识别且能抓帧，暂不处理；后续底层补强阶段再分析设备树 |
| raw/YUV 抓帧文件体积过大 | 4K NV12/YUV 文件体积很大 | 未压缩图像数据体积符合预期 | `.gitignore` 忽略 `*.raw`、`*.yuv`，仓库只记录命令、大小和结论 |

## 本阶段结论

`camera-bringup` 阶段完成。

IMX415 MIPI 摄像头已在泰山派 3M 的 Debian 12 系统中被识别。最终验收有效 sensor 为 `m00_b_imx415 5-0037`，有效链路为 `IMX415 -> rockchip-csi2-dphy0 -> rockchip-mipi-csi2 -> rkcif-mipi-lvds1 -> rkisp-vir1 -> /dev/video42`。应用层推荐使用 `/dev/video42`，该节点属于 `rkisp_mainpath`，支持 `NV12 3840x2160` 输出。通过 `v4l2-ctl --stream-mmap` 已完成 NV12/YUV 连续抓帧验证，说明摄像头链路已满足后续实时预览开发的输入条件。

下一阶段按项目流程进入 `display-bringup`，确认 MIPI 屏幕或当前显示链路是否可稳定显示测试画面。完成显示链路验证后，再进入 `opencv-preview`，把 `/dev/video42` 的采集画面显示到屏幕上。
