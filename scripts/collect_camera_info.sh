#!/usr/bin/env bash
set -u

OUT_DIR="${1:-docs/camera_logs/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

run_cmd() {
    local name="$1"
    shift
    echo "[camera-bringup] collecting $name"
    "$@" > "$OUT_DIR/${name}.txt" 2>&1 || true
}

run_shell() {
    local name="$1"
    local script="$2"
    echo "[camera-bringup] collecting $name"
    sh -c "$script" > "$OUT_DIR/${name}.txt" 2>&1 || true
}

collect_media_pipelines() {
    echo "[camera-bringup] collecting media pipelines"

    # Keep the default media-ctl output for quick comparison with older logs.
    media-ctl -p > "$OUT_DIR/media_pipeline_default.txt" 2>&1 || true

    {
        for media in /dev/media*; do
            [ -e "$media" ] || continue
            echo "===== $media ====="
            media-ctl -d "$media" -p 2>&1 | grep -Ei 'driver|model|bus info|entity|device node name|imx415|dphy|mipi|csi|rkcif|rkisp|ENABLED' || true
            echo
        done
    } > "$OUT_DIR/media_pipelines_summary.txt"

    for media in /dev/media*; do
        [ -e "$media" ] || continue
        safe_name="$(basename "$media")"
        run_cmd "${safe_name}_pipeline" media-ctl -d "$media" -p
    done
}

run_cmd uname uname -a
run_cmd os_release cat /etc/os-release
run_shell video_nodes 'ls -l /dev/video* /dev/media* 2>/dev/null'
run_shell dmesg_camera "dmesg | grep -Ei 'imx415|mipi|csi|isp|v4l2|video|camera|rkisp|rkcif'"
run_shell camera_hints "dmesg | grep -Ei 'Detected imx415|matches m00_b_imx415|Async subdev notifier|first params|set exposure|rkisp-vir|rkcif-mipi-lvds'"
run_cmd v4l2_devices v4l2-ctl --list-devices
collect_media_pipelines

for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    safe_name="$(basename "$dev")"
    run_cmd "${safe_name}_all" v4l2-ctl -d "$dev" --all
    run_cmd "${safe_name}_formats" v4l2-ctl -d "$dev" --list-formats-ext
done

cat > "$OUT_DIR/README.txt" <<EOF
Camera bring-up logs collected at $(date)

Suggested next steps:
1. Inspect dmesg_camera.txt and camera_hints.txt for IMX415, CSI, ISP, or V4L2 errors.
2. Inspect media_pipelines_summary.txt first. If the camera moved to another MIPI connector, the active sensor may appear under /dev/media1, /dev/media2, or another media node instead of /dev/media0.
3. Inspect media*_pipeline.txt to confirm the enabled path from imx415 -> dphy -> mipi-csi2 -> rkcif/rkisp.
4. Inspect v4l2_devices.txt and video*_formats.txt before selecting the capture node, resolution, and pixel format.
5. Try one-frame capture with v4l2-ctl after confirming the target node and format.
EOF

echo "[camera-bringup] logs saved to $OUT_DIR"
