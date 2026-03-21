#!/usr/bin/env python3

import argparse
import json
import sys

from yt_dlp import YoutubeDL


def emit(event):
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def as_float(value, default=0.0):
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def as_int(value, default=0):
    try:
        if value is None:
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def calc_progress(status):
    total = status.get("total_bytes") or status.get("total_bytes_estimate")
    downloaded = status.get("downloaded_bytes")
    if total and downloaded is not None:
        return max(0.0, min(1.0, float(downloaded) / float(total)))

    fragment_count = status.get("fragment_count")
    fragment_index = status.get("fragment_index")
    if fragment_count and fragment_index is not None:
        return max(0.0, min(1.0, float(fragment_index) / float(fragment_count)))

    if status.get("status") == "finished":
        return 1.0
    return 0.0


def progress_event(status):
    info = status.get("info_dict") or {}
    filename = (
        status.get("filename")
        or status.get("tmpfilename")
        or info.get("filepath")
        or (info.get("requested_downloads") or [{}])[0].get("filepath")
        or ""
    )

    detail = filename or info.get("title") or info.get("id") or "Downloading"
    return {
        "type": "progress",
        "phase": "download",
        "status": status.get("status") or "downloading",
        "progress": calc_progress(status),
        "downloaded_bytes": as_int(status.get("downloaded_bytes")),
        "total_bytes": as_int(status.get("total_bytes") or status.get("total_bytes_estimate")),
        "speed_bytes_per_second": as_float(status.get("speed")),
        "eta_seconds": as_float(status.get("eta"), default=-1.0),
        "detail": detail,
        "video_id": info.get("id"),
        "title": info.get("title"),
        "filepath": filename,
    }


def postprocessor_event(status):
    info = status.get("info_dict") or {}
    postprocessor = status.get("postprocessor") or "postprocess"
    return {
        "type": "progress",
        "phase": "postprocess",
        "status": status.get("status") or "started",
        "progress": 1.0 if status.get("status") == "finished" else 0.0,
        "downloaded_bytes": 0,
        "total_bytes": 0,
        "speed_bytes_per_second": 0.0,
        "eta_seconds": -1.0,
        "detail": postprocessor,
        "video_id": info.get("id"),
        "title": info.get("title"),
        "filepath": info.get("filepath") or "",
    }


def sanitize_result(ydl, info):
    return ydl.sanitize_info(info)


def fetch_metadata(url):
    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
    }

    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=False)
        emit({"type": "metadata", "payload": sanitize_result(ydl, info)})


def download_video(url, output, format_selector):
    def on_progress(status):
        emit(progress_event(status))

    def on_postprocessor(status):
        emit(postprocessor_event(status))

    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "outtmpl": {"default": output},
        "progress_hooks": [on_progress],
        "postprocessor_hooks": [on_postprocessor],
        "noprogress": True,  # Suppress internal progress bar to prevent stdout clutter
    }

    if format_selector:
        options["format"] = format_selector

    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=True)
        sanitized = sanitize_result(ydl, info)
        requested = sanitized.get("requested_downloads") or []
        filepath = (
            requested[0].get("filepath")
            if requested
            else sanitized.get("filepath")
        )
        emit(
            {
                "type": "result",
                "filepath": filepath or "",
                "payload": sanitized,
            }
        )


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    metadata_parser = subparsers.add_parser("metadata")
    metadata_parser.add_argument("--url", required=True)

    download_parser = subparsers.add_parser("download")
    download_parser.add_argument("--url", required=True)
    download_parser.add_argument("--output", required=True)
    download_parser.add_argument("--format")

    args = parser.parse_args()

    if args.command == "metadata":
        fetch_metadata(args.url)
    elif args.command == "download":
        download_video(args.url, args.output, args.format)
    else:
        raise SystemExit(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    main()
