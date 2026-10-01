#!/usr/bin/env python3
"""Read-only pydicom verification of prepared fixtures, never product support.

Run with the existing reference venv (pydicom 3.0.2; numpy version recorded). Checks every
file hash, metadata, repeated-generation bytes and normal stored/color pixels.
Negative cases check the independently stated boundary, not adapter rejection.
"""

import hashlib
import json
import platform
import sys
from pathlib import Path

import numpy as np
import pydicom
from pydicom.pixels import apply_color_lut, convert_color_space, pixel_array


class VerificationError(Exception):
    pass


def check(condition, label):
    if not condition:
        raise VerificationError(label)


def boundary(ds, reason):
    size = ds.Rows * ds.Columns * ds.SamplesPerPixel
    checks = {
        "undefined_planar": lambda: ds.PlanarConfiguration == 2,
        "short_pixel_data": lambda: len(ds.PixelData) < size,
        "extra_pixel_data": lambda: len(ds.PixelData) > size,
        "unsigned_color_only": lambda: ds.PixelRepresentation == 1,
        "us_native_color_requires_rgb": lambda: ds.SOPClassUID == "1.2.840.10008.5.1.4.1.1.6.1" and ds.file_meta.TransferSyntaxUID in {"1.2.840.10008.1.2", "1.2.840.10008.1.2.1", "1.2.840.10008.1.2.2"} and ds.SamplesPerPixel > 1 and ds.PhotometricInterpretation != "RGB",
        "color_rescale_not_supported": lambda: float(ds.RescaleSlope) == 2 and float(ds.RescaleIntercept) == 0,
        "ybr422_requires_planar0": lambda: ds.PhotometricInterpretation == "YBR_FULL_422" and ds.PlanarConfiguration == 1,
        "short_ybr422_pixel_data": lambda: len(ds.PixelData) < ds.Rows * ds.Columns * 2,
        "initial_adapter_even_columns_only": lambda: ds.Columns % 2 == 1 and len(ds.PixelData) == ds.Rows * ds.Columns * 2,
        "palette_length_mismatch": lambda: len(ds.RedPaletteColorLookupTableData) != int(ds.RedPaletteColorLookupTableDescriptor[0]) * 2,
        "palette_channel_descriptor_disagreement": lambda: list(ds.RedPaletteColorLookupTableDescriptor) != list(ds.GreenPaletteColorLookupTableDescriptor),
        "initial_palette_dense16_only": lambda: all(int(ds[tag].value[2]) == 8 for tag in [(0x28, 0x1101), (0x28, 0x1102), (0x28, 0x1103)]),
        "segmented_palette_not_in_initial_scope": lambda: all((0x28, 0x1221 + c) in ds and (0x28, 0x1201 + c) not in ds for c in range(3)),
    }
    check(reason in checks and checks[reason](), "boundary_metadata")


def verify(root, repeat):
    manifest = json.loads((root / "manifest.json").read_text())
    check(manifest == json.loads((repeat / "manifest.json").read_text()), "repeat_manifest")
    cases = manifest["fixtures"]
    names = [c["id"] for c in cases]
    check(len(names) == len(set(names)) and all(Path(n).name == n and n.endswith(".dcm") for n in names), "fixture_ids")
    check({p.name for p in root.glob("*.dcm")} == set(names), "fixture_inventory")
    results = []
    for c in cases:
        repeated = False
        try:
            data = (root / c["id"]).read_bytes()
            check(data == (repeat / c["id"]).read_bytes(), "repeat_bytes")
            repeated = True
            check(len(data) == c["bytes"] and hashlib.sha256(data).hexdigest() == c["sha256"], "file_hash")
            ds = pydicom.dcmread(root / c["id"])
            check(str(ds.SOPClassUID) == c["sop_class_uid"] == str(ds.file_meta.MediaStorageSOPClassUID), "sop_class")
            check(ds.SOPInstanceUID == ds.file_meta.MediaStorageSOPInstanceUID, "sop_instance")
            check(str(ds.file_meta.TransferSyntaxUID) == c["transfer_syntax_uid"], "syntax")
            check((ds.Rows, ds.Columns, ds.BitsAllocated, ds.PixelRepresentation == 1, ds.PhotometricInterpretation)
                  == (c["rows"], c["columns"], c["bits_allocated"], c["signed"], c["photometric"]), "pixel_metadata")
            check(int(getattr(ds, "NumberOfFrames", 1)) == c["frames"] == 1, "frames")
            check(getattr(ds, "PlanarConfiguration", None) == c["planar"], "planar")
            check(ds.BitsStored == c["bits_stored"] and ds.HighBit == c["high_bit"], "pixel_bits")
            check(ds[0x7FE00010].VR == c["pixel_data_vr"] or
                  (ds.file_meta.TransferSyntaxUID.is_implicit_VR and ds[0x7FE00010].VR in {"OB", "OW"}), "pixel_vr")
            check(len(ds.PixelData) == c["pixel_data_bytes"] and hashlib.sha256(ds.PixelData).hexdigest() == c["pixel_data_sha256"], "pixel_hash")
            record = {"id": c["id"], "fixture_sha256": c["sha256"], "preparation_status": "pass",
                      "target_expectation": c["target_expectation"], "repeat_status": "pass", "product_status": "not-run"}
            if c["target_expectation"] != "future_decode":
                check(c["target_expectation"] in {"reject", "unsupported"}, "expectation")
                check(c["stored_expanded"] is None and c["rgb8"] is None and c["rgba8"] is None, "negative_has_no_success_oracle")
                boundary(ds, c["reason"])
                record.update({"checks": "metadata/hash/repeat/boundary", "reason": c["reason"],
                               "note": "adapter rejection not executed"})
            if c["target_expectation"] == "future_decode" or c["raw_reader_expected"] is not None:
                oracle = c if c["target_expectation"] == "future_decode" else c["raw_reader_expected"]
                raw = pixel_array(ds, raw=True)
                stored = raw.reshape(-1, 3).tolist() if ds.SamplesPerPixel == 3 else raw.ravel().tolist()
                check(stored == oracle["stored_expanded"], "stored_literal")
                if ds.PhotometricInterpretation == "PALETTE COLOR":
                    color = np.rint(apply_color_lut(raw, ds).astype(np.float64) / 257).astype(np.uint8)
                elif ds.PhotometricInterpretation.startswith("YBR"):
                    color = convert_color_space(raw, "YBR_FULL", "RGB")
                else:
                    color = raw
                actual = color.reshape(-1, 3)
                expected = np.array(oracle["rgb8"], dtype=np.int16)
                error = int(np.abs(actual.astype(np.int16) - expected).max())
                # Preparation is exact to this pinned independent reader. The
                # product tolerance is separate and is not used to hide errors.
                check(error == 0, "rgb_literal")
                rgba = [value for p in actual.tolist() for value in [*p, 255]]
                check(rgba == oracle["rgba8"], "rgba_literal")
                record.update({"checks": record.get("checks", "metadata/hash/repeat") + "/stored/RGB/RGBA", "max_rgb_error": error,
                               "raw_color_readback_only": c["target_expectation"] != "future_decode",
                               "observed_stored": stored, "observed_rgba8": rgba})
            results.append(record)
        except Exception as error:
            # IDs/check codes only: never emit source paths, UIDs or raw parser
            # exception text. Every failed case keeps a failing process result.
            results.append({"id": c["id"], "preparation_status": "fail", "error_type": type(error).__name__,
                            "check": str(error) if isinstance(error, VerificationError) else "reader_error",
                            "repeat_status": "pass" if repeated else "fail", "product_status": "not-run"})
    return manifest, results


def main():
    if len(sys.argv) != 4:
        raise SystemExit("Usage: verify-color-fixtures.py CACHE_DIRECTORY REPEAT_DIRECTORY OUTPUT_JSON")
    check(pydicom.__version__ == "3.0.2", "reference_version")
    manifest, results = verify(Path(sys.argv[1]), Path(sys.argv[2]))
    passed = sum(c["preparation_status"] == "pass" for c in results)
    report = {
        "task_id": manifest["task_id"], "scope": "independent fixture preparation/readback only",
        "environment": {"python": platform.python_version(), "pydicom": pydicom.__version__, "numpy": np.__version__},
        "verifier_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "manifest_sha256": hashlib.sha256(Path(sys.argv[1], "manifest.json").read_bytes()).hexdigest(),
        "manifest": manifest, "preparation": {"pass": passed, "fail": len(results) - passed,
        "normal_color_readback": sum(c["preparation_status"] == "pass" and c.get("target_expectation") == "future_decode" for c in results),
        "raw_color_readback_only": sum(c["preparation_status"] == "pass" and c.get("raw_color_readback_only", False) for c in results),
        "normal_expected": sum(c["target_expectation"] == "future_decode" for c in manifest["fixtures"]),
        "product_checks": "not-run", "deterministic_repeat": "pass" if all(c["repeat_status"] == "pass" for c in results) else "fail"},
        "cases": results,
    }
    Path(sys.argv[3]).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["preparation"]))
    raise SystemExit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
