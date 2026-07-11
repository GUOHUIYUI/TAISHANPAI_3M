#!/bin/sh

set -u

DURATION="${1:-600}"
REPORT="${2:-/tmp/opencv_preview_report.md}"
PYTHON="${PYTHON:-/opt/opencv-env/bin/python3}"
PREVIEW_SCRIPT="${PREVIEW_SCRIPT:-/opt/face-terminal/scripts/opencv_preview.py}"
DEVICE="${DEVICE:-/dev/video42}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
ROTATE="${ROTATE:-clockwise}"
SCREEN_WIDTH="${SCREEN_WIDTH:-480}"
SCREEN_HEIGHT="${SCREEN_HEIGHT:-800}"
DISPLAY="${DISPLAY:-:0}"
XAUTHORITY="${XAUTHORITY:-/var/run/lightdm/root/:0}"
QT_QPA_FONTDIR="${QT_QPA_FONTDIR:-/usr/share/fonts}"

WORK_DIR="$(mktemp -d /tmp/opencv-preview-collect.XXXXXX)" || exit 1
PREVIEW_LOG="$WORK_DIR/preview.log"
SAMPLES="$WORK_DIR/process_samples.txt"

cleanup() {
    if [ "${PREVIEW_PID:-}" ] && kill -0 "$PREVIEW_PID" 2>/dev/null; then
        kill "$PREVIEW_PID" 2>/dev/null || true
        wait "$PREVIEW_PID" 2>/dev/null || true
    fi
}
trap cleanup INT TERM EXIT

if [ ! -x "$PYTHON" ]; then
    echo "Python not found or not executable: $PYTHON" >&2
    exit 2
fi

if [ ! -f "$PREVIEW_SCRIPT" ]; then
    echo "Preview script not found: $PREVIEW_SCRIPT" >&2
    exit 3
fi

if [ ! -e "$DEVICE" ]; then
    echo "Camera device not found: $DEVICE" >&2
    exit 4
fi

export DISPLAY XAUTHORITY QT_QPA_FONTDIR

"$PYTHON" "$PREVIEW_SCRIPT" \
    --device "$DEVICE" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --rotate "$ROTATE" \
    --screen-width "$SCREEN_WIDTH" \
    --screen-height "$SCREEN_HEIGHT" \
    --duration "$DURATION" >"$PREVIEW_LOG" 2>&1 &
PREVIEW_PID=$!

echo "[opencv-preview] pid=$PREVIEW_PID, collecting for ${DURATION}s"
echo "timestamp cpu_percent rss_kb" >"$SAMPLES"

while kill -0 "$PREVIEW_PID" 2>/dev/null; do
    SAMPLE="$(ps -p "$PREVIEW_PID" -o %cpu= -o rss= 2>/dev/null | awk 'NF == 2 { print $1, $2 }')"
    if [ "$SAMPLE" ]; then
        echo "$(date '+%Y-%m-%dT%H:%M:%S') $SAMPLE" >>"$SAMPLES"
    fi
    sleep 1
done

wait "$PREVIEW_PID"
PREVIEW_STATUS=$?
PREVIEW_PID=""

SUMMARY="$(grep 'PREVIEW_SUMMARY' "$PREVIEW_LOG" | tail -n 1)"
CPU_AVG="$(awk 'NR > 1 { sum += $2; count++ } END { if (count) printf "%.2f", sum/count; else print "N/A" }' "$SAMPLES")"
RSS_AVG_KB="$(awk 'NR > 1 { sum += $3; count++ } END { if (count) printf "%.0f", sum/count; else print "N/A" }' "$SAMPLES")"
RSS_MAX_KB="$(awk 'NR > 1 && $3 > max { max=$3 } END { if (max) print max; else print "N/A" }' "$SAMPLES")"
SAMPLE_COUNT="$(awk 'END { print NR > 0 ? NR-1 : 0 }' "$SAMPLES")"
NOW="$(date '+%Y-%m-%d %H:%M:%S %z')"

get_value() {
    echo "$SUMMARY" | tr ' ' '\n' | awk -F= -v key="$1" '$1 == key { print $2; exit }'
}

FPS_AVG="$(get_value fps_avg)"
FPS_MIN="$(get_value fps_min)"
FPS_MAX="$(get_value fps_max)"
ACTUAL_SIZE="$(get_value size)"
RUN_SECONDS="$(get_value duration_s)"

{
    echo "# OpenCV Preview Validation Report"
    echo
    echo "Generated: $NOW"
    echo
    echo "## Result"
    echo
    echo "| Item | Value |"
    echo "| --- | --- |"
    echo "| Exit status | \`$PREVIEW_STATUS\` |"
    echo "| Camera device | \`$DEVICE\` |"
    echo "| Requested format | \`NV12\` |"
    echo "| Requested resolution | \`${WIDTH}x${HEIGHT}\` |"
    echo "| Actual resolution | \`${ACTUAL_SIZE:-unknown}\` |"
    echo "| Display | \`$DISPLAY\` |"
    echo "| Xauthority | \`$XAUTHORITY\` |"
    echo "| Physical screen | \`${SCREEN_WIDTH}x${SCREEN_HEIGHT}\` portrait |"
    echo "| Rotation | \`$ROTATE\` |"
    echo "| Preview FPS (avg/min/max) | \`${FPS_AVG:-N/A} / ${FPS_MIN:-N/A} / ${FPS_MAX:-N/A}\` |"
    echo "| Process CPU average | \`${CPU_AVG}%\` |"
    echo "| RSS average / maximum | \`${RSS_AVG_KB} KB / ${RSS_MAX_KB} KB\` |"
    echo "| Measured runtime | \`${RUN_SECONDS:-N/A} s\` |"
    echo "| Process samples | \`$SAMPLE_COUNT\` |"
    echo
    echo "## Launch Command"
    echo
    echo '```bash'
    echo "DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY QT_QPA_FONTDIR=$QT_QPA_FONTDIR $PYTHON $PREVIEW_SCRIPT --device $DEVICE --width $WIDTH --height $HEIGHT --rotate $ROTATE --screen-width $SCREEN_WIDTH --screen-height $SCREEN_HEIGHT"
    echo '```'
    echo
    echo "## Automatic Checks"
    echo
    if [ "$PREVIEW_STATUS" -eq 0 ] && [ "$SUMMARY" ]; then
        echo "- [x] OpenCV opened the camera and completed the timed preview run."
    else
        echo "- [ ] Preview did not complete successfully; inspect the log below."
    fi
    echo "- [ ] Confirm manually that the image direction is correct."
    echo "- [ ] Confirm manually that the image is not stretched or visibly delayed."
    echo
    echo "## Program Output"
    echo
    echo '```text'
    cat "$PREVIEW_LOG"
    echo '```'
} >"$REPORT"

trap - INT TERM EXIT
rm -rf "$WORK_DIR"

echo "[opencv-preview] report: $REPORT"
exit "$PREVIEW_STATUS"
