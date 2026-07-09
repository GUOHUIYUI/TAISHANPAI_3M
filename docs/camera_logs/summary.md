# Camera Logs Summary

本目录保存 `camera-bringup` 阶段的板端采集日志。当前最终验收结果来自切换 MIPI 接口后的日志。

## Final Valid Pipeline

```text
m00_b_imx415 5-0037
  -> rockchip-csi2-dphy0
  -> rockchip-mipi-csi2
  -> rkcif-mipi-lvds1
  -> rkisp-vir1
  -> /dev/video42
```

## Key Nodes

| 用途 | 节点 | 说明 |
| --- | --- | --- |
| Sensor | `m00_b_imx415 5-0037` | 最终有效 IMX415 sensor |
| CIF raw | `/dev/media1`, `/dev/video11` | `rkcif-mipi-lvds1`，10-bit Bayer raw |
| ISP output | `/dev/media4`, `/dev/video42` | `rkisp-vir1` mainpath，应用层推荐节点 |

## Key Evidence

- `camera_hints.txt`: `imx415 5-0037: Detected imx415 id 0000e0`
- `camera_hints.txt`: `dphy0 matches m00_b_imx415 5-0037`
- `media1_pipeline.txt`: sensor 到 `rockchip-csi2-dphy0`、`rockchip-mipi-csi2`、`/dev/video11` 的链路为 `[ENABLED]`
- `media4_pipeline.txt`: `rkcif-mipi-lvds1 -> rkisp-isp-subdev -> rkisp_mainpath /dev/video42` 为 `[ENABLED]`
- `video42_all.txt`: `/dev/video42` 默认输出 `NV12 3840x2160`
- `video42_formats.txt`: `/dev/video42` 支持 `UYVY`, `NV16`, `NV61`, `NV21`, `NV12`, `NM21`, `NM12`

## Notes

旧接口曾验证过 `m00_b_imx415 4-0037` 和 `/dev/video-camera0 -> /dev/video33`。当前硬件切换 MIPI 接口后，最终验收以 `5-0037`、`/dev/media1`、`/dev/media4`、`/dev/video42` 为准。

日志里存在旧接口或未接入通道的 `Unexpected sensor id(000000)`、`get remote terminal sensor failed`、`update sensor info failed -19`。这些不是当前有效链路的阻塞项。
