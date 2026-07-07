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

run_cmd uname uname -a
run_cmd os_release cat /etc/os-release
run_shell video_nodes 'ls -l /dev/video* /dev/media* 2>/dev/null'
run_shell dmesg_camera "dmesg | grep -Ei 'imx415|mipi|csi|isp|v4l2|video|camera|rkisp|rkcif'"
run_cmd v4l2_devices v4l2-ctl --list-devices
run_cmd media_pipeline media-ctl -p

for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    safe_name="$(basename "$dev")"
    run_cmd "${safe_name}_all" v4l2-ctl -d "$dev" --all
    run_cmd "${safe_name}_formats" v4l2-ctl -d "$dev" --list-formats-ext
done

cat > "$OUT_DIR/README.txt" <<EOF
Camera bring-up logs collected at $(date)

Suggested next steps:
1. Inspect dmesg_camera.txt for IMX415, CSI, ISP, or V4L2 errors.
2. Inspect v4l2_devices.txt to choose the correct /dev/video* node.
3. Inspect video*_formats.txt before selecting capture resolution and pixel format.
4. Try one-frame capture with v4l2-ctl after confirming the target node and format.
EOF

echo "[camera-bringup] logs saved to $OUT_DIR"
