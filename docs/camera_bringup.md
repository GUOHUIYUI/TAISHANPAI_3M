# Camera Bring-up 调试记录

本文档记录 `codex/camera-bringup` 阶段的 IMX415 MIPI 摄像头调试过程。目标是在泰山派 3M 的 Debian 12 系统中确认摄像头链路可用，并获得后续实时预览和人脸识别需要的基础参数。

## 阶段目标

- 确认 IMX415 相关驱动是否加载。
- 确认系统是否生成 `/dev/video*` 设备节点。
- 记录 V4L2 支持的像素格式、分辨率和帧率。
- 记录 media pipeline 拓扑。
- 完成至少一帧图像抓取验证。
- 整理本阶段命令输出、问题记录和验收结论。

## 硬件与系统

| 项目 | 记录 |
| --- | --- |
| 开发板 | 泰山派 3M |
| 摄像头 | IMX415 MIPI 摄像头 |
| 系统 | Debian 12 |
| 内核版本 | 待板端填写 |
| 摄像头接口 | MIPI CSI |
| 设备节点 | 待板端填写，例如 `/dev/video0` |

## 前置检查

在板端执行：

```bash
uname -a
cat /etc/os-release
ls -l /dev/video*
```

预期结果：系统能看到至少一个 `/dev/video*` 节点。如果没有设备节点，优先检查设备树、驱动加载日志、摄像头供电和排线方向。

## 驱动日志检查

```bash
dmesg | grep -Ei 'imx415|mipi|csi|isp|v4l2|video|camera|rkisp|rkcif'
```

需要记录：

- 是否出现 IMX415 probe 成功日志。
- 是否存在 I2C 通信失败、供电失败、时钟失败、reset GPIO 失败等错误。
- 是否出现 ISP、CSI、video node 注册信息。

## V4L2 设备检查

```bash
v4l2-ctl --list-devices
v4l2-ctl --all -d /dev/video0
v4l2-ctl --list-formats-ext -d /dev/video0
```

如果设备节点不是 `/dev/video0`，按实际节点替换。

需要记录：

| 项目 | 实际结果 |
| --- | --- |
| 视频设备节点 | 待填写 |
| Driver name | 待填写 |
| Card type | 待填写 |
| Bus info | 待填写 |
| 支持格式 | 待填写 |
| 推荐测试分辨率 | 待填写 |
| 推荐测试帧率 | 待填写 |

## Media Pipeline 检查

```bash
media-ctl -p
```

需要确认 sensor、CSI、ISP、video node 之间的链路是否存在并启用。把完整输出保存到 `docs/camera_logs/`，后续用于整理 `/dev/video*` 节点背后的内核链路。

## 抓图验证

优先使用 `v4l2-ctl` 做最小验证：

```bash
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=capture.raw
```

如果像素格式和分辨率需要显式指定，可使用：

```bash
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=NV12 --stream-mmap --stream-count=1 --stream-to=capture_1920x1080_nv12.raw
```

实际格式以 `--list-formats-ext` 输出为准。若后续需要可视化 raw 文件，再根据像素格式转换为 PNG/JPG。

## 自动采集脚本

本分支提供 `scripts/collect_camera_info.sh`，在板端仓库根目录执行：

```bash
bash scripts/collect_camera_info.sh
```

默认会把输出保存到：

```text
docs/camera_logs/YYYYMMDD_HHMMSS/
```

也可以指定输出目录：

```bash
bash scripts/collect_camera_info.sh docs/camera_logs/manual_test_01
```

## 验收标准

- [ ] `dmesg` 能看到摄像头、CSI、ISP 或 V4L2 相关有效日志。
- [ ] `v4l2-ctl --list-devices` 能列出视频设备。
- [ ] `v4l2-ctl --list-formats-ext` 能列出至少一种可采集格式。
- [ ] `media-ctl -p` 能看到摄像头到 video node 的 pipeline。
- [ ] 能通过 `v4l2-ctl --stream-mmap` 抓取一帧数据。
- [ ] 已保存关键命令输出到 `docs/camera_logs/`。
- [ ] 已在本文档中补充实际设备节点、格式、问题和结论。

## 问题记录

| 问题 | 现象 | 原因分析 | 处理方式 |
| --- | --- | --- | --- |
| 待填写 |  |  |  |

## 本阶段结论

待板端验证后填写。
