# Camera Bring-up 日志摘要

采集时间：2026-07-07
分支：`codex/camera-bringup`

## 系统信息

- 开发板：TaishanPi-3M
- 系统：Debian GNU/Linux 12 (bookworm)
- 内核：Linux 6.1.99 aarch64
- 构建信息：root@ghy Fri Apr 24 08:27:24 CST 2026

## 设备识别结论

IMX415 摄像头已被内核识别，实际有效传感器节点为：

```text
m00_b_imx415 4-0037
```

`dmesg_camera.txt` 中关键日志：

```text
imx415 4-0037: Detected imx415 id 0000e0
rockchip-csi2-dphy csi2-dcphy0: dphy0 matches m00_b_imx415 4-0037:bus type 5
rockchip-csi2-dphy csi2-dcphy0: csi2 dphy0 probe successfully!
rkisp-vir0: Async subdev notifier completed
rkaiq_3A.service - Enable Rockchip camera engine rkaiq
```

其他候选地址如 `4-001a`、`5-001a`、`5-0037`、`6-001a`、`6-0037` 返回 `Unexpected sensor id(000000)`，可判断当前摄像头接在 `i2c-4` 的 `0x37` 地址。

## Media Pipeline

`media_pipeline.txt` 显示有效链路为：

```text
m00_b_imx415 4-0037
  -> rockchip-csi2-dphy0
  -> rockchip-mipi-csi2
  -> rkcif / rkisp
```

传感器输出格式：

```text
SGBRG10_1X10 / 3864x2192 @ 30fps
crop: 3840x2160
```

## 推荐应用层采集节点

优先使用：

```text
/dev/video-camera0 -> /dev/video33
```

原因：

- `/dev/video-camera0` 是系统提供的摄像头别名，当前指向 `/dev/video33`。
- `/dev/video33` 属于 `rkisp_mainpath`，驱动为 `rkisp_v10`。
- 默认输出为 `NV12 3840x2160`，相比 raw Bayer 更适合后续 OpenCV 预览和人脸识别输入。

`video-camera0_formats.txt` 支持格式：

```text
UYVY, NV16, NV61, NV21, NV12, NM21, NM12
32x32 - 3840x2160 step 8/8
```

## 原始 Bayer 节点

`/dev/video0` 属于 `rkcif`，对应 `stream_cif_mipi_id0`，输出 raw Bayer：

```text
GB10 3840x2160
```

`video0_formats.txt` 支持：

```text
RG10, BA10, GB10, BG10, Y10
64x64 - 3864x2192 step 8/8
```

该节点更适合底层链路验证，不建议作为第一版 OpenCV 应用输入。

## 当前风险与注意点

- 日志中有多路 `rkcif-mipi-lvds1`、`rkcif-mipi-lvds3` 的 `get remote terminal sensor failed -19`，但有效链路 `rkcif-mipi-lvds` 和 `rkisp-vir0` 已完成 notifier，优先不处理无摄像头接入的其他 MIPI 通道。
- `imx415` 日志里有 `Failed to get power-gpios` 和 pinstate 缺失提示，但 sensor 已成功识别，暂不作为阻塞项。
- 下一步需要实际抓帧验证 `/dev/video-camera0` 和 `/dev/video33` 是否可以稳定输出图像。

## 下一步命令

建议先在板端执行：

```bash
v4l2-ctl -d /dev/video-camera0 --stream-mmap --stream-count=30 --stream-to=/tmp/camera0_nv12.raw
ls -lh /tmp/camera0_nv12.raw
```

如果失败，再直接使用实际节点：

```bash
v4l2-ctl -d /dev/video33 --stream-mmap --stream-count=30 --stream-to=/tmp/video33_nv12.raw
ls -lh /tmp/video33_nv12.raw
```

后续 OpenCV 预览阶段优先从 `/dev/video-camera0` 或 `/dev/video33` 开始。
