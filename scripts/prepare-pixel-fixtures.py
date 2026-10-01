#!/usr/bin/env python3
"""Deterministic, synthetic Part 10 fixtures; no patient data or network access.

The writer uses only struct and literal stored samples, independent of the Rust
adapter. Goldens are explicit expected Modality/RGBA values, not decoder output.
Generated files remain in the caller's cache directory, never in source control.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

LONG_VR = {"OB", "OW", "SQ", "UN"}
SC = "1.2.840.10008.5.1.4.1.1.7"
CT = "1.2.840.10008.5.1.4.1.1.2"
LE = "1.2.840.10008.1.2.1"
BE = "1.2.840.10008.1.2.2"
IMPLICIT = "1.2.840.10008.1.2"


def element(group, tag, vr, value, endian="<", implicit=False):
    if isinstance(value, str):
        value = value.encode("ascii")
        value += (b"\0" if vr == "UI" else b" ") * (len(value) % 2)
    elif isinstance(value, int):
        value = struct.pack(endian + {"US": "H", "SS": "h", "UL": "I"}[vr], value)
    elif len(value) % 2:
        value += b"\0"
    header = struct.pack(endian + "HH", group, tag)
    if implicit:
        return header + struct.pack(endian + "I", len(value)) + value
    if vr in LONG_VR:
        return header + vr.encode() + b"\0\0" + struct.pack(endian + "I", len(value)) + value
    return header + vr.encode() + struct.pack(endian + "H", len(value)) + value


def dicom(index, *, syntax=LE, color=False, frames=1, sop=None, intercept="-10",
          photometric="MONOCHROME2", stored=None, padding=True, extra=(), rows=2, columns=None):
    sop = sop or (SC if color else CT)
    columns = columns if columns is not None else (2 if color else 3)
    uid = "1.2.826.0.1.3680043.10.543.9100." + str(index)
    meta = b"".join([
        element(2, 1, "OB", b"\0\1"), element(2, 2, "UI", sop),
        element(2, 3, "UI", uid), element(2, 0x10, "UI", syntax),
        element(2, 0x12, "UI", "1.2.826.0.1.3680043.10.543.9100"),
    ])
    endian = ">" if syntax == BE else "<"
    implicit = syntax == IMPLICIT
    tags = [
        (8, 0x16, "UI", sop), (8, 0x18, "UI", uid),
        (8, 0x60, "CS", "OT" if color else "CT"),
        (0x28, 2, "US", 3 if color else 1),
        (0x28, 4, "CS", "RGB" if color else photometric),
        (0x28, 8, "IS", str(frames)),
        (0x28, 0x10, "US", rows), (0x28, 0x11, "US", columns),
        (0x28, 0x100, "US", 8 if color else 16),
        (0x28, 0x101, "US", 8 if color else 12),
        (0x28, 0x102, "US", 7 if color else 11),
        (0x28, 0x103, "US", 0 if color else 1),
    ]
    if color:
        tags.append((0x28, 6, "US", 0))
        pixels = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 17, 34, 51])
    else:
        if padding:
            tags.append((0x28, 0x120, "SS", -2048))
        tags += [(0x28, 0x1052, "DS", intercept), (0x28, 0x1053, "DS", "2")]
        # Unused high bits deliberately nonzero: BitsStored/HighBit determine
        # the signed value. A naive i16 cast would produce the wrong samples.
        words = [0xA800, 0xAFFF, 0xA000, 0xA001, 0xA400, 0xA7FF] if stored is None else [0xA000 | (sample & 0xFFF) for sample in stored]
        pixels = struct.pack(endian + str(len(words)) + "H", *words)
    tags.extend(extra)
    tags.append((0x7FE0, 0x10, "OB" if color else "OW", pixels * frames))
    body = b"".join(element(*tag, endian=endian, implicit=implicit) for tag in sorted(tags))
    return b"\0" * 128 + b"DICM" + element(2, 0, "UL", len(meta)) + meta + body


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: prepare-pixel-fixtures.py CACHE_DIRECTORY")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    fixtures = {
        "gray-le.dcm": dicom(1),
        "gray-be.dcm": dicom(2, syntax=BE),
        "gray-implicit.dcm": dicom(3, syntax=IMPLICIT),
        "rgb.dcm": dicom(4, color=True),
        "unsupported-multiframe.dcm": dicom(5, frames=2),
        "unsupported-compressed.dcm": dicom(6, syntax="1.2.840.10008.1.2.4.50"),
        "unsupported-enhanced.dcm": dicom(7, sop="1.2.840.10008.5.1.4.1.1.2.1"),
        "unsupported-overflow.dcm": dicom(8, intercept="1e100"),
        "malformed.dcm": b"not a DICOM file\n",
    }
    def window(function, center="-10", width="4"):
        return [(0x28, 0x1050, "DS", center), (0x28, 0x1051, "DS", width), (0x28, 0x1056, "CS", function)]
    fixtures.update({
        "display-linear.dcm": dicom(11, extra=window("LINEAR")),
        "display-exact.dcm": dicom(12, extra=window("LINEAR_EXACT")),
        "display-sigmoid.dcm": dicom(13, extra=window("SIGMOID")),
        "display-mono1.dcm": dicom(14, photometric="MONOCHROME1", extra=window("LINEAR_EXACT") + [(0x2050, 0x20, "CS", "INVERSE")]),
        "display-aspect.dcm": dicom(15, extra=[(0x28, 0x30, "DS", "2\\1")]),
        "display-uniform.dcm": dicom(16, stored=[0] * 6, padding=False),
        "display-padding.dcm": dicom(17, stored=[-2048] * 6),
        "invalid-window.dcm": dicom(18, extra=window("LINEAR", width="0")),
        "display-multiwindow.dcm": dicom(19, extra=window("LINEAR", center="-10\\2036", width="4\\4096")),
        "display-large-sigmoid.dcm": dicom(20, stored=[0] * 6, padding=False, intercept="3e38",
                                             extra=window("SIGMOID", center="0", width="3e38")),
        "display-opposite-sigmoid.dcm": dicom(21, stored=[0] * 6, padding=False, intercept="1e38",
                                                extra=window("SIGMOID", center="-2.5e38", width="3.4e38")),
        "display-diagnostics.dcm": dicom(22, extra=[
            (0x18, 0x1600, "CS", "RECTANGULAR"), (0x18, 0x1602, "IS", "1"),
            (0x18, 0x1604, "IS", "3"), (0x18, 0x1606, "IS", "1"), (0x18, 0x1608, "IS", "2"),
            (0x6000, 0x10, "US", 2), (0x6000, 0x11, "US", 3), (0x6000, 0x40, "CS", "G"),
            (0x6000, 0x50, "SS", struct.pack("<2h", 1, 1)), (0x6000, 0x100, "US", 1),
            (0x6000, 0x102, "US", 0), (0x6000, 0x3000, "OW", b"\x3f\x00"),
        ]),
        "display-unrenderable-window.dcm": dicom(23, extra=window("LINEAR_EXACT", center="1e100")),
        "oversized-texture.dcm": dicom(24, stored=[0] * 20000, padding=False, rows=1, columns=20000),
    })
    records = []
    for name, content in fixtures.items():
        (output / name).write_bytes(content)
        record = {"id": name, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}
        if name != "malformed.dcm":
            color = name == "rgb.dcm"
            record.update({
                "sop_class_uid": SC if color else ("1.2.840.10008.5.1.4.1.1.2.1" if "enhanced" in name else CT),
                "transfer_syntax_uid": BE if "-be" in name else (IMPLICIT if "implicit" in name else ("1.2.840.10008.1.2.4.50" if "compressed" in name else LE)),
                "rows": 1 if name == "oversized-texture.dcm" else 2,
                "columns": 20000 if name == "oversized-texture.dcm" else (2 if color else 3),
                "frames": 2 if "multiframe" in name else 1,
                "photometric": "RGB" if color else ("MONOCHROME1" if name == "display-mono1.dcm" else "MONOCHROME2"),
                "bits_allocated": 8 if color else 16, "bits_stored": 8 if color else 12,
                "high_bit": 7 if color else 11, "signed": not color,
                "expected": ("unsupported" if name.startswith("unsupported-") or name == "invalid-window.dcm"
                             else "rendering_invalid_display" if name in {"display-unrenderable-window.dcm", "oversized-texture.dcm"} else "golden_match"),
                "note": "deliberately unsupported syntax; native payload" if "compressed" in name else "synthetic stored samples",
            })
        else:
            record["expected"] = "decode_failed"
        records.append(record)
    # The oversized input is sparse on disk and rejected before parsing.
    oversized = output / "oversized.dcm"
    with oversized.open("wb") as stream:
        stream.truncate(32 * 1024 * 1024 + 1)
    records.append({"id": oversized.name, "bytes": oversized.stat().st_size, "sha256": hashlib.sha256(oversized.read_bytes()).hexdigest(), "expected": "resource_limit_before_parse"})
    manifest = {
        "revision": 2, "synthetic_only": True,
        "source": "generated locally from literal samples; no patient or external source data",
        "use": "project contract tests; generated binaries are cache-only",
        "oracle": "independent literal stored samples, slope/intercept arithmetic and RGBA bytes",
        "writer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "fixtures": records,
        "gray_expected": {"width": 3, "height": 2, "stored": [-2048, -1, 0, 1, 1024, 2047], "slope": 2, "intercept": -10,
                          "f32": [0, -12, -10, -8, 2038, 4084], "mask": [0, 1, 1, 1, 1, 1], "accounted_bytes": 30},
        "rgba_expected": [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 17, 34, 51, 255],
        "display_expected": {
            "linear": {"center": -10, "width": 4, "function": "LINEAR", "gray8": [0, 0, 170, 255, 255, 255]},
            "exact": {"center": -10, "width": 4, "function": "LINEAR_EXACT", "gray8": [0, 0, 128, 255, 255, 255]},
            "sigmoid": {"center": -10, "width": 4, "function": "SIGMOID", "gray8": [0, 30, 128, 225, 255, 255]},
            "mono1": {"inverted": True, "gray8": [0, 255, 128, 0, 0, 0]},
            "aspect": {"pixel_height_over_width": 2, "aspect_source": "pixel_spacing"},
            "uniform": {"center": -10, "width": 1, "function": "LINEAR_EXACT", "gray8": [128] * 6},
            "padding": {"default_window": None, "can_window": False, "gray8": [0] * 6},
            "multiwindow": {"centers": [-10, 2036], "widths": [4, 4096]},
            "large_sigmoid": {"center": 0, "width": 3e38, "function": "SIGMOID", "gray8": [250] * 6},
            "opposite_sigmoid": {"center": -2.5e38, "width": 3.4e38, "function": "SIGMOID", "gray8": [251] * 6},
            "diagnostics": ["overlay_not_applied", "shutter_not_applied"],
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {len(records)} synthetic fixtures and independent literal goldens.")


if __name__ == "__main__":
    main()
