#!/usr/bin/env python3
"""
Downloads and installs ONLY the Godot 4.7.2 Web export templates into
%APPDATA%/Godot/export_templates/4.7.2.stable/ using HTTP Range requests
against the official GitHub Release .tpz archive (~40 MB vs 1.28 GB).
Verifies zlib CRC32 for every extracted template file.
"""

from __future__ import annotations

import os
import struct
import sys
import urllib.request
import zlib
from pathlib import Path

TPZ_URL = (
    "https://github.com/godotengine/godot/releases/download/"
    "4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
)

TARGET_ENTRIES = {
    "templates/version.txt": "version.txt",
    "templates/web_nothreads_release.zip": "web_nothreads_release.zip",
    "templates/web_nothreads_debug.zip": "web_nothreads_debug.zip",
    "templates/web_release.zip": "web_release.zip",
    "templates/web_debug.zip": "web_debug.zip",
}

USER_AGENT = "AstraRex-WebGL-Template-Installer/1.0"


class _RangeRedirectHandler(urllib.request.HTTPRedirectHandler):
    pass


def resolve_cdn_url_and_size(url: str) -> tuple[str, int]:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        final_url = resp.geturl()
        length = int(resp.headers.get("Content-Length", "0"))
        if length <= 0:
            raise RuntimeError(f"Invalid Content-Length from HEAD: {length}")
        return final_url, length


def fetch_range(url: str, start: int, end: int) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Range": f"bytes={start}-{end}",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        status = getattr(resp, "status", 200)
        if status not in (200, 206):
            raise RuntimeError(f"Unexpected HTTP status {status} for range {start}-{end}")
        data = resp.read()
        if status == 200 and len(data) > (end - start + 1):
            return data[start : end + 1]
        return data


def parse_central_directory(cdn_url: str, total_size: int) -> dict[str, tuple[int, int, int, int, int]]:
    tail_size = min(131072, total_size)
    tail_start = total_size - tail_size
    tail = fetch_range(cdn_url, tail_start, total_size - 1)

    eocd_sig = b"PK\x05\x06"
    eocd_idx = tail.rfind(eocd_sig)
    if eocd_idx < 0:
        raise RuntimeError("Could not locate ZIP End-of-Central-Directory record")

    eocd = tail[eocd_idx : eocd_idx + 22]
    _, _, _, _, _, cd_size, cd_offset, _ = struct.unpack("<IHHHHIIH", eocd)

    if cd_offset >= tail_start and (cd_offset - tail_start + cd_size) <= len(tail):
        cd_data = tail[cd_offset - tail_start : cd_offset - tail_start + cd_size]
    else:
        cd_data = fetch_range(cdn_url, cd_offset, cd_offset + cd_size - 1)

    entries: dict[str, tuple[int, int, int, int, int]] = {}
    pos = 0
    while pos < len(cd_data):
        if cd_data[pos : pos + 4] != b"PK\x01\x02":
            break
        hdr = struct.unpack("<IHHHHHHIIIHHHHHII", cd_data[pos : pos + 46])
        method = hdr[4]
        crc = hdr[7]
        comp_size = hdr[8]
        uncomp_size = hdr[9]
        fn_len = hdr[10]
        extra_len = hdr[11]
        comment_len = hdr[12]
        local_off = hdr[16]
        name = cd_data[pos + 46 : pos + 46 + fn_len].decode("utf-8", errors="replace")
        entries[name] = (method, crc, comp_size, uncomp_size, local_off)
        pos += 46 + fn_len + extra_len + comment_len
    return entries


def extract_entry(cdn_url: str, entry: tuple[int, int, int, int, int]) -> bytes:
    method, expected_crc, comp_size, uncomp_size, local_off = entry
    # Local header is 30 bytes + variable filename + extra field; grab modest slack first
    chunk = fetch_range(cdn_url, local_off, local_off + 30 + 512 + comp_size - 1)
    if chunk[:4] != b"PK\x03\x04":
        raise RuntimeError(f"Bad local ZIP header signature at offset {local_off}")
    fn_len, ex_len = struct.unpack("<HH", chunk[26:30])
    data_start = 30 + fn_len + ex_len
    data_end = data_start + comp_size
    if data_end > len(chunk):
        extra_needed = fetch_range(
            cdn_url,
            local_off + len(chunk),
            local_off + data_end - 1,
        )
        chunk += extra_needed
    payload = chunk[data_start:data_end]
    if method == 0:
        raw = payload
    elif method == 8:
        raw = zlib.decompress(payload, -15)
    else:
        raise RuntimeError(f"Unsupported ZIP compression method {method}")

    if len(raw) != uncomp_size:
        raise RuntimeError(f"Size mismatch: got {len(raw)} bytes, expected {uncomp_size}")
    actual_crc = zlib.crc32(raw) & 0xFFFFFFFF
    if actual_crc != expected_crc:
        raise RuntimeError(f"CRC32 mismatch: got {actual_crc:#x}, expected {expected_crc:#x}")
    return raw


def main() -> int:
    appdata = os.environ.get("APPDATA", "")
    if not appdata:
        print("ERROR: APPDATA environment variable not set.", file=sys.stderr)
        return 1
    dest_dir = Path(appdata) / "Godot" / "export_templates" / "4.7.2.stable"
    dest_dir.mkdir(parents=True, exist_ok=True)

    missing = [out for out in TARGET_ENTRIES.values() if not (dest_dir / out).exists()]
    if not missing:
        print(f"All Godot 4.7.2 Web templates already present in {dest_dir}")
        return 0

    print(f"Resolving {TPZ_URL} ...")
    cdn_url, total_size = resolve_cdn_url_and_size(TPZ_URL)
    print(f"Archive size: {total_size:,} bytes; parsing ZIP central directory...")
    cd_entries = parse_central_directory(cdn_url, total_size)

    for tpz_key, out_name in TARGET_ENTRIES.items():
        out_path = dest_dir / out_name
        if out_path.exists() and out_path.stat().st_size > 0:
            print(f"  [SKIP] {out_name} already exists ({out_path.stat().st_size:,} B)")
            continue
        if tpz_key not in cd_entries:
            print(f"  [ERR] Missing {tpz_key} in .tpz central directory", file=sys.stderr)
            return 1
        print(f"  [GET]  {tpz_key} -> {out_path} ...")
        raw = extract_entry(cdn_url, cd_entries[tpz_key])
        out_path.write_bytes(raw)
        print(f"         verified OK ({len(raw):,} bytes)")

    print("Godot 4.7.2 Web export templates installed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
