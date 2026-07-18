#!/usr/bin/env python3
"""Minimal OpenCV camera preview for the TaishanPi 3M."""

import argparse
import os
import sys
import time


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="/dev/video42")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--display", default=":0")
    parser.add_argument("--screen-width", type=int, default=480)
    parser.add_argument("--screen-height", type=int, default=800)
    parser.add_argument(
        "--fit",
        choices=("contain", "cover", "stretch"),
        default="contain",
        help="How to fit the camera frame into the display area.",
    )
    parser.add_argument(
        "--fullscreen",
        action="store_true",
        help="Use a borderless fullscreen OpenCV window.",
    )
    parser.add_argument(
        "--rotate",
        choices=("none", "clockwise", "counterclockwise", "180"),
        default="clockwise",
    )
    parser.add_argument("--window-name", default="TaishanPi Camera Preview")
    parser.add_argument(
        "--duration",
        type=float,
        default=0.0,
        help="Stop automatically after this many seconds; 0 runs until q or Esc.",
    )
    return parser.parse_args()


def rotate_frame(cv2, frame, direction):
    rotations = {
        "clockwise": cv2.ROTATE_90_CLOCKWISE,
        "counterclockwise": cv2.ROTATE_90_COUNTERCLOCKWISE,
        "180": cv2.ROTATE_180,
    }
    return cv2.rotate(frame, rotations[direction]) if direction in rotations else frame


def fit_frame(cv2, frame, width, height, mode):
    source_height, source_width = frame.shape[:2]

    if mode == "stretch":
        return cv2.resize(frame, (width, height), interpolation=cv2.INTER_AREA)

    if mode == "cover":
        scale = max(width / source_width, height / source_height)
        resized_width = max(1, int(round(source_width * scale)))
        resized_height = max(1, int(round(source_height * scale)))
        resized = cv2.resize(
            frame, (resized_width, resized_height), interpolation=cv2.INTER_AREA
        )
        left = max(0, (resized_width - width) // 2)
        top = max(0, (resized_height - height) // 2)
        return resized[top : top + height, left : left + width]

    scale = min(width / source_width, height / source_height)
    resized_width = max(1, int(source_width * scale))
    resized_height = max(1, int(source_height * scale))
    resized = cv2.resize(frame, (resized_width, resized_height), interpolation=cv2.INTER_AREA)

    canvas = cv2.copyMakeBorder(
        resized,
        (height - resized_height) // 2,
        height - resized_height - (height - resized_height) // 2,
        (width - resized_width) // 2,
        width - resized_width - (width - resized_width) // 2,
        cv2.BORDER_CONSTANT,
        value=(0, 0, 0),
    )
    return canvas


def main():
    args = parse_args()
    os.environ.setdefault("DISPLAY", args.display)

    try:
        import cv2
    except ImportError:
        print("OpenCV Python bindings are missing (module: cv2).", file=sys.stderr)
        return 2

    capture = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not capture.isOpened():
        print(f"Cannot open camera device: {args.device}", file=sys.stderr)
        return 3

    capture.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    capture.set(cv2.CAP_PROP_FPS, args.fps)
    capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"NV12"))
    capture.set(cv2.CAP_PROP_CONVERT_RGB, 1)

    actual_width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = capture.get(cv2.CAP_PROP_FPS)
    print(
        f"device={args.device} format=NV12 size={actual_width}x{actual_height} "
        f"reported_fps={actual_fps:.2f} display={os.environ['DISPLAY']}"
    )

    cv2.namedWindow(args.window_name, cv2.WINDOW_NORMAL)
    if args.fullscreen:
        cv2.setWindowProperty(
            args.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN
        )
    else:
        cv2.resizeWindow(args.window_name, args.screen_width, args.screen_height)

    frame_count = 0
    total_frames = 0
    fps_samples = []
    run_start = time.monotonic()
    measured_fps = 0.0
    sample_start = run_start

    try:
        while True:
            ok, frame = capture.read()
            if not ok or frame is None:
                print("Camera frame read failed.", file=sys.stderr)
                return 4

            frame_count += 1
            total_frames += 1
            elapsed = time.monotonic() - sample_start
            if elapsed >= 1.0:
                measured_fps = frame_count / elapsed
                fps_samples.append(measured_fps)
                frame_count = 0
                sample_start = time.monotonic()

            frame = rotate_frame(cv2, frame, args.rotate)
            frame = fit_frame(
                cv2, frame, args.screen_width, args.screen_height, args.fit
            )
            cv2.putText(
                frame,
                f"FPS {measured_fps:.1f}",
                (12, 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )
            cv2.imshow(args.window_name, frame)
            if (cv2.waitKey(1) & 0xFF) in (27, ord("q")):
                break
            if args.duration > 0 and time.monotonic() - run_start >= args.duration:
                break
    finally:
        capture.release()
        cv2.destroyAllWindows()

    run_seconds = time.monotonic() - run_start
    average_fps = total_frames / run_seconds if run_seconds > 0 else 0.0
    minimum_fps = min(fps_samples) if fps_samples else average_fps
    maximum_fps = max(fps_samples) if fps_samples else average_fps
    print(
        "PREVIEW_SUMMARY "
        f"frames={total_frames} duration_s={run_seconds:.2f} "
        f"fps_avg={average_fps:.2f} fps_min={minimum_fps:.2f} fps_max={maximum_fps:.2f} "
        f"size={actual_width}x{actual_height} rotate={args.rotate} "
        f"screen={args.screen_width}x{args.screen_height} fit={args.fit} "
        f"fullscreen={int(args.fullscreen)}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
