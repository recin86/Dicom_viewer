#!/usr/bin/env python3
"""Cache-only color boundary fixtures, independent of the product adapter.

These minimal Part 10 files exercise the Image Pixel/US pixel specializations,
not full IOD conformance. Literal stored/RGB arrays are the oracle. No codec,
Rust decoder, patient data, or network is used by this writer.
"""

import hashlib
import json
import struct
import sys
from pathlib import Path

SC = "1.2.840.10008.5.1.4.1.1.7"
US = "1.2.840.10008.5.1.4.1.1.6.1"
LE = "1.2.840.10008.1.2.1"
BE = "1.2.840.10008.1.2.2"
IMPLICIT = "1.2.840.10008.1.2"
LONG_VR = {"OB", "OW", "SQ", "UN"}
RGB = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [0, 0, 0], [255, 255, 255], [17, 34, 51]]
YBR = [[76, 85, 255], [150, 44, 21], [29, 255, 107], [0, 128, 128], [255, 128, 128], [128, 128, 128]]
YBR_RGB = [[254, 0, 0], [0, 255, 1], [0, 0, 254], [0, 0, 0], [255, 255, 255], [128, 128, 128]]
PACKED_422 = [76, 100, 85, 255, 29, 60, 255, 107, 0, 255, 128, 128, 128, 64, 128, 128]
EXPANDED_422 = [[76, 85, 255], [100, 85, 255], [29, 255, 107], [60, 255, 107],
                [0, 128, 128], [255, 128, 128], [128, 128, 128], [64, 128, 128]]
RGB_422 = [[254, 0, 0], [255, 24, 24], [0, 0, 254], [31, 31, 255],
           [0, 0, 0], [255, 255, 255], [128, 128, 128], [64, 64, 64]]
PALETTE_INDICES = [0, 1, 2, 3, 4, 255]
PALETTE_RGB = [RGB[0], RGB[0], RGB[1], RGB[2], RGB[5], RGB[5]]


def element(tag, vr, value, endian="<", implicit=False):
    if isinstance(value, str):
        value = value.encode("ascii")
        value += (b"\0" if vr == "UI" else b" ") * (len(value) % 2)
    elif isinstance(value, int):
        value = struct.pack(endian + {"US": "H", "SS": "h", "UL": "I"}[vr], value)
    elif len(value) % 2:
        value += b"\0"
    header = struct.pack(endian + "HH", *tag)
    if implicit:
        return header + struct.pack(endian + "I", len(value)) + value
    if vr in LONG_VR:
        return header + vr.encode() + b"\0\0" + struct.pack(endian + "I", len(value)) + value
    return header + vr.encode() + struct.pack(endian + "H", len(value)) + value


def part10(index, tags, syntax, sop):
    uid = "1.2.826.0.1.3680043.10.543.9200." + str(index)
    meta = b"".join(element(tag, vr, value) for tag, vr, value in [
        ((2, 1), "OB", b"\0\1"), ((2, 2), "UI", sop), ((2, 3), "UI", uid),
        ((2, 0x10), "UI", syntax), ((2, 0x12), "UI", "1.2.826.0.1.3680043.10.543.9200"),
    ])
    tags = dict(tags)
    tags[(8, 0x16)] = ("UI", sop)
    tags[(8, 0x18)] = ("UI", uid)
    endian = ">" if syntax == BE else "<"
    body = b"".join(element(tag, vr, value, endian, syntax == IMPLICIT)
                    for tag, (vr, value) in sorted(tags.items()))
    return b"\0" * 128 + b"DICM" + element((2, 0), "UL", len(meta)) + meta + body


def color_tags(photometric="RGB", planar=0, sop=SC, syntax=LE):
    palette = photometric == "PALETTE COLOR"
    columns = 4 if photometric == "YBR_FULL_422" else 3
    tags = {
        (8, 8): ("CS", "DERIVED\\SECONDARY"), (8, 0x60): ("CS", "US" if sop == US else "OT"),
        (0x18, 0x64): ("CS", "WSD"),
        (0x28, 2): ("US", 1 if palette else 3), (0x28, 4): ("CS", photometric),
        (0x28, 0x10): ("US", 2), (0x28, 0x11): ("US", columns),
        (0x28, 0x100): ("US", 8), (0x28, 0x101): ("US", 8),
        (0x28, 0x102): ("US", 7), (0x28, 0x103): ("US", 0),
    }
    if palette:
        endian = ">" if syntax == BE else "<"
        if sop == US:
            tags.update({(0x28, 0x100): ("US", 16), (0x28, 0x101): ("US", 16), (0x28, 0x102): ("US", 15)})
            pixels = struct.pack(endian + "6H", *PALETTE_INDICES)
        else:
            pixels = bytes(PALETTE_INDICES)
        # Dense 16-bit tables: four entries, first stored index 1. Replicated
        # bytes map exactly to 8-bit RGB after full-range normalization.
        for channel in range(3):
            tags[(0x28, 0x1101 + channel)] = ("US", struct.pack(endian + "3H", 4, 1, 16))
            values = [RGB[i][channel] * 257 for i in [0, 1, 2, 5]]
            tags[(0x28, 0x1201 + channel)] = ("OW", struct.pack(endian + "4H", *values))
        stored, expected = PALETTE_INDICES, PALETTE_RGB
    elif photometric == "YBR_FULL_422":
        pixels = bytes(PACKED_422)
        stored, expected = EXPANDED_422, RGB_422
    else:
        stored = YBR if photometric == "YBR_FULL" else RGB
        expected = YBR_RGB if photometric == "YBR_FULL" else RGB
        pixels = bytes([p[channel] for channel in range(3) for p in stored]
                       if planar == 1 else [value for p in stored for value in p])
    if not palette:
        tags[(0x28, 6)] = ("US", planar)
    tags[(0x7FE0, 0x10)] = ("OW" if tags[(0x28, 0x100)][1] == 16 else "OB", pixels)
    return tags, stored, expected


def cases():
    result = []

    def add(name, *, photometric="RGB", planar=0, sop=SC, syntax=LE, mutation=None,
            expectation="future_decode", reason="", step="color-1", raw_readback=False):
        tags, stored, expected = color_tags(photometric, planar, sop, syntax)
        if mutation:
            mutation(tags)
        result.append((name, tags, sop, syntax, {
            "photometric": photometric, "planar": None if photometric == "PALETTE COLOR" else tags[(0x28, 6)][1],
            "rows": tags[(0x28, 0x10)][1], "columns": tags[(0x28, 0x11)][1],
            "bits_allocated": tags[(0x28, 0x100)][1], "signed": tags[(0x28, 0x103)][1] == 1,
            "bits_stored": tags[(0x28, 0x101)][1], "high_bit": tags[(0x28, 0x102)][1],
            "pixel_data_vr": tags[(0x7FE0, 0x10)][0],
            "pixel_data_bytes": len(tags[(0x7FE0, 0x10)][1]),
            "pixel_data_sha256": hashlib.sha256(tags[(0x7FE0, 0x10)][1]).hexdigest(),
            "target_expectation": expectation, "reason": reason, "substep": step,
            "product_status": "not-run",
            "stored_expanded": stored if expectation == "future_decode" else None,
            "rgb8": expected if expectation == "future_decode" else None,
            "rgba8": [v for p in expected for v in [*p, 255]] if expectation == "future_decode" else None,
            "rgb_tolerance": 0 if photometric == "RGB" or photometric == "PALETTE COLOR" else 1,
            "raw_reader_expected": {"stored_expanded": stored, "rgb8": expected,
                "rgba8": [v for p in expected for v in [*p, 255]]} if raw_readback else None,
        }))

    add("sc-rgb-interleaved-le")
    add("sc-rgb-planar-le", planar=1)
    add("sc-rgb-planar-implicit", planar=1, syntax=IMPLICIT)
    add("sc-rgb-interleaved-be", syntax=BE)
    add("us-rgb-interleaved", sop=US, step="color-us")
    add("sc-ybr-full-interleaved", photometric="YBR_FULL")
    add("sc-ybr-full-planar", photometric="YBR_FULL", planar=1)
    add("defer-us-ybr-full-planar", photometric="YBR_FULL", planar=1, sop=US, step="color-us",
        expectation="unsupported", reason="us_native_color_requires_rgb", raw_readback=True)
    add("defer-us-ybr-full-interleaved", photometric="YBR_FULL", planar=0, sop=US, step="color-us",
        expectation="unsupported", reason="us_native_color_requires_rgb", raw_readback=True)
    add("sc-ybr-full-422", photometric="YBR_FULL_422")
    add("defer-us-ybr-full-422", photometric="YBR_FULL_422", sop=US, step="color-us",
        expectation="unsupported", reason="us_native_color_requires_rgb", raw_readback=True)
    add("sc-palette16-le", photometric="PALETTE COLOR", step="color-palette")
    add("sc-palette16-be", photometric="PALETTE COLOR", syntax=BE, step="color-palette")
    add("us-palette16", photometric="PALETTE COLOR", sop=US, step="color-palette-us")

    def replace_pixel(delta):
        def change(tags):
            vr, value = tags[(0x7FE0, 0x10)]
            tags[(0x7FE0, 0x10)] = (vr, value[:delta] if delta < 0 else value + b"\0" * delta)
        return change

    add("reject-rgb-planar2", mutation=lambda t: t.update({(0x28, 6): ("US", 2)}),
        expectation="reject", reason="undefined_planar")
    add("reject-rgb-short", mutation=replace_pixel(-2), expectation="reject", reason="short_pixel_data")
    add("reject-rgb-extra", mutation=replace_pixel(2), expectation="reject", reason="extra_pixel_data")
    add("reject-rgb-signed", mutation=lambda t: t.update({(0x28, 0x103): ("US", 1)}),
        expectation="reject", reason="unsigned_color_only")
    add("reject-rgb-rescale", mutation=lambda t: t.update({(0x28, 0x1052): ("DS", "0"), (0x28, 0x1053): ("DS", "2")}),
        expectation="reject", reason="color_rescale_not_supported")
    add("reject-422-planar1", photometric="YBR_FULL_422", planar=1,
        expectation="reject", reason="ybr422_requires_planar0")
    add("reject-422-short", photometric="YBR_FULL_422", mutation=replace_pixel(-2),
        expectation="reject", reason="short_ybr422_pixel_data")
    add("defer-422-odd-width", photometric="YBR_FULL_422",
        mutation=lambda t: t.update({(0x28, 0x11): ("US", 3), (0x7FE0, 0x10): ("OB", bytes(PACKED_422[:12]))}),
        expectation="unsupported", reason="initial_adapter_even_columns_only")
    add("reject-palette-short", photometric="PALETTE COLOR", step="color-palette",
        mutation=lambda t: t.update({(0x28, 0x1201): ("OW", t[(0x28, 0x1201)][1][:-2])}),
        expectation="reject", reason="palette_length_mismatch")
    add("reject-palette-descriptor", photometric="PALETTE COLOR", step="color-palette",
        mutation=lambda t: t.update({(0x28, 0x1102): ("US", struct.pack("<3H", 4, 2, 16))}),
        expectation="reject", reason="palette_channel_descriptor_disagreement")

    def palette8(tags):
        for channel in range(3):
            tags[(0x28, 0x1101 + channel)] = ("US", struct.pack("<3H", 4, 1, 8))
            tags[(0x28, 0x1201 + channel)] = ("OW", bytes(RGB[i][channel] for i in [0, 1, 2, 5]))
    add("defer-palette8", photometric="PALETTE COLOR", step="color-palette",
        mutation=palette8, expectation="unsupported", reason="initial_palette_dense16_only")

    def segmented(tags):
        for channel in range(3):
            tags.pop((0x28, 0x1201 + channel))
            tags[(0x28, 0x1221 + channel)] = ("OW", struct.pack("<6H", 0, 4, *[RGB[i][channel] * 257 for i in [0, 1, 2, 5]]))
    add("defer-palette-segmented", photometric="PALETTE COLOR", step="color-palette",
        mutation=segmented, expectation="unsupported", reason="segmented_palette_not_in_initial_scope")
    return result


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: prepare-color-fixtures.py CACHE_DIRECTORY")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for index, (name, tags, sop, syntax, record) in enumerate(cases(), 1):
        data = part10(index, tags, syntax, sop)
        (output / (name + ".dcm")).write_bytes(data)
        records.append({"id": name + ".dcm", "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                        "sop_class_uid": sop, "transfer_syntax_uid": syntax, "frames": 1, **record})
    manifest = {
        "task_id": "P1-ADAPTER-PREP-20261001", "revision": 2, "synthetic_only": True,
        "scope": "fixture preparation only; minimal pixel-module files, not full IOD conformance or product support",
        "standard": "DICOM PS3.3 2026d C.7.6.3 and C.8.5.6, consulted 2026-10-01",
        "standard_sources": [
            "https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.3.html",
            "https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.5.6.html",
        ],
        "oracle": "literal stored/RGB/RGBA arrays; independent reader checks; no product decoder output",
        "writer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "pixel_data_vr": "explicit OB for 8-bit pixels, OW for 16-bit pixels; implicit VR inferred by reader; palette tables OW with source syntax endian",
        "us_policy": "C.8.5.6.1.2 requires RGB for native multi-sample US. C.8-23 YBR_FULL planar0/1 row does not grant native Photometric acceptance; US YBR is unsupported target with generic raw color readback only. C.8-20 specializes dense16 palette to 16-bit unsigned indices.",
        "ybr_policy": "full-range BT.601 inverse, nearest integer then clamp; target tolerance <=1",
        "fixtures": records,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {len(records)} synthetic color boundary fixtures; product checks not-run.")


if __name__ == "__main__":
    main()
