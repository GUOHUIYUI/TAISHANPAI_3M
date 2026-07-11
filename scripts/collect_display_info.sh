#!/usr/bin/env bash
set -u

OUT_DIR="${1:-docs/display_logs/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

run_cmd() {
    local name="$1"
    shift
    echo "[display-bringup] collecting $name"
    "$@" > "$OUT_DIR/${name}.txt" 2>&1 || true
}

run_shell() {
    local name="$1"
    local script="$2"
    echo "[display-bringup] collecting $name"
    sh -c "$script" > "$OUT_DIR/${name}.txt" 2>&1 || true
}

run_cmd uname uname -a
run_cmd os_release cat /etc/os-release
run_shell display_nodes 'ls -l /dev/fb* /dev/dri/* 2>/dev/null'
run_shell framebuffer_sysfs 'for p in /sys/class/graphics/fb*; do echo "## $p"; for f in name modes virtual_size bits_per_pixel stride state blank; do [ -e "$p/$f" ] && echo "$f=$(cat "$p/$f" 2>/dev/null)"; done; done'
run_shell drm_sysfs 'for p in /sys/class/drm/*; do echo "## $p"; for f in status enabled modes dpms; do [ -e "$p/$f" ] && echo "$f=$(cat "$p/$f" 2>/dev/null)"; done; done'
run_shell session_env 'echo XDG_SESSION_TYPE=$XDG_SESSION_TYPE; echo DISPLAY=$DISPLAY; echo WAYLAND_DISPLAY=$WAYLAND_DISPLAY'
run_shell display_processes "ps -ef | grep -Ei 'weston|wayland|xorg|Xorg|lightdm|gdm|sddm|kms|drm' | grep -v grep"
run_cmd fbset fbset -fb /dev/fb0
run_cmd xrandr xrandr
run_cmd modetest_connectors modetest -c
run_cmd modetest_planes modetest -p

cat > "$OUT_DIR/README.txt" <<EOF
Display bring-up logs collected at $(date)

Suggested next steps:
1. Inspect display_nodes.txt to confirm /dev/fb* and /dev/dri/* availability.
2. Inspect framebuffer_sysfs.txt for framebuffer name, resolution, and bpp.
3. Inspect drm_sysfs.txt and modetest output for connected DRM connector and modes.
4. Inspect session_env.txt and display_processes.txt to determine desktop/session type.
5. Choose the first display validation method: OpenCV imshow, framebuffer write, or DRM/KMS test.
EOF

echo "[display-bringup] logs saved to $OUT_DIR"
